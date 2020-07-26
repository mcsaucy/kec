#!/bin/bash

set -e

HERE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
SCRATCH="$HERE/scratch"
mkdir -p "$SCRATCH"
cd "$HERE"

NUM_NODES="${NUM_NODES:=3}"
if (( NUM_NODES < 3 )); then
    echo "If set, env var NUM_NODES must contain a number >= 3" >&2
    exit 1
fi

bash "$HERE/teardown.sh"

echo "Going to create $NUM_NODES node(s)..."

QCOW="$SCRATCH/fedora-coreos-qemu.qcow2"

if [[ ! -f "$QCOW" || "$(wc -c < "$QCOW")" -eq 0 ]]; then
    IMG_LOC="https://builds.coreos.fedoraproject.org/prod/streams/stable/builds/32.20200629.3.0/x86_64/fedora-coreos-32.20200629.3.0-qemu.x86_64.qcow2.xz"

    echo "Fetching and decompressing image. This may take a minute..."
    curl -sfL "$IMG_LOC" | xzcat > "$QCOW"
else
    echo "Reusing $QCOW"
fi

# shellcheck disable=SC1117
AUTH_ME="$(tr -d "\n" < "$HOME/.ssh/id_rsa.pub")"
K3S_TOKEN="$(uuidgen | base64 -w 0)"

function make_ign() {
    local NODE_NUMBER="$1"
    local PRIMARY_NODE_IP="$2"
    local IGN="$SCRATCH/node$NODE_NUMBER.ign"

    local SUBS=(
        -e "s|YOUR_KEY_HERE|$AUTH_ME|g"
        -e "s|K3S_TOKEN|$K3S_TOKEN|g"
        -e "s|NODE_NUMBER|$NODE_NUMBER|g"
    )

    if [[ -n "$PRIMARY_NODE_IP" ]]; then
        SUBS+=( -e "s|PRIMARY_NODE_IP|$PRIMARY_NODE_IP|g" )
        local TMPL="$HERE/secondary.yaml"
    else
        local TMPL="$HERE/primary.yaml"
    fi
    sed < "$TMPL" "${SUBS[@]}" \
    | podman run -i quay.io/coreos/fcct:release --pretty --strict \
        > "$IGN"
}

function make_vm() {
    local NODE_NUMBER="$1"
    local IGN="$SCRATCH/node$NODE_NUMBER.ign"

    local NQ="$SCRATCH/fcos.node$NODE_NUMBER.qcow2"
    if [[ -f "$NQ" ]]; then
        rm -f "$NQ"
    fi
    rm -f "$SCRATCH/disk.node$NODE_NUMBER.0" "$SCRATCH/disk.node$NODE_NUMBER.1"
    qemu-img create -f qcow2 -b "$QCOW" "$NQ"

    local VM_NAME="kwik-e-cluster_node$NODE_NUMBER"

    echo "Let's make $VM_NAME"

    virt-install --connect qemu:///system -n "$VM_NAME" \
        -r 2048 --vcpus=2 \
        --os-variant=generic  --import --graphics=none --noautoconsole \
        --disk size=10,backing_store="$NQ" \
        --disk "size=10,path=$SCRATCH/disk.node$NODE_NUMBER.0" \
        --disk "size=10,path=$SCRATCH/disk.node$NODE_NUMBER.1" \
        --qemu-commandline="-fw_cfg name=opt/com.coreos/config,file=$IGN"

    echo "$VM_NAME is booting."
}

function retry_with_backoff() {
    local CMD=( "$@" )
    local ATTEMPT=1
    local BACKOFFS=(1 5 5 10 15 15 20 20 30 30 45 60)
    local MAX_ATT
    (( MAX_ATT=${#BACKOFFS[@]} + 1))
    for seconds in "${BACKOFFS[@]}"; do
        echo "(attempt $ATTEMPT/$MAX_ATT) executing: $*" >&2
        if ! "${CMD[@]}"; then
            echo "Failed. Sleeping $seconds seconds and retrying" >&2
            ((ATTEMPT++))
            sleep "$seconds"
        else return 0
        fi
    done

    echo "(attempt $ATTEMPT/$MAX_ATT) executing: $*"
    "${CMD[@]}"
}

function wait_til_sshable() {
    local NODE_NUM="$1"
    echo "Waiting for node$NODE_NUM to be SSHable..."
    retry_with_backoff timeout 3s "$HERE/ssh_node.sh" "$NODE_NUM" true
}
function wait_til_done_with_firstboot(){
    local NODE_NUM="$1"
    echo "Waiting for node$NODE_NUM to finish its first boot..."
    retry_with_backoff timeout 3s "$HERE/ssh_node.sh" "$NODE_NUM" \
        ! grep -q "ignition.firstboot" /proc/cmdline
}
function wait_til_can_see_node() {
    local NODE_NUM="$1"
    local LOOK_FOR="${2}"
    echo "Waiting for node$NODE_NUM to be able to see nodes..."
    retry_with_backoff timeout 3s bash -c "
            TARGET='$NODE_NUM'
            '$HERE/kubectl_node.sh' get node 'node${LOOK_FOR:-0}' \
                | grep -q 'Ready'"
}

function node_kubectl() {
    local NODE_NUM="$1"
    shift
    TARGET="$NODE_NUM" "$HERE/kubectl_node.sh" "$@"
}

# we have to make the primary before we can add secondaries.
make_ign 0
make_vm 0
wait_til_can_see_node 0

PRIMARY_NODE_IP="$( bash "$HERE/ip.sh" 0)"

mapfile -t SECONDARY_NODE_NUMS < <(seq 1 "$(( NUM_NODES - 1 ))")

for NODE_NUMBER in "${SECONDARY_NODE_NUMS[@]}"; do
    make_ign "$NODE_NUMBER" "$PRIMARY_NODE_IP"
    make_vm "$NODE_NUMBER"
done

echo "Waiting for all secondary nodes to come alive..."

for NODE_NUMBER in "${SECONDARY_NODE_NUMS[@]}"; do
    wait_til_can_see_node 0 "$NODE_NUMBER"
done

echo "Setting up rook-ceph with examples."
"$HERE/ssh_node.sh" 0 git clone https://github.com/mcsaucy/kec.git
node_kubectl 0 create -f kec/rook/common.yaml
node_kubectl 0 create -f kec/rook/operator.yaml
node_kubectl 0 create -f kec/rook/cluster.yaml
node_kubectl 0 create -f kec/rook/filesystem.yaml
node_kubectl 0 create -f kec/rook/storageclass.yaml
node_kubectl 0 create -f kec/rook/toolbox.yaml
node_kubectl 0 create -f kec/rook/pvc.yaml
node_kubectl 0 create -f kec/rook/consume_pvc.yaml
sleep 3
node_kubectl 0 -n rook-ceph get pods
echo "Completed successfully in $SECONDS seconds."
