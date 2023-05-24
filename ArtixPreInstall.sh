#!/bin/sh

# Daniel Pellegrino Artix Pre-Install runit Script
# by Daniel Pellegrino
# License: GNU GPLv3

### VOLUME GROUP VARIABLES ###
CRYPT_PART="artix_crypt"

# PARTITION SIZES (You can edit these if desired)
EFI_SIZE=512M      # EFI applies to GPT disklabel

# EXTRA (You can edit these if desired)
TIMEZONE='America/New_York'
LOCALE="en_US.UTF-8"
KEYBOARD="us"

### FUNCTIONS ###

efi_boot_mode(){
    # if the efivars directory exists we definitely have an EFI BIOS
    # otherwise, we could have a non-standard EFI or even an MBR-only system
    ( $(ls /sys/firmware/efi/efivars &>/dev/null) && return 0 ) || return 1
}

installpkg() {
	pacman --noconfirm --needed -S "$1" >/dev/null 2>&1
}

error() {
	# Log to stderr and exit with failure.
	printf "%s\n" "$1" >&2
	exit 1
}

welcomemsg() {
	whiptail --title "Welcome!" \
		--msgbox "Welcome to Daniel's Pre-Install Script!\\n\\nThis script will automatically set up encryption and a btrfs file system.\\n\\n-Daniel" 10 60

	whiptail --title "Important Note!" --yes-button "All ready!" \
		--no-button "Return..." \
		--yesno "Be sure the computer you are using has current pacman updates and refreshed Arch keyrings.\\n\\nIf it does not, the installation of some programs might fail." 8 70
}

# Verify user is using the runit init system
runitcheck() {
	{ pstree | grep runsv >/dev/null 2>&1; }
}

selectdisk() {
	depth=$(lsblk | grep 'disk' | wc -l)
	local DISKS=()
	for d in $(lsblk | grep disk | awk '{printf "%s\n%s \\\n",$1,$4}'); do
		DISKS+=("$d")
	done
	whiptail --title "Select Disk" \
		--radiolist " Your Installation Disk: " 20 70 "$depth" \
		"${DISKS[@]}" 3>&1 1>&2 2>&3
}

setupdisk(){
    device=$(selectdisk)
}

preinstallmsg() {
	whiptail --title "Final Warnings!" --yes-button "All good!" \
		--no-button "No wait!" \
		--yesno "The rest of the installation will now be totally automated!\n\nWARNING: This script is intended for systems that have yet to be set up, please perform this on the Artix Linux iso installation.\\n\\nWARNING: All data on /dev/$device will be wiped going onwards." 13 90 || {
		clear
		exit 1
	}
}

wipedisk(){
	wipefs -a /dev/$device[1-9]* # wipe old partitions
	wipefs -a /dev/$device       # wipe the disk itself
	parted /dev/$device          # create new partitions
	wipefs -a /dev/$device[1-9]* # wipe the new partitions, just in case
}

encryptdisk(){
	echo -e "YES" | cryptsetup luksFormat /dev/$device2 # User may enter their encryption password
}

formatdisk(){
	echo -e "o\nn\np\n1\n\n+$EFI_SIZE\nn\np\n2\n\n\nw" | fdisk /dev/$device
	mkfs.fat -F32 /dev/$device1
	encryptdisk
	cryptsetup open /dev/$device2 $CRYPT_PART # User will enter encryption password
	mkfs.btrfs /dev/mapper/$CRYPT_PART
}

### THE ACTUAL SCRIPT ###

# Download libnewt (to use whiptail)
pacman --noconfirm --needed -Sy libnewt ||
	error "Are you sure you're running this as the root user, are on an Arch-based distribution and have an internet connection?"

# Check if using is on GPT disktable
efi_boot_mode || error "Please run this script only on a GPT disktable."

# Welcome user
welcomemsg || error "User exited."

# Verify the user is using the runit init system
runitcheck || error "This script is intended to be used on a runit based init system."

# Select disk to install on
setupdisk || error "Error selecting disk."

# Last chance for user to back out before install.
preinstallmsg || error "User exited."

# Wipe the selected disk
wipedisk

# Format the selected disk
formatdisk