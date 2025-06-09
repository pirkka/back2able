#!/usr/bin/env ruby

require 'rexml/document'
require 'pathname'
require 'zlib'

# This script converts Ableton Live Set files (.als) to be compatible with Ableton Live 11.
# Author: Pirkka Esko

# TODO:
# - https://cloud.google.com/run/docs/quickstarts/build-and-deploy/deploy-ruby-service
# - https://ablegrade-341817698190.europe-north1.run.app
# - Add support for more versions of Ableton Live

# Check if filename argument is provided
if ARGV.empty?
  puts "Usage: #{$0} <xml_file>"
  exit 1
end

als_file = ARGV[0]
output_file = als_file.gsub('.als', '_L11.als')

# Check if file exists
unless File.exist?(als_file)
  puts "Error: File '#{als_file}' not found"
  exit 1
end

begin
  xml_content = nil
  File.open(als_file) do |f|
    gz = Zlib::GzipReader.new(f)
    xml_content = gz.read
    gz.close
  end

  doc = REXML::Document.new(xml_content)

  # EDIT THE XML TO WORK WITH ABLETON LIVE 11
  # <Ableton MajorVersion="5" MinorVersion="11.0_11300" SchemaChangeCount="7" Creator="Ableton Live 11.3.40b2" Revision="97b2aa4f9e88ecec40a7dc6f0e9c707631d5a5c7">
  # 
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

  puts "Converted '#{als_file}' to '#{output_file}' successfully."

rescue REXML::ParseException => e
  puts "Error parsing XML: #{e.message}"
  exit 1
rescue => e
  puts "Error reading file: #{e.message}"
  exit 1
end