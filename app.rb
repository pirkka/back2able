require "sinatra"
require 'rexml/document'
require 'pathname'
require 'zlib'

set :bind, "0.0.0.0"
port = ENV["PORT"] || "8080"
set :port, port

configure :production do
  set :bind, '0.0.0.0'
  set :port, ENV['PORT'] || 8080
  
  # Trust proxy headers from Cloud Run
  set :protection, origin_whitelist: ['https://back2able.odj.fi']
  
  # If you need to check if the original request was HTTPS
  before do
    @https = request.env['HTTP_X_FORWARDED_PROTO'] == 'https'
  end
end

# SERVER DEPLOYMENT:
# To deploy this script as a server, you can use Google Cloud Run or any other cloud service that supports Ruby applications.
# The script can be run as a web service that accepts file uploads and returns the converted .als file.
# 
# For Google Cloud Run, you would typically create a Dockerfile that sets up the Ruby environment, installs dependencies, and runs this script.
# You can use a web framework like Sinatra or Rails to handle HTTP requests and responses.
# 
# here is the command to deploy in terminal: 'gcloud run deploy'
# here is the way to run the server locally: 'rerun ruby app.rb'

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
  ".content { max-width: 800px; margin: 0 auto; padding: 20px; background: #B7B7B7; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }" + \
  "</style>" + \
  "</head>" + \
  "<body style='font-family: Manual, Avenir, Verdana, Arial, sans-serif; font-size: 2.5em; padding: 20px; background: #8F8F8F; text-align: center;'>" + \
  "<div class='content'>" + \
  "<img src='/back2able.png' style='max-width: 800px;'>" + \
  "<p>Please upload an Ableton Live 12 file (.als) to convert it to Ableton Live 11.</p>" + \
  "<p>If the resulting file does not open in Live 11, please take a screencap of the error and send to odjpirkka@gmail.com.</p>" + \
  "<form action='/convert' method='post' enctype='multipart/form-data'>" + \
  "<input type='file' name='file' accept='.als'>" + \
  "<input type='submit' value='Convert'>" + \
  "</form>" + \
  "</div>" + \
  "</body>" + \
  "</html>"
end

post "/convert" do
  tempfile = params['file'][:tempfile]
  filename = params['file'][:filename]

  if filename && filename.end_with?('.als') && tempfile
    als_file = tempfile
    output_file = filename.gsub('.als', '_L11.als')

    begin
      xml_content = nil
      begin
      File.open(als_file) do |f|
        gz = Zlib::GzipReader.new(f)
        xml_content = gz.read
        gz.close
      end 
      rescue Zlib::GzipFile::Error => e
        xml_content = als_file.read
      end
      doc = REXML::Document.new(xml_content)

      # EDIT THE XML TO WORK WITH ABLETON LIVE 11
      doc.root.attributes['MajorVersion'] = '5'
      doc.root.attributes['MinorVersion'] = '11.0_11300'
      doc.root.attributes['Creator'] = 'Ableton Live 11.3.40b2'
      doc.root.attributes['Revision'] = '97b2aa4f9e88ecec40a7dc6f0e9c707631d5a5c7'

      # remove MidiEditorLaneModel elements
      doc.elements.each('//MidiEditorLaneModel') do |element|
        element.parent.delete_element(element)
      end

      ouput_string = doc.to_s
      ouput_string = ouput_string.gsub("Value='true'", "Value='1'")
      ouput_string = ouput_string.gsub("Value='false'", "Value='0'")

      File.open(output_file, 'w') do |f|
        f.write(ouput_string)
      end

      #Zlib::GzipWriter.open('output_file') do |gz|
      #  gz.write doc.to_s
      #end

      send_file output_file, filename: File.basename(output_file), type: 'application/xml'
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