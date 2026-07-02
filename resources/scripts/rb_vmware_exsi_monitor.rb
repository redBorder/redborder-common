#!/usr/bin/env ruby

########################################################################
# Copyright (c) 2026 ENEO Tecnología S.L.
# This file is part of redBorder.
# redBorder is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# redBorder is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License License for more details.
# You should have received a copy of the GNU Affero General Public License License
# along with redBorder. If not, see <http://www.gnu.org/licenses/>.
# ######################################################################

require 'optparse'
require 'json'
require 'fileutils'
require 'open3'
require 'tmpdir'

class VMwareESXiMonitor
  class ExecutionError < StandardError; end

  SUPPORTED_METRICS = %w[cpu memory disk].freeze

  def initialize(options)
    @host = options[:host]
    @user = options[:user]
    @password = options[:password]
    @metric = options[:metric]&.downcase
  end

  def run
    validate_options!
    setup_environment!
    
    case @metric
    when 'cpu'
      puts sprintf("%.2f", query_cpu_usage)
    when 'memory'
      puts sprintf("%.2f", query_memory_usage)
    when 'disk'
      puts query_disk_usage.join(';')
    else
      raise ArgumentError, "Unsupported metric: #{@metric}"
    end
  end

  private

  def validate_options!
    raise ArgumentError, "Missing required host parameter (-i)" if @host.nil? || @host.empty?
    raise ArgumentError, "Missing required username parameter (-u)" if @user.nil? || @user.empty?
    raise ArgumentError, "Missing required password parameter (-p)" if @password.nil? || @password.empty?
    raise ArgumentError, "Missing required metric parameter (-t)" if @metric.nil? || @metric.empty?
    raise ArgumentError, "Unsupported metric: #{@metric}. Supported metrics are: #{SUPPORTED_METRICS.join(', ')}" unless SUPPORTED_METRICS.include?(@metric)
  end

  def setup_environment!
    ENV['GOVC_URL'] = "https://#{@user}:#{@password}@#{@host}/sdk"
    ENV['GOVC_INSECURE'] = "true"
    ENV['GOVC_PERSIST_SESSION'] = "false"
    
    # Isolate session directory to avoid write permissions errors
    govc_home = File.join(Dir.tmpdir, "govc-home-#{Process.uid}")
    ENV['HOME'] = govc_home
    ENV['GOVC_HOME'] = govc_home
    
    begin
      FileUtils.mkdir_p(govc_home)
    rescue => e
      warn "Warning: Failed to create GOVC directory #{govc_home}: #{e.message}"
    end
  end

  def execute_command(*args)
    stdout, stderr, status = Open3.capture3(*args)
    unless status.success?
      handle_error!(stderr, args)
    end
    stdout
  end

  def handle_error!(stderr, args)
    err_msg = stderr.strip
    err_msg_down = err_msg.downcase
    if err_msg_down.include?("connection refused") || err_msg_down.include?("no such host") || err_msg_down.include?("i/o timeout")
      raise ExecutionError, "Host #{@host} is unreachable or connection timed out."
    elsif err_msg_down.include?("unauthorized") || err_msg_down.include?("login failed") ||
          err_msg_down.include?("incorrect user name") || err_msg_down.include?("incorrect username")
      raise ExecutionError, "Authentication failed for user #{@user} on host #{@host}."
    else
      raise ExecutionError, err_msg.empty? ? "Command '#{args.join(' ')}' failed." : err_msg
    end
  end

  def fetch_host_info
    output = execute_command('/usr/bin/govc', 'host.info', '-json')
    data = JSON.parse(output)
    host_systems = data['HostSystems'] || data['hostSystems']
    raise ExecutionError, "No HostSystem found in govc response" if host_systems.nil? || host_systems.empty?
    host_systems[0]
  end

  def query_cpu_usage
    host_system = fetch_host_info
    summary = host_system['Summary'] || host_system['summary'] || {}
    quick_stats = summary['quickStats'] || summary['QuickStats'] || {}
    hardware = summary['hardware'] || summary['Hardware'] || {}

    usage = quick_stats['overallCpuUsage'].to_f
    cpu_mhz = hardware['cpuMhz'].to_f
    num_cores = hardware['numCpuCores'].to_f
    total = cpu_mhz * num_cores

    total > 0 ? (usage / total) * 100.0 : 0.0
  end

  def query_memory_usage
    host_system = fetch_host_info
    summary = host_system['Summary'] || host_system['summary'] || {}
    quick_stats = summary['quickStats'] || summary['QuickStats'] || {}
    hardware = summary['hardware'] || summary['Hardware'] || {}

    usage_mb = quick_stats['overallMemoryUsage'].to_f
    memory_size_bytes = hardware['memorySize'].to_f
    total_mb = memory_size_bytes / (1024.0 * 1024.0)

    total_mb > 0 ? (usage_mb / total_mb) * 100.0 : 0.0
  end

  def query_disk_usage
    output = execute_command('/usr/bin/govc', 'datastore.info', '-json')
    data = JSON.parse(output)
    datastores = data['Datastores'] || data['datastores'] || []
    
    datastores.map do |ds|
      summary = ds['Summary'] || ds['summary'] || {}
      capacity = summary['capacity'].to_f
      free_space = summary['freeSpace'].to_f
      used = capacity - free_space
      percent = capacity > 0 ? (used / capacity) * 100.0 : 0.0
      sprintf("%.2f", percent)
    end
  end
end

if __FILE__ == $0
  options = {}
  OptionParser.new do |opts|
    opts.banner = "Usage: rb_vmware_exsi_monitor.rb [options]"

    opts.on('-i', '--host HOST-IP', 'Host IP') { |o| options[:host] = o }
    opts.on('-u', '--user USER', 'Username') { |o| options[:user] = o }
    opts.on('-p', '--password PASSWORD', 'Password') { |o| options[:password] = o }
    opts.on('-t', '--metric METRIC', "Metric (#{VMwareESXiMonitor::SUPPORTED_METRICS.join(', ')})") { |o| options[:metric] = o }
  end.parse!

  begin
    monitor = VMwareESXiMonitor.new(options)
    monitor.run
  rescue ArgumentError => e
    STDERR.puts "Error: #{e.message}"
    exit 1
  rescue VMwareESXiMonitor::ExecutionError => e
    STDERR.puts "Error: #{e.message}"
    exit 1
  rescue => e
    STDERR.puts "Error: #{e.class} - #{e.message}"
    exit 1
  end
end
