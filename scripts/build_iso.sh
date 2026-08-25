#!/bin/bash

set -uxf -o pipefail

OS_VERSION_NUMBER="$1"
BUILD_DIR="$2"

if [[ $# -ne 2 ]]; then
  echo 1>&2 "$0: Please specify the fedora version number and build directory"
  exit 2
fi

cd "$BUILD_DIR"
# Download Fedora Everything ISO
PUBLIC_URL="https://dl.fedoraproject.org/pub/fedora/linux/releases/"
STABLE_PATH="${OS_VERSION_NUMBER}/Everything/x86_64/iso/"
BASE_URL="${PUBLIC_URL}${STABLE_PATH}"

html=$(curl -s "$BASE_URL")
ISO_NAME=$(echo "$html" | awk -F'href="' '{print $2}' | awk -F '"' '{print $1}' | grep 'Fedora-Everything-.*.iso$')

PUBLIC_URL="https://download.fedoraproject.org/pub/fedora/linux/releases/"
BASE_URL="${PUBLIC_URL}${STABLE_PATH}"
BASE_ISO_URL="$BASE_URL$ISO_NAME"
wget "$BASE_ISO_URL"

# Run mkksiso
sudo mkksiso \
-c "platform.version=$OS_VERSION_NUMBER platform.nvidia=rpmfusion" \
-V FUDGE"$OS_VERSION_NUMBER"hwqual \
-a ./scripts/fedora_hwqual_testing.sh \
-a ./scripts/post_kickstart.sh \
-a ./scripts/nvidia_setup.sh \
-a ./scripts/Hardware_Qualification_ISO*.pdf \
fedora_hwqual_kickstart.cfg \
"$ISO_NAME" \
fedora-fantasy-hwqual-"$OS_VERSION_NUMBER".iso

sudo rm "$ISO_NAME"
