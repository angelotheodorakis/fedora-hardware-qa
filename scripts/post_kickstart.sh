#!/bin/bash

set -eux -o pipefail

trap '
  exec < /dev/tty3 > /dev/tty3
  chvt 3
  set +x
  setfont -d
  echo
  echo "################################################################"
  echo "#  ____   ___    _   _  ___ _____   ____  _   _ ___ ____    _  #"
  echo "# |  _ \ / _ \  | \ | |/ _ \_   _| / ___|| | | |_ _|  _ \  | | #"
  echo "# | | | | | | | |  \| | | | || |   \___ \| |_| || || |_) | | | #"
  echo "# | |_| | |_| | | |\  | |_| || |    ___) |  _  || ||  __/  |_| #"
  echo "# |____/ \___/  |_| \_|\___/ |_|   |____/|_| |_|___|_|     (_) #"
  echo "#                                                              #"
  echo "################################################################"
  echo
  echo
  echo "Something went wrong and the post kickstart script did not finish successfully."
  echo
  echo "To see the output of what possibly failed, Press ALT+CTRL+F1 to switch to the commandline TTY script output. "
  echo " You can return to the main window with ALT + CTRL + F6 to exit the installation."
  echo
  echo "The error was trapped in the line $LINENO in command: $BASH_COMMAND that finished with exit code $?"
  sleep 120
' ERR

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
dnf -y install gnome-shell-extension-appindicator gnome-extensions-app gnome-shell-extension-caffeine

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

# Importing akmods key with MOK enrollment if secure boot is enabled
MOKUTIL_CHECK=$(mokutil --sb-state)
if [[ $MOKUTIL_CHECK == "SecureBoot enabled" ]]; then
  #TODO we might need to change TTY here to 1 which displays the post_kistart steps
  AKMODS_CERT="/etc/pki/akmods/certs/public_key.der"
  # Check for akmods
  if [ ! -d "/etc/pki/akmods/certs" ] && [ ! -f "$AKMODS_CERT" ]; then
  dnf install -y kmodtool akmods mokutil openssl
  fi

  /usr/sbin/kmodgenca -a

  set +x
  # Interactive mokutil enrollment via TTY3
  if [ -f /etc/pki/akmods/certs/public_key.der ]; then
  exec < /dev/tty3 > /dev/tty3 2>&1
  chvt 3
  setfont -d
  echo
  echo "########################################################"
  echo "#  Secure Boot: MOK Key Enrollment                     #"
  echo "#  You will be prompted to set a one-time password.    #"
  echo "#  Remember it — you'll need it on the next reboot.    #"
  echo "########################################################"
  echo
  mokutil --import /etc/pki/akmods/certs/public_key.der
  mokutil --timeout -1
  echo
  echo "MOK key queued for enrollment. On next boot, the MOK"
  echo "manager will ask you to confirm with the password above."
  echo
  read -rsn1 -p "Press any key to continue..."
  chvt 6
  set -x
  exec < /dev/tty1 > /dev/tty1 2>&1
  fi

  akmods --rebuild
  dracut -f
fi