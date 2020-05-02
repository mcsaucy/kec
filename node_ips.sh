#!/bin/bash

mapfile OUR_VMS < <(virsh --connect qemu:///system list | grep issue_329_node)
for VM in "${OUR_VMS[@]}"; do
    DOMAIN_ID="$(echo "$VM" | awk '{print $1}')"
    NAME="$(echo "$VM" | awk '{print $2}')"
    echo "Node $NAME::"
    virsh --connect qemu:///system domifaddr "$DOMAIN_ID" \
        | grep "vnet" | awk '{print "  " $2 " --> " $4}'
done
