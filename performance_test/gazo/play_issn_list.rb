#!/usr/bin/ruby

# Makes requests to Gazo staging based on input containing lines with timestamp and a list of ISSNs.
# Logs request times and the distribution of ISSNs
#
# Unless otherwise specified via the -t argument, requests will be sent using the same time intervals
# as was in the input file.
#
# HTTP return codes other than 200 and 404 will be reported along with the ISSN that caused it on STDERR.

require 'httparty'
require 'getopt/long'

opt = Getopt::Long.getopts(
  # Name of file to log ISSN numbers in
  ['--issn-log', '-i', Getopt::REQUIRED],
  # Name of file to log request times in
  ['--request-time-log' '-r', Getopt::REQUIRED],
  # Time factor for speeding up or slowing down sleep intervals between requests
  ['--time-factor', '-t', Getopt::REQUIRED],
  # Destination of retrieved cover images
  ['--image-dir', '-d', Getopt::REQUIRED],
  # API key for image service
  ['--api-key', '-a', Getopt::REQUIRED],
  # Image service URL
  ['--image-service-url', '-u', Getopt::REQUIRED]
)

# Optional arguments
time_factor = (opt['t'] || 1.0).to_f

# Mandatory arguments
api_key = opt['a']
issn_log_file = opt['i']
request_time_log_file = opt['r']
image_url = opt['u']
image_dir = opt['d']

if !api_key || !issn_log_file || !request_time_log_file || !image_url || !image_dir || opt.empty?
  puts "Usage: #{__FILE__} -r <request-time-log> -i <issn-log> -d <image-dir> -a <api-key> -u image_service_url [-t <time-factor>]"
  exit 0
end

# Will hold request times for getting all ISSNs belonging to a single original search request
request_times = []

# Will hold ISSN distribution
issn_stats = {}

previous_timestamp = nil

STDIN.each do |line|
  case line
  when /^(.+?): (.+)/
    timestamp, issns = $1, ($2.split ',')
    # Convert from ETH's strange date format
    timestamp = "#{$1} #{$2} #{$3}:#{$4}:#{$5} #{$6}" if timestamp =~ /^(.+?)_(\d+)_(\d+)_(\d+)_(\d+)_(\d+)/

    start_all = Time.now
    issns.each do |issn|
      response = HTTParty.get URI.encode("#{image_url}/api/#{api_key}/#{issn}/native.png")
      File.open "#{image_dir}/#{issn}.png", 'w' do |f|
        f.write response.body
      end
      STDERR.puts "HTTP #{response.code} for ISSN #{issn}" and STDERR.flush unless [200, 404].include? response.code
      issn_stats[issn] = 0 unless issn_stats.has_key? issn
      issn_stats[issn] += 1
    end

    request_times << { :timestamp => Time.now, :request_time => (Time.now - start_all) }

    # Sleep until next timestamp
    if previous_timestamp
      t1 = Time.parse previous_timestamp
      t2 = Time.parse timestamp
      puts "Next request (original time: #{timestamp}) in #{(t2 - t1) / time_factor} seconds"
      sleep (t2 - t1) / time_factor
    end
    previous_timestamp = timestamp
  end
end

File.open request_time_log_file, 'w' do |f|
  request_times.each do |hash|
    f.puts "#{hash[:timestamp]}: #{hash[:request_time]}"
  end
end

File.open issn_log_file, 'w' do |f|
  issn_stats.each do |issn, counter|
    f.puts "#{issn}: #{counter}"
  end
end
