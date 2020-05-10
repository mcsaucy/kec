#!/bin/bash

set -e

TARGET="${TARGET:-0}"

HERE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

TARGET="$TARGET" "$HERE/kubectl_node.sh" -n rook-ceph \
    exec -it deployment/rook-ceph-tools -- "$@"
