#!/usr/bin/env ruby

require 'optparse'
require 'zlib'
require_relative 'als_converter'

options = { compress: true }

parser = OptionParser.new do |opts|
  opts.banner = "Usage: #{$0} [options] <xml_file>"
  opts.on('-z', '--compress', 'Gzip the output .als (default)') { options[:compress] = true }
  opts.on('--no-compress', 'Write uncompressed XML .als') { options[:compress] = false }
  opts.on('-h', '--help', 'Show this help') { puts opts; exit }
end

parser.parse!

if ARGV.empty?
  puts parser
  exit 1
end

als_file = ARGV[0]
output_file = als_file.sub(/\.als\z/i, '_L11.als')

unless File.exist?(als_file)
  puts "Error: File '#{als_file}' not found"
  exit 1
end

begin
  xml_content = File.open(als_file, 'rb') do |file|
    magic = file.read(2)
    file.rewind
    if magic == "\x1f\x8b".b
      gzip = Zlib::GzipReader.new(file)
      content = gzip.read
      gzip.close
      content
    else
      file.read
    end
  end

  output = AlsConverter.convert(xml_content)

  if options[:compress]
    Zlib::GzipWriter.open(output_file) { |gzip| gzip.write(output) }
  else
    File.open(output_file, 'wb') { |file| file.write(output) }
  end

  puts "Converted '#{als_file}' to '#{output_file}' successfully."
rescue REXML::ParseException => e
  puts "Error parsing XML: #{e.message}"
  exit 1
rescue => e
  puts "Error converting file: #{e.message}"
  exit 1
end
