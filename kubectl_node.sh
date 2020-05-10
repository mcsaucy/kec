#!/bin/bash

set -e

TARGET="${TARGET:-0}"

HERE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
bash "$HERE/ssh_node.sh" "$TARGET" sudo k3s kubectl "$@"
