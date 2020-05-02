#!/bin/bash

set -e

HERE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

IP="$( bash "$HERE/node_ips.sh" \
        | grep "issue_329_node0" \
        | cut -d, -f3 \
        | cut -d/ -f1 )"

if [[ -z "$IP" ]]; then
    echo "Can't determine IP of node 0. This could be because it's booting." >&2
    echo "Ensure it's running and try again later." >&2
    exit 1
fi

echo "Preparing to ssh to core@$IP"
ssh "core@$IP"
