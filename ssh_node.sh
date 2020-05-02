#!/bin/bash

set -e

if [[ "$#" -eq 0 ]]; then
    echo "Usage: $0 NODE_NUMBER [commands...]" >&2
    exit 1
fi

NODE_NUM="$1"
shift

HERE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

IP="$( bash "$HERE/ip.sh" "$NODE_NUM" )"

echo "Preparing to ssh to core@$IP"
ssh -oStrictHostKeyChecking=no "core@$IP" "$@"
