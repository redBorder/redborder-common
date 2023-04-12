#!/usr/bin/ruby

#######################################################################
## Copyright (c) 2014 ENEO Tecnología S.L.
## This file is part of redBorder.
## redBorder is free software: you can redistribute it and/or modify
## it under the terms of the GNU Affero General Public License License as published by
## the Free Software Foundation, either version 3 of the License, or
## (at your option) any later version.
## redBorder is distributed in the hope that it will be useful,
## but WITHOUT ANY WARRANTY; without even the implied warranty of
## MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
## GNU Affero General Public License License for more details.
## You should have received a copy of the GNU Affero General Public License License
## along with redBorder. If not, see <http://www.gnu.org/licenses/>.
########################################################################

require 'json'
require "getopt/std"
require 'net/http'

opt = Getopt::Std.getopts("hcelmnu")

def usage 
  printf("USAGE: rb_get_logstash_stats.sh [-h][-c][-l][-m][-n][-u]\n")
  printf("  * -h -> get this help\n")
  printf("  * -c -> get logstash cpu percent\n")
  printf("  * -e -> get logstash in events\n")
  printf("  * -l -> get logstash load average 1m\n")
  printf("  * -m -> get logstash load average 5m\n")
  printf("  * -n -> get logstash load average 15m\n")
  printf("  * -u -> get logstash heap used percent\n")
end


def get_size(node, url)
  return JSON.parse(Net::HTTP.get(URI.parse("http://#{node}/#{url}"))).size
end

def get_elements(node, url)
  return Net::HTTP.get(URI.parse("http://#{node}/#{url}"))
end

logstash="localhost:9600"

if opt["h"] or opt.empty?
  usage
elsif opt["c"]
  print JSON.parse(Net::HTTP.get(URI.parse("http://#{logstash}/_node/stats/process?pretty")))["process"]["cpu"]["percent"]
  printf("\n")
elsif opt["e"]
  print JSON.parse(Net::HTTP.get(URI.parse("http://#{logstash}/_node/stats/events?pretty")))["events"]["in"]
  printf("\n")
elsif opt["l"]
  print JSON.parse(Net::HTTP.get(URI.parse("http://#{logstash}/_node/stats/process?pretty")))["process"]["cpu"]["load_average"]["1m"]
  printf("\n")
elsif opt["m"]
  print JSON.parse(Net::HTTP.get(URI.parse("http://#{logstash}/_node/stats/process?pretty")))["process"]["cpu"]["load_average"]["5m"]
  printf("\n")
elsif opt["n"]
  print JSON.parse(Net::HTTP.get(URI.parse("http://#{logstash}/_node/stats/process?pretty")))["process"]["cpu"]["load_average"]["15m"]
  printf("\n")
elsif opt["u"]
  print JSON.parse(Net::HTTP.get(URI.parse("http://#{logstash}/_node/stats/jvm?pretty")))["jvm"]["mem"]["heap_used_percent"]
  printf("\n")
end
