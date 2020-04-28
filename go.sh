#!/bin/bash

set -e

HERE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
SCRATCH="$HERE/scratch/"
mkdir -p "$SCRATCH"
cd "$HERE"

if ! (( NUM_NODES="$(cat "$HERE/NUM_NODES")" )) || (( NUM_NODES < 1 )); then
    echo "$HERE/NUM_NODES must contain a number >= 1" >&2
    exit 1
fi

echo "Going to create $NUM_NODES node(s)..."

QCOW="$SCRATCH/fedora-coreos-qemu.qcow2"

if [[ ! -f "$QCOW" || "$(wc -c < "$QCOW")" -eq 0 ]]; then
    IMG_LOC="https://builds.coreos.fedoraproject.org/prod/streams/stable/builds/31.20200407.3.0/x86_64/fedora-coreos-31.20200407.3.0-qemu.x86_64.qcow2.xz"

    echo "Fetching and decompressing image. This may take a minute..."
    curl -sfL "$IMG_LOC" | xzcat > "$QCOW"
else
    echo "Reusing $QCOW"
fi

AUTH_ME="$(tr -d "\n" < "$HOME/.ssh/id_rsa.pub")"

for NODE_NUMBER in $(seq 0 "$(( NUM_NODES - 1 ))"); do
    IGN="$SCRATCH/node$NODE_NUMBER.ign"
    sed < base.yaml \
        -e "s|YOUR_KEY_HERE|$AUTH_ME|g" \
        -e "s|NODE_NUMBER|$NODE_NUMBER|g" \
    | podman run -i --rm quay.io/coreos/fcct:release --pretty --strict \
        > "$IGN"

    NQ="$SCRATCH/fcos.node$NODE_NUMBER.qcow2"
    if [[ -f "$NQ" ]]; then
        rm -f "$NQ"
    fi
    rm -f "$SCRATCH/disk.node$NODE_NUMBER.0" "$SCRATCH/disk.node$NODE_NUMBER.1"
    qemu-img create -f qcow2 -b "$QCOW" "$NQ"

    VM_NAME="issue_307_node$NODE_NUMBER"

    echo "Cleaning up any running VMs that we may have started in the past."
    echo "Don't worry about missing domain errors."
    virsh --connect qemu:///system destroy "$VM_NAME" || :
    virsh --connect qemu:///system undefine "$VM_NAME" || :
    echo "OK, start worrying about missing domain errors again..."

    echo "Let's make $VM_NAME"

    virt-install --connect qemu:///system -n "$VM_NAME" \
        -r 2048 --vcpus=2 \
        --os-variant=generic  --import --graphics=none --noautoconsole \
        --disk size=10,backing_store="$NQ" \
        --disk "size=5,path=$SCRATCH/disk.node$NODE_NUMBER.0" \
        --disk "size=5,path=$SCRATCH/disk.node$NODE_NUMBER.1" \
        --qemu-commandline="-fw_cfg name=opt/com.coreos/config,file=$IGN"

    echo "$VM_NAME is booting."

done
