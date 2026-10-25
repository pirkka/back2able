require "sinatra"
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
  content_type :html
  "<!DOCTYPE html>" + \
  "<html lang='en'>" + \
  "<head>" + \
  "<meta charset='UTF-8'>" + \
  "<meta name='viewport' content='width=device-width, initial-scale=1.0'>" + \
  "<title>back2able - ableton live project file downgrading utility</title>" + \
  "<style>" + \
  "body { margin: 0; padding: 0; }" + \
  ".content { max-width: 800px; margin: 0 auto; padding: 20px; background: #B7B7B7; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1);} input {font-size: 0.5em;} form {background-color: #ccc; padding: 0.5em; border-radius: 0.4em;}" + \
  "</style>" + \
  "</head>" + \
  "<body style='font-family: Manual, Avenir, Verdana, Arial, sans-serif; font-size: 2.5em; padding: 20px; background: #8F8F8F; text-align: center;'>" + \
  "<div class='content'>" + \
  "<img src='/back2able.png' style='max-width: 800px;'>" + \
  "<p>Please upload an Ableton Live 12 file (.als) to convert it to Ableton Live 11.</p>" + \
  "<form action='/convert' method='post' enctype='multipart/form-data'>" + \
  "<input type='file' name='file' accept='.als'>" + \
  "<input type='submit' value='Convert'>" + \
  "</form>" + \
  "<p>If the resulting file does not open in Live 11, please take a screencap of the error and send to odjpirkka@gmail.com.</p>" + \
  "</div>" + \
  "</body>" + \
  "</html>"
end

get "/up" do
  "ok"
end

post "/convert" do
  tempfile = params['file'][:tempfile]
  filename = params['file'][:filename]

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

      content_type 'application/xml'
      attachment File.basename(output_name)
      output_string
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
