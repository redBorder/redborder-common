#!/usr/bin/env python3
import argparse
import sys
import ssl
from pyVim.connect import SmartConnect, Disconnect
from pyVmomi import vim

def get_real_value(args):
    context = ssl._create_unverified_context()
    si = SmartConnect(host=args.host, user=args.user, pwd=args.password, sslContext=context)
    try:
        content = si.RetrieveContent()
        container = content.viewManager.CreateContainerView(content.rootFolder, [vim.VirtualMachine], True)
        target_vm = None
        for vm in container.view:
            if vm.name == args.name:
                target_vm = vm
                break
        if not target_vm:
            raise ValueError(f"VM {args.name} not found")
        
        summary = target_vm.summary
        if args.metric == "power":
            state = 1 if summary.runtime.powerState == vim.VirtualMachinePowerState.poweredOn else 0
            return f"{state:.2f}"
        elif args.metric == "cpu":
            usage = summary.quickStats.overallCpuUsage
            num_cpu = target_vm.config.hardware.numCPU if target_vm.config and target_vm.config.hardware else 1
            host = target_vm.runtime.host if target_vm.runtime else None
            host_mhz = host.summary.hardware.cpuMhz if host and host.summary and host.summary.hardware else 2000
            total = num_cpu * host_mhz
            val = (usage / total) * 100 if total > 0 else 0
            return f"{val:.2f}"
        elif args.metric == "memory":
            usage = summary.quickStats.guestMemoryUsage
            total = summary.config.memorySizeMB
            val = (usage / total) * 100 if total > 0 else 0
            return f"{val:.2f}"
        elif args.metric == "disk":
            storage = summary.storage
            committed = storage.committed if storage else 0
            uncommitted = storage.uncommitted if storage else 0
            total = committed + uncommitted
            val = (committed / total) * 100 if total > 0 else 0.00
            return f"{val:.2f}"
    finally:
        Disconnect(si)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("-i", "--host", required=True)
    parser.add_argument("-u", "--user", required=True)
    parser.add_argument("-p", "--password", required=True)
    parser.add_argument("-d", "--datacenter")
    parser.add_argument("-f", "--folder")
    parser.add_argument("-n", "--name", required=True)
    parser.add_argument("-t", "--metric", choices=["cpu", "memory", "disk", "power"], required=True)
    args = parser.parse_args()

    try:
        print(get_real_value(args))
    except Exception as e:
        sys.stderr.write(f"Error querying VM: {e}\n")
        sys.exit(1)

if __name__ == "__main__":
    main()
