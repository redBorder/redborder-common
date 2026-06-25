#!/usr/bin/env ruby

require 'optparse'
require 'json'

options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: rb_vmware_exsi_monitor.rb [options]"

  opts.on('-i', '--host HOST-IP', 'Host IP') { |o| options[:host] = o }
  opts.on('-u', '--user USER', 'Username') { |o| options[:user] = o }
  opts.on('-p', '--password PASSWORD', 'Password') { |o| options[:password] = o }
  opts.on('-d', '--datacenter DATACENTER', 'Datacenter') { |o| options[:datacenter] = o }
  opts.on('-f', '--folder FOLDER', 'Folder') { |o| options[:folder] = o }
  opts.on('-t', '--metric METRIC', 'Metric (cpu, memory, disk)') { |o| options[:metric] = o }
end.parse!

if !options[:host] || !options[:user] || !options[:password] || !options[:metric]
  STDERR.puts "Missing required options"
  exit 1
end

# Set environment variables for govc
ENV['GOVC_URL'] = "https://#{options[:user]}:#{options[:password]}@#{options[:host]}/sdk"
ENV['GOVC_INSECURE'] = "true"
ENV['GOVC_DATACENTER'] = options[:datacenter] if options[:datacenter] && !options[:datacenter].empty?
ENV['HOME'] = "/tmp/govc-home-#{Process.uid}"
ENV['GOVC_HOME'] = "/tmp/govc-home-#{Process.uid}"
ENV['GOVC_PERSIST_SESSION'] = "false"
Dir.mkdir(ENV['HOME']) rescue nil

begin
  case options[:metric].downcase
  when 'cpu'
    output = `govc host.info -json`
    if $?.exitstatus != 0
      raise "govc host.info failed with exit code #{$?.exitstatus}"
    end
    data = JSON.parse(output)
    vms = data['HostSystems'] || data['hostSystems']
    host_system = vms ? vms[0] : nil
    raise "No HostSystem found" unless host_system

    summary = host_system['Summary'] || host_system['summary']
    quick_stats = summary['quickStats'] || summary['QuickStats']
    hardware = summary['hardware'] || summary['Hardware']

    usage = quick_stats['overallCpuUsage'].to_f
    cpu_mhz = hardware['cpuMhz'].to_f
    num_cores = hardware['numCpuCores'].to_f
    total = cpu_mhz * num_cores

    val = total > 0 ? (usage / total) * 100 : 0
    puts sprintf("%.2f", val)

  when 'memory'
    output = `govc host.info -json`
    if $?.exitstatus != 0
      raise "govc host.info failed with exit code #{$?.exitstatus}"
    end
    data = JSON.parse(output)
    vms = data['HostSystems'] || data['hostSystems']
    host_system = vms ? vms[0] : nil
    raise "No HostSystem found" unless host_system

    summary = host_system['Summary'] || host_system['summary']
    quick_stats = summary['quickStats'] || summary['QuickStats']
    hardware = summary['hardware'] || summary['Hardware']

    usage = quick_stats['overallMemoryUsage'].to_f # in MB
    memory_size = hardware['memorySize'].to_f # in bytes
    total = memory_size / (1024.0 * 1024.0) # to MB

    val = total > 0 ? (usage / total) * 100 : 0
    puts sprintf("%.2f", val)

  when 'disk'
    output = `govc datastore.info -json`
    if $?.exitstatus != 0
      raise "govc datastore.info failed with exit code #{$?.exitstatus}"
    end
    data = JSON.parse(output)
    datastores = data['Datastores'] || data['datastores'] || []
    
    ds_usages = datastores.map do |ds|
      summary = ds['Summary'] || ds['summary']
      capacity = summary['capacity'].to_f
      free_space = summary['freeSpace'].to_f
      used = capacity - free_space
      percent = capacity > 0 ? (used / capacity) * 100 : 0
      sprintf("%.2f", percent)
    end
    puts ds_usages.join(";")
  else
    STDERR.puts "Unknown metric: #{options[:metric]}"
    exit 1
  end
rescue => e
  STDERR.puts "Error querying ESXi host: #{e.message}"
  exit 1
end
