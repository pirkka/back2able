require "sinatra"
require 'stringio'
require 'zlib'
require_relative 'als_converter'

set :bind, "0.0.0.0"
port = ENV["PORT"] || "8080"
set :port, port

configure :production do
  set :bind, '0.0.0.0'
  set :port, ENV['PORT'] || 8080

  # Only accept cross-origin form posts from our own site. The app runs behind
  # Cloudflare and kamal-proxy, both of which forward the original Origin header.
  set :protection, origin_whitelist: ['https://back2able.odj.fi']
end

# DEPLOYMENT:
# The app is deployed as a Docker container to a Hetzner VPS with Kamal.
# See config/deploy.yml and deploy.sh. Run it locally with: 'bundle exec ruby app.rb'

get "/" do
  send_file File.join(settings.public_folder, "index.html")
end

get "/up" do
  "ok"
end

post "/convert" do
  upload = params['file']
  tempfile = upload && upload[:tempfile]
  filename = upload && upload[:filename]

  if filename && filename.end_with?('.als') && tempfile
    als_file = tempfile
    output_name = filename.sub(/\.als\z/i, '_L11.als')

    begin
      xml_content = nil
      begin
      File.open(als_file) do |f|
        gz = Zlib::GzipReader.new(f)
        xml_content = gz.read
        gz.close
      end 
      rescue Zlib::GzipFile::Error => e
        # Not gzipped: rewind, the failed header read consumed some bytes.
        als_file.rewind if als_file.respond_to?(:rewind)
        xml_content = als_file.read
      end
      output_string = AlsConverter.convert(xml_content)

      # Ableton .als files are gzipped XML, so serve the compressed form.
      content_type 'application/octet-stream'
      attachment File.basename(output_name)
      gzip(output_string)
    rescue REXML::ParseException => e
      status 400
      "Error parsing XML: #{e.message}"
    rescue => e
      status 500
      "An error occurred: #{e.message}"
    end
  else
    status 400
    "No file uploaded or file is invalid."
  end
end

helpers do
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
