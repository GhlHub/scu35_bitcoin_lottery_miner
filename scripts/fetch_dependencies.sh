#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p third_party
fetch() {
    local name="$1" url="$2" revision="$3"
    if test ! -d "third_party/$name"; then
        git clone --no-checkout "$url" "third_party/$name"
        git -C "third_party/$name" checkout --detach "$revision"
    fi
    local actual
    actual=$(git -C "third_party/$name" rev-parse HEAD)
    if test "$actual" != "$revision"; then
        printf 'Revision mismatch for %s: expected %s, found %s\n' "$name" "$revision" "$actual" >&2
        exit 1
    fi
}
# Upstream includes the reviewed WREADY fix in RTL and packaged IP.
fetch hyperbus_controller https://github.com/GhlHub/hyperbus_controller.git 26bcdc5c0f2044867d4bce6872a646fcee25079c
fetch e_uart https://github.com/GhlHub/e_uart.git 72f014c35d812936c70f2e17acdd32a491c1fcdd
# This commit is from the requested 202604-LTS branch.
fetch FreeRTOS-LTS https://github.com/FreeRTOS/FreeRTOS-LTS.git 0b25dc50bae4cb971c7a459b109e52ab2f01a6b8
git -C third_party/FreeRTOS-LTS submodule update --init --depth 1 \
    FreeRTOS/FreeRTOS-Kernel FreeRTOS/FreeRTOS-Plus-TCP FreeRTOS/coreJSON
