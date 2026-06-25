#!/usr/bin/env ruby

require 'optparse'
require 'json'
require 'shellwords'

options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: rb_vmware_exsi_vm_monitor.rb [options]"

  opts.on('-i', '--host HOST-IP', 'Host IP') { |o| options[:host] = o }
  opts.on('-u', '--user USER', 'Username') { |o| options[:user] = o }
  opts.on('-p', '--password PASSWORD', 'Password') { |o| options[:password] = o }
  opts.on('-d', '--datacenter DATACENTER', 'Datacenter') { |o| options[:datacenter] = o }
  opts.on('-f', '--folder FOLDER', 'Folder') { |o| options[:folder] = o }
  opts.on('-n', '--name VM-NAME', 'VM Name') { |o| options[:name] = o }
  opts.on('-t', '--metric METRIC', 'Metric (cpu, memory, disk, power)') { |o| options[:metric] = o }
  opts.on('-v', '--verbose', 'Verbose mode') { options[:verbose] = true }
end.parse!

if !options[:host] || !options[:user] || !options[:password] || !options[:name] || !options[:metric]
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
  escaped_name = Shellwords.escape(options[:name])

  # 1. Fetch VM Info to check powerState and basic properties
  info_output = `govc vm.info -json #{escaped_name}`
  if $?.exitstatus != 0
    raise "VM #{options[:name]} not found or govc failed"
  end
 
  data = JSON.parse(info_output)
  vms = data['VirtualMachines'] || data['virtualMachines']
  raise "VM #{options[:name]} not found" if !vms || vms.empty?
  vm = vms[0]

  runtime = vm['Runtime'] || vm['runtime'] || {}
  power_state = runtime['PowerState'] || runtime['powerState']

  # Handle power metric directly
  if options[:metric].downcase == 'power'
    state_val = (power_state == 'poweredOn') ? 1.00 : 0.00
    puts sprintf("%.2f", state_val)
    exit 0
  end

  # For other metrics, if the VM is not poweredOn, return 0.00
  if power_state != 'poweredOn'
    puts "0.00"
    exit 0
  end

  case options[:metric].downcase
  when 'cpu'
    # Use govc metric.sample to get CPU usage average
    vm_path = `govc find . -name #{escaped_name}`.strip
    if vm_path.empty?
      raise "Could not find VM path for #{options[:name]}"
    end

    metric_output = `govc metric.sample -json #{Shellwords.escape(vm_path)} cpu.usage.average`
    if $?.exitstatus != 0
      raise "govc metric.sample cpu.usage.average failed"
    end

    metric_data = JSON.parse(metric_output)
    sample = metric_data['sample'] || metric_data['Sample']
    raise "No performance metrics returned" if !sample || sample.empty?

    values = sample[0]['value'] || sample[0]['Value']
    raise "No values in performance sample" if !values || values.empty?

    raw_val = values[0]['value'] || values[0]['Value']
    raise "No raw values in performance sample" if !raw_val || raw_val.empty?
 
    last_val = raw_val[-1].to_f
    # Standard vSphere metric cpu.usage.average returns basis points (1 unit = 0.01%)
    percent = last_val / 100.0
    puts sprintf("%.2f", percent)

  when 'memory'
    config = vm['Config'] || vm['config'] || {}
    hardware = config['Hardware'] || config['hardware'] || {}
    memory_mb = (hardware['MemoryMB'] || hardware['memoryMB']).to_f

    summary = vm['Summary'] || vm['summary'] || {}
    quick_stats = summary['QuickStats'] || summary['quickStats'] || {}
    guest_mem_usage = (quick_stats['GuestMemoryUsage'] || quick_stats['guestMemoryUsage']).to_f

    val = memory_mb > 0 ? (guest_mem_usage / memory_mb) * 100 : 0
    puts sprintf("%.2f", val)

  when 'disk'
    summary = vm['Summary'] || vm['summary'] || {}
    storage = summary['Storage'] || summary['storage'] || {}
    committed = (storage['Committed'] || storage['committed']).to_f
    uncommitted = (storage['Uncommitted'] || storage['uncommitted']).to_f
    total = committed + uncommitted

    val = total > 0 ? (committed / total) * 100 : 0.00
    puts sprintf("%.2f", val)

  else
    STDERR.puts "Unknown metric: #{options[:metric]}"
    exit 1
  end
rescue => e
  STDERR.puts "Error querying VM: #{e.message}"
  exit 1
end
