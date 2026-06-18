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
        container = content.viewManager.CreateContainerView(content.rootFolder, [vim.HostSystem], True)
        if not container.view:
            raise ValueError("No HostSystem found")
        host = container.view[0] # Assume single host context
        summary = host.summary
        
        if args.metric == "cpu":
            usage = summary.quickStats.overallCpuUsage
            total = summary.hardware.cpuMhz * summary.hardware.numCpuCores
            val = (usage / total) * 100 if total > 0 else 0
            return f"{val:.2f}"
        elif args.metric == "memory":
            usage = summary.quickStats.overallMemoryUsage
            total = summary.hardware.memorySize / (1024 * 1024)
            val = (usage / total) * 100 if total > 0 else 0
            return f"{val:.2f}"
        elif args.metric == "disk":
            ds_usages = []
            for ds in host.datastore:
                ds_summary = ds.summary
                used = ds_summary.capacity - ds_summary.freeSpace
                percent = (used / ds_summary.capacity) * 100 if ds_summary.capacity > 0 else 0
                ds_usages.append(f"{percent:.2f}")
            return ";".join(ds_usages)
    finally:
        Disconnect(si)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("-i", "--host", required=True)
    parser.add_argument("-u", "--user", required=True)
    parser.add_argument("-p", "--password", required=True)
    parser.add_argument("-d", "--datacenter")
    parser.add_argument("-f", "--folder")
    parser.add_argument("-t", "--metric", choices=["cpu", "memory", "disk"], required=True)
    args = parser.parse_args()

    try:
        print(get_real_value(args))
    except Exception as e:
        sys.stderr.write(f"Error querying ESXi host: {e}\n")
        sys.exit(1)

if __name__ == "__main__":
    main()
