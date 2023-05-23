#!/bin/sh

# Daniel Pellegrino Artix Pre-Install runit Script
# by Daniel Pellegrino
# License: GNU GPLv3

### FUNCTIONS ###

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

### THE ACTUAL SCRIPT ###

pacman --noconfirm --needed -Sy libnewt ||
	error "Are you sure you're running this as the root user, are on an Arch-based distribution and have an internet connection?"

# Welcome user
welcomemsg || error "User exited."

runitcheck || error "runit not detected."

setupdisk || error "Error selecting disk."
