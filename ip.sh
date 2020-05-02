#!/bin/bash

NODE_NUM="$1"

function getall() {
    mapfile OUR_VMS < <(virsh --connect qemu:///system list \
                        | grep issue_329_node)
    for VM in "${OUR_VMS[@]}"; do
        DOMAIN_ID="$(echo "$VM" | awk '{print $1}')"
        NAME="$(echo "$VM" | awk '{print $2}')"
        virsh --connect qemu:///system domifaddr "$DOMAIN_ID" \
            | grep "vnet" | awk -v name="$NAME" '{print name "," $2 "," $4}'
    done
}


if [[ -z "$NODE_NUM" ]]; then
    getall
else
    TARGET="issue_329_node$NODE_NUM"
    mapfile RECORDS < <(getall)
    for r in "${RECORDS[@]}"; do
        NAME="$(cut -d, -f1 <<< "$r")"
        IP="$(cut -d, -f3 <<< "$r" | cut -d/ -f1 )"
        if [[ "$NAME" == "$TARGET" ]]; then 
            echo "$IP"
            exit 0
        fi
    done
    echo "Can't determine IP of node $NODE_NUM. This could be because it's booting." >&2
    echo "Ensure it's running and try again later." >&2
    exit 1
fi
