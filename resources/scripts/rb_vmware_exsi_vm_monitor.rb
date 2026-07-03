#!/usr/bin/env ruby
#
# #######################################################################
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
#

require 'optparse'
require 'json'
require 'fileutils'
require 'open3'
require 'tmpdir'

class VMwareESXiVMMonitor
  class ExecutionError < StandardError; end

  SUPPORTED_METRICS = %w[cpu memory disk power].freeze

  def initialize(options)
    @host = options[:host]
    @user = options[:user]
    @password = options[:password]
    @name = options[:name]
    @metric = options[:metric]&.downcase
    @verbose = options[:verbose]
  end

  def run
    validate_options!
    setup_environment!

    # 1. Fetch VM Info to check powerState and basic properties
    vm = fetch_vm_info
    runtime = vm['Runtime'] || vm['runtime'] || {}
    power_state = runtime['PowerState'] || runtime['powerState']

    # Handle power metric directly
    if @metric == 'power'
      state_val = (power_state == 'poweredOn') ? 1.00 : 0.00
      puts sprintf("%.2f", state_val)
      return
    end

    # For other metrics, if the VM is not poweredOn, return 0.00
    if power_state != 'poweredOn'
      puts "0.00"
      return
    end

    case @metric
    when 'cpu'
      puts sprintf("%.2f", query_cpu_usage)
    when 'memory'
      puts sprintf("%.2f", query_memory_usage(vm))
    when 'disk'
      puts sprintf("%.2f", query_disk_usage(vm))
    else
      raise ArgumentError, "Unsupported metric: #{@metric}"
    end
  end

  private

  def validate_options!
    raise ArgumentError, "Missing required host parameter (-i)" if @host.nil? || @host.empty?
    raise ArgumentError, "Missing required username parameter (-u)" if @user.nil? || @user.empty?
    raise ArgumentError, "Missing required password parameter (-p)" if @password.nil? || @password.empty?
    raise ArgumentError, "Missing required VM name parameter (-n)" if @name.nil? || @name.empty?
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
    elsif err_msg_down.include?("not found")
      raise ExecutionError, "VM '#{@name}' not found on host #{@host}."
    else
      raise ExecutionError, err_msg.empty? ? "Command '#{args.join(' ')}' failed." : err_msg
    end
  end

  def fetch_vm_info
    output = execute_command('/usr/bin/govc', 'vm.info', '-json', @name)
    data = JSON.parse(output)
    vms = data['VirtualMachines'] || data['virtualMachines']
    raise ExecutionError, "VM #{@name} not found on host #{@host}." if vms.nil? || vms.empty?
    vms[0]
  end

  def query_cpu_usage
    # Use govc find to locate the exact VM path
    vm_path = execute_command('/usr/bin/govc', 'find', '.', '-name', @name).strip
    raise ExecutionError, "Could not find VM path for #{@name}." if vm_path.empty?

    # Sample performance metric cpu.usage.average
    metric_output = execute_command('/usr/bin/govc', 'metric.sample', '-json', vm_path, 'cpu.usage.average')
    metric_data = JSON.parse(metric_output)
    sample = metric_data['sample'] || metric_data['Sample']
    raise ExecutionError, "No performance metrics returned for VM #{@name}." if sample.nil? || sample.empty?

    values = sample[0]['value'] || sample[0]['Value']
    raise ExecutionError, "No values in performance sample for VM #{@name}." if values.nil? || values.empty?

    raw_val = values[0]['value'] || values[0]['Value']
    raise ExecutionError, "No raw values in performance sample for VM #{@name}." if raw_val.nil? || raw_val.empty?
 
    last_val = raw_val[-1].to_f

    last_val / 100.0
  end

  def query_memory_usage(vm)
    config = vm['Config'] || vm['config'] || {}
    hardware = config['Hardware'] || config['hardware'] || {}
    memory_mb = (hardware['MemoryMB'] || hardware['memoryMB']).to_f

    summary = vm['Summary'] || vm['summary'] || {}
    quick_stats = summary['QuickStats'] || summary['quickStats'] || {}
    guest_mem_usage = (quick_stats['GuestMemoryUsage'] || quick_stats['guestMemoryUsage']).to_f

    memory_mb > 0 ? (guest_mem_usage / memory_mb) * 100.0 : 0.0
  end

  def query_disk_usage(vm)
    summary = vm['Summary'] || vm['summary'] || {}
    storage = summary['Storage'] || summary['storage'] || {}
    committed = (storage['Committed'] || storage['committed']).to_f
    uncommitted = (storage['Uncommitted'] || storage['uncommitted']).to_f
    total = committed + uncommitted

    total > 0 ? (committed / total) * 100.0 : 0.0
  end
end

if __FILE__ == $0
  options = {}
  OptionParser.new do |opts|
    opts.banner = "Usage: rb_vmware_exsi_vm_monitor.rb [options]"

    opts.on('-i', '--host HOST-IP', 'Host IP') { |o| options[:host] = o }
    opts.on('-u', '--user USER', 'Username') { |o| options[:user] = o }
    opts.on('-p', '--password PASSWORD', 'Password') { |o| options[:password] = o }
    opts.on('-n', '--name VM-NAME', 'VM Name') { |o| options[:name] = o }
    opts.on('-t', '--metric METRIC', "Metric (#{VMwareESXiVMMonitor::SUPPORTED_METRICS.join(', ')})") { |o| options[:metric] = o }
    opts.on('-v', '--verbose', 'Verbose mode') { options[:verbose] = true }
  end.parse!

  begin
    monitor = VMwareESXiVMMonitor.new(options)
    monitor.run
  rescue ArgumentError => e
    STDERR.puts "Error: #{e.message}"
    exit 1
  rescue VMwareESXiVMMonitor::ExecutionError => e
    STDERR.puts "Error: #{e.message}"
    exit 1
  rescue => e
    STDERR.puts "Error: #{e.class} - #{e.message}"
    exit 1
  end
end
