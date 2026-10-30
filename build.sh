#!/bin/bash
set -xe
shopt -s extglob

BUILD_DIR=workdir

# From https://stackoverflow.com/a/48808214
args=("$@")
for ((i=0; i<"${#args[@]}"; ++i)); do
    case ${args[i]} in
        -b) BUILD_DIR=${args[i+1]}; unset args[i]; unset args[i+1]; break;;
    esac
done

[ -d build ] || git clone https://gitlab.com/ubports/community-ports/halium-generic-adaptation-build-tools build

HERE=$(pwd)
SCRIPT="$(dirname "$(realpath "$0")")"/build
if [ ! -d "$SCRIPT" ]; then
    SCRIPT="$(dirname "$SCRIPT")"
fi
for BUILD_TOOLS_PATCH in "$HERE"/patches/build-tools/*.patch; do
    [ -f "$BUILD_TOOLS_PATCH" ] || continue
    if ! git -C "$SCRIPT" apply --reverse --check "$BUILD_TOOLS_PATCH"; then
        git -C "$SCRIPT" apply --check "$BUILD_TOOLS_PATCH"
        git -C "$SCRIPT" apply "$BUILD_TOOLS_PATCH"
    fi
done
TMPDOWN="$BUILD_DIR/downloads"
mkdir -p "$TMPDOWN"

source deviceinfo
source "$SCRIPT/common_functions.sh"
source "$SCRIPT/setup_repositories.sh" "${TMPDOWN}"

KERNEL_DIR="$(basename "${deviceinfo_kernel_source}")"
KERNEL_DIR="${KERNEL_DIR%.*}"
echo $KERNEL_DIR

cd "$TMPDOWN/$KERNEL_DIR"

git fetch origin "$deviceinfo_kernel_source_branch"
git checkout --detach FETCH_HEAD

cd "$HERE"

for KERNEL_PATCH in "$HERE"/patches/kernel/*.patch; do
    [ -f "$KERNEL_PATCH" ] || continue
    if ! git -C "$TMPDOWN/$KERNEL_DIR" apply --reverse --check "$KERNEL_PATCH"; then
        git -C "$TMPDOWN/$KERNEL_DIR" apply --check "$KERNEL_PATCH"
        git -C "$TMPDOWN/$KERNEL_DIR" apply "$KERNEL_PATCH"
    fi
done

install -D -m 0644 "$HERE/vendor/halium.config" \
    "$TMPDOWN/$KERNEL_DIR/arch/arm64/configs/vendor/halium.config"
install -D -m 0644 "$HERE/vendor/milanf_device.config" \
    "$TMPDOWN/$KERNEL_DIR/arch/arm64/configs/vendor/milanf_device.config"

./build/build.sh "${args[@]}" -b "$BUILD_DIR"
