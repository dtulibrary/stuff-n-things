#!/usr/bin/ruby

# Extracts all ISSNs found in search results based on queries parsed from STDIN and 
# outputs them to STDOUT.
#
# Each line on STDIN should be on the form
# <time-stamp> | <start> | <rows> | <query-string>
# 
# Example:
#  2012-03-06 10:00:06.031965+01 |     0 |   25 | author:(brunetti) title:(Rayleigh-rejection)
#
# The -u argument should point to an instance of the infonet backend like for example
# http://localhost:8080/data
#
# Queries where no ISSNs can be found in the search result will be reported on STDERR

require 'httparty'
require 'uri'
require 'getopt/long'

query = nil
timestamp = nil
start = nil
rows = nil

opt = Getopt::Long.getopts(
  ['--infonet-backend-url', '-u', Getopt::REQUIRED]
)

$backend_url = opt['u']

unless $backend_url
  puts "Usage: #{__FILE__} -u <infonet-backend-url>"
  exit 0
end

# Extract all ISSNs from a single member blob
def extract_issns member_xml
  issns = []
  member_xml.scan /<journal>(.*?)<\/journal>/m do |journal_xml, _|
    journal_xml.scan /<issn>(.*?)<\/issn>|<eissn>(.*?)<\/eissn>/ do |issn, eissn, _|
      issns << (issn || eissn)
      break
    end
  end
  issns
end

# Extract ISSNs from a page in a result set
def find_issns query, start, rows
  issns = []
  xml = HTTParty.get("#{$backend_url}/article/?q=#{URI.encode query}&start=#{start}&limit=#{rows}&media=xml").body
  xml.scan /<inf:cluster .*?>(.*?)<\/inf:cluster>/m do |cluster_xml, _|
    members = {}
    cluster_xml.scan /<inf:member (.*?)>(.*?)<\/inf:member>/m do |member_attributes, member_xml, _|
      member_type = $1 if member_attributes =~ /type=\"(.*?)\"/
      members[member_type] = [] unless members.has_key? member_type
      members[member_type] << member_xml
    end

    # Make the same member selection as DLIB UI does
    if members.has_key? 'publisher'
      issns += extract_issns members['publisher'][0]
    elsif members.has_key? 'database'
      issns += extract_issns members['database'][0]
    elsif !members.empty?
      issns += extract_issns members.first[1][0]
    end
  end
  issns
end

STDIN.each do |line|
  case line
  when /^\s*(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\S+) \| \s*(\d+) \| \s*(\d+) \| (.*)/
    # This is the beginning of a new query
    if query
      # Finish up the previous query being read
      issns = find_issns query, start, rows
      puts "#{timestamp}: #{issns.join ','}" and STDOUT.flush unless issns.empty?
      STDERR.puts "Empty query: offset=#{start}, limit=#{rows}, query=#{query}" and STDERR.flush if issns.empty?
    end
    timestamp, start, rows, query = $1, $2, $3, $4
  when /^\s+: (.*)/
    # This is from a query that spans multiple lines - for example due to a newline in the content.
    query += $1 if $1
  end
end
