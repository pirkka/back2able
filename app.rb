require "sinatra"
require 'stringio'
require 'zlib'
require_relative 'als_converter'

set :bind, "0.0.0.0"
port = ENV["PORT"] || "8080"
set :port, port

# Cloudflare caches .js and .css for four hours by default, which would leave
# visitors with an outdated page after a deploy. Always revalidate instead.
set :static_cache_control, :no_cache

# Cross-origin form posts are rejected explicitly. Rack::Protection's origin
# check cannot do this: Sinatra sets the reaction to :drop_session and the app
# has no sessions, so a rejected request would still be served.
ALLOWED_ORIGINS = (ENV["ALLOWED_ORIGINS"] || "https://back2able.odj.fi,http://back2able.odj.fi").split(",").map(&:strip).reject(&:empty?).freeze
UNSAFE_METHODS = %w[POST PUT PATCH DELETE].freeze

# Limits. The conversion builds a REXML document in memory, which takes roughly
# 25-35x the size of the project file, so the project size is capped well
# below what the server could physically handle.
MAX_UPLOAD_BYTES = Integer(ENV.fetch("MAX_UPLOAD_MB", "20")) * 1024 * 1024
MAX_XML_BYTES = Integer(ENV.fetch("MAX_XML_MB", "30")) * 1024 * 1024
MAX_CONCURRENT = Integer(ENV.fetch("MAX_CONCURRENT", "1"))
QUEUE_WAIT_SECONDS = Integer(ENV.fetch("QUEUE_WAIT_SECONDS", "60"))
RATE_LIMIT_COUNT = Integer(ENV.fetch("RATE_LIMIT_COUNT", "30"))
RATE_LIMIT_WINDOW_SECONDS = Integer(ENV.fetch("RATE_LIMIT_WINDOW_SECONDS", "600"))

class FileTooLarge < StandardError; end
class ServerBusy < StandardError; end
class RateLimited < StandardError; end

# Allows a limited number of conversions to run at the same time. Requests that
# do not get a slot within the timeout are rejected.
class ConcurrencyLimiter
  def initialize(limit)
    @limit = limit
    @mutex = Mutex.new
    @condition = ConditionVariable.new
    @active = 0
  end

  def acquire(timeout)
    @mutex.synchronize do
      deadline = monotonic_now + timeout

      while @active >= @limit
        remaining = deadline - monotonic_now
        return false if remaining <= 0
        @condition.wait(@mutex, remaining)
      end

      @active += 1
      true
    end
  end

  def release
    @mutex.synchronize do
      @active -= 1
      @condition.signal
    end
  end

  private

  def monotonic_now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end

# Counts conversions started in a sliding window.
class RateLimiter
  def initialize(count, window)
    @count = count
    @window = window
    @mutex = Mutex.new
    @timestamps = []
  end

  def allow?
    @mutex.synchronize do
      now = Time.now.to_f
      @timestamps.reject! { |timestamp| now - timestamp > @window }
      return false if @timestamps.size >= @count
      @timestamps << now
      true
    end
  end
end

CONVERSIONS = ConcurrencyLimiter.new(MAX_CONCURRENT)
RATE_LIMITER = RateLimiter.new(RATE_LIMIT_COUNT, RATE_LIMIT_WINDOW_SECONDS)

configure :production do
  set :bind, '0.0.0.0'
  set :port, ENV['PORT'] || 8080

  # The app runs behind Cloudflare and kamal-proxy, which forward the original
  # Origin header.
  before do
    next unless UNSAFE_METHODS.include?(request.request_method)

    origin = request.env["HTTP_ORIGIN"]
    halt 403, "Forbidden" if origin && !ALLOWED_ORIGINS.include?(origin)
  end
end

# DEPLOYMENT:
# The app is deployed as a Docker container to a Hetzner VPS with Kamal.
# See config/deploy.yml and deploy.sh. Run it locally with: 'bundle exec ruby app.rb'

get "/" do
  headers "Cache-Control" => "no-cache"
  erb :index
end

get "/up" do
  "ok"
end

post "/convert" do
  upload = params['file']
  tempfile = upload && upload[:tempfile]
  filename = upload && upload[:filename]

  unless filename && filename.end_with?('.als') && tempfile
    status 400
    "No file uploaded or file is invalid."
  else
    begin
      convert(tempfile, filename)
    rescue FileTooLarge => e
      status 413
      e.message
    rescue RateLimited => e
      headers "Retry-After" => "30"
      status 429
      e.message
    rescue ServerBusy => e
      headers "Retry-After" => "30"
      status 503
      e.message
    rescue REXML::ParseException => e
      status 400
      "Error parsing XML: #{e.message}"
    rescue => e
      status 500
      "An error occurred: #{e.message}"
    end
  end
end

helpers do
  # The asset URLs carry the deploy version, so a deploy always gets fresh
  # JavaScript and CSS instead of whatever Cloudflare has cached.
  def asset_version
    ENV["KAMAL_VERSION"] || "dev"
  end

  def convert(tempfile, filename)
    output_name = filename.sub(/\.als\z/i, '_L11.als')

    if tempfile.size > MAX_UPLOAD_BYTES
      raise FileTooLarge, "The file is too large (limit #{MAX_UPLOAD_BYTES / 1024 / 1024} MB)."
    end

    unless RATE_LIMITER.allow?
      raise RateLimited, "Too many conversions right now, please try again shortly."
    end

    unless CONVERSIONS.acquire(QUEUE_WAIT_SECONDS)
      raise ServerBusy, "The server is busy, please try again in a minute."
    end

    begin
      output_string = AlsConverter.convert(read_project(tempfile))

      # Ableton .als files are gzipped XML, so serve the compressed form.
      content_type 'application/octet-stream'
      attachment File.basename(output_name)
      gzip(output_string)
    ensure
      CONVERSIONS.release
    end
  end

  # Reads the project XML, refusing to load more than MAX_XML_BYTES so that a
  # huge upload cannot exhaust the server.
  def read_project(file)
    content = nil

    begin
      gz = Zlib::GzipReader.new(file)
      content = gz.read(MAX_XML_BYTES + 1)
      gz.close
    rescue Zlib::GzipFile::Error
      # Not gzipped: rewind, the failed header read consumed some bytes.
      file.rewind if file.respond_to?(:rewind)
      content = file.read(MAX_XML_BYTES + 1)
    end

    if content.bytesize > MAX_XML_BYTES
      raise FileTooLarge, "The project is too large (limit #{MAX_XML_BYTES / 1024 / 1024} MB)."
    end

    content
  end

  # Gzip in memory, with a fixed timestamp so the same input always gives the
  # same output.
  def gzip(data)
    buffer = StringIO.new
    writer = Zlib::GzipWriter.new(buffer)
    writer.mtime = 0
    writer.write(data)
    writer.close
    buffer.string
  end
end
