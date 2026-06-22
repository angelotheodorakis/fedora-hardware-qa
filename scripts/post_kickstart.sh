#!/bin/bash

set -eux -o pipefail

mode="$(grep -oP 'cpe.mode=\K(\w*)' /proc/cmdline)"

# scripts from ISO
cp /tmp/fedora_hwqual_testing.sh /usr/local/bin/fedora_hwqual_testing.sh
cp /tmp/nvidia_setup.sh /usr/local/bin/nvidia_setup.sh

# PDF with instructions in every new user's Documents folder
mkdir -p /etc/skel/Documents
cp /tmp/Hardware_Qualification_ISO_-_Setup_and_usage_instructions.pdf /etc/skel/Documents/Hardware_Qualification_ISO_-_Setup_and_usage_instructions.pdf

############################################################################
# Additional software installation section
############################################################################

dnf -y install neovim terminus-fonts-console tmux zsh

# Install latest kernel
dnf -y install kernel-modules-extra kernel-devel
dnf -y update kernel kernel-core kernel-modules kernel-modules-extra kernel-devel tpm2-tools

# Rebuild grub config so system defaults are used instead of ISO's
grub2-mkconfig -o /boot/grub2/grub.conf

# Confirming dependencies for kerberos exist
dnf -y install dmidecode krb5-workstation krb5-libs openconnect chkconfig fedora-workstation-repositories libxcrypt-compat

# Install appindicator extensions early so chef doesn't fail to bootstrap later
dnf -y install gnome-shell-extension-appindicator gnome-extensions-app

# Installing Seahorse for keyring management
dnf -y install seahorse

# Installing Google Chrome
dnf -y install fedora-workstation-repositories
dnf config-manager setopt google-chrome.enabled=1
dnf -y install google-chrome-stable

# Hardware qualification tooling
dnf -y copr enable aflyhorse/iozone
dnf -y install glmark2 stress stress-ng memtester sysbench kdiskmark iozone inxi phoronix-test-suite

############################################################################
# End of extra software installation section
############################################################################

# Automatically decrypt disk
ENCRYPTED_ROOT="$(findfs "$(sudo cut -d' ' -f2 /etc/crypttab)")"

## Create key
dd if=/dev/urandom of=/boot/keyfile bs=1024 count=4
chmod 0400 /boot/keyfile
echo 'fedora' | cryptsetup -v luksAddKey "${ENCRYPTED_ROOT}" /boot/keyfile

## Setup Crypttab
sed -i 's#none.*#/boot/keyfile luks#' /etc/crypttab

## Set the keyfile to go in the initramfs
echo 'install_items+=" /boot/keyfile "' >> /etc/dracut.conf.d/keyfile.conf

## Rebuild the initramfs
dracut -f --regenerate-all

## Clean up
rm /etc/dracut.conf.d/keyfile.conf

# Run any remaining security and OS updates
dnf -y upgrade --refresh --security
dnf -y upgrade --refresh

# installing Nvidia drivers if detected
chmod +x /usr/local/bin/nvidia_setup.sh
/usr/local/bin/nvidia_setup.sh

