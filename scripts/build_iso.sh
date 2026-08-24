#!/bin/bash

# Ensure you have a copy of the following files in the same folder as this build script
# 1. nvidia_setup.sh
# 2. post_kickstart.sh
# 3. fedora_hwqual_kickstart.cfg
# 4. Hardware_Qualification_ISO*.pdf
# And of course a copy of the Fedora Everything ISO which can be downloaded publicly
# 5. Fedora-Everything-netinst-x86_64-40-1.14.iso

# Define version and hwqual variables from command line arguments
VERSION=$1

# Echo message to confirm the build parameters
echo "We are building an ISO for Fedora Version: $VERSION and MODE: hwqual"

# Create a directory named 'build_iso' and change into it
mkdir build_iso && cd build_iso

# Copy necessary files from parent directories to the current directory
cp ../fedora_hwqual_testing.sh .
cp ../nvidia_setup.sh .
cp ../post_kickstart.sh .
cp ../Hardware_Qualification_ISO*.pdf .
cp ../fedora_hwqual_kickstart.cfg .
cp ../Fedora-Everything-netinst-x86_64-"$VERSION"*.iso .

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
