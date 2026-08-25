#!/bin/bash

# Ensure you have a copy of the following files in the same folder as this build script
# 1. nvidia_setup.sh
# 2. post_kickstart.sh
# 3. fedora_hwqual_kickstart.cfg
# 4. Hardware_Qualification_ISO*.pdf

if [[ $# -ne 1 ]]; then
  echo 1>&2 "$0: Please specify the fedora version number"
  exit 2
fi

# Define version and hwqual variables from command line arguments
VERSION=$1

# Echo message to confirm the build parameters
echo "We are building an ISO for Fedora Version: $VERSION and MODE: hwqual"

# Create a directory named 'build_iso' and change into it
mkdir build_iso && cd build_iso

# Define ISO name 
PUBLIC_URL="https://dl.fedoraproject.org/pub/fedora/linux/releases/"
STABLE_PATH="${VERSION}/Everything/x86_64/iso/"
BASE_URL="${PUBLIC_URL}${STABLE_PATH}"

html=$(curl -s "$BASE_URL")
ISO_NAME=$(echo "$html" | awk -F'href="' '{print $2}' | awk -F '"' '{print $1}' | grep 'Fedora-Everything-.*.iso$')

PUBLIC_URL="https://download.fedoraproject.org/pub/fedora/linux/releases/"
BASE_URL="${PUBLIC_URL}${STABLE_PATH}"
BASE_ISO_URL="$BASE_URL$ISO_NAME"
wget "$BASE_ISO_URL"

# Copy necessary files from parent directories to the current directory
cp ../fedora_hwqual_testing.sh .
cp ../nvidia_setup.sh .
cp ../post_kickstart.sh .
cp ../Hardware_Qualification_ISO*.pdf .
cp ../fedora_hwqual_kickstart.cfg .

# Run the mkksiso command to build the ISO, including all specified scripts and files
sudo mkksiso -c "platform.version=$VERSION platform.nvidia=rpmfusion" -V FUDGE"$VERSION"hwqual \
-a fedora_hwqual_testing.sh \
-a post_kickstart.sh \
-a nvidia_setup.sh \
-a Hardware_Qualification_ISO*.pdf \
fedora_hwqual_kickstart.cfg \
Fedora-Everything-netinst-x86_64-"$VERSION"*.iso \
../fedora-fantasy-hwqual-"$VERSION".iso

cd ..
sudo rm -rf build_iso
