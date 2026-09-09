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
fetch hyperbus_controller https://github.com/GhlHub/hyperbus_controller.git a3e38a65512daa10a436d7dc5ecaaa477c9811ec
# Keep the upstream checkout pinned and apply the reviewed local FIFO fix.
patch_path="$PWD/patches/hyperbus-wready.patch"
if ! git -C third_party/hyperbus_controller apply --reverse --check "$patch_path" 2>/dev/null; then
    git -C third_party/hyperbus_controller apply --check "$patch_path"
    git -C third_party/hyperbus_controller apply "$patch_path"
fi
fetch e_uart https://github.com/GhlHub/e_uart.git 72f014c35d812936c70f2e17acdd32a491c1fcdd
# This commit is from the requested 202604-LTS branch.
fetch FreeRTOS-LTS https://github.com/FreeRTOS/FreeRTOS-LTS.git 0b25dc50bae4cb971c7a459b109e52ab2f01a6b8
git -C third_party/FreeRTOS-LTS submodule update --init --depth 1 \
    FreeRTOS/FreeRTOS-Kernel FreeRTOS/FreeRTOS-Plus-TCP FreeRTOS/coreJSON
