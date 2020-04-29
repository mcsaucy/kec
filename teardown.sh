#!/bin/bash

set -e

echo "Tearing down all issue_307_* nodes..."
if ! VMS=( $(virsh --connect qemu:///system list --name \
             | grep issue_307_node) ); then
    echo "Nothing to tear down."
    exit 0
fi

for VM_NAME in "${VMS[@]}"; do
    echo "Tearing down $VM_NAME..."
    virsh --connect qemu:///system destroy "$VM_NAME" || :
    virsh --connect qemu:///system undefine "$VM_NAME" || :
done
echo "Done."
