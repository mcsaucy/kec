#!/bin/bash

set -e

HERE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

IP="$( bash "$HERE/ip.sh" 0 )"

echo "Preparing to ssh to core@$IP"
ssh -oStrictHostKeyChecking=no "core@$IP" "$@"
