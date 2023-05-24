#!/bin/sh

# Daniel Pellegrino Artix Pre-Install runit Script
# by Daniel Pellegrino
# License: GNU GPLv3

### PROGRAMS FILE (CONTAINS ALL PROGRAMS THAT WILL BE INSTALLED) ###
progsfile="https://raw.githubusercontent.com/danpellegrino/ArtixPre/main/progs.csv"

### VOLUME GROUP VARIABLES ###
CRYPT_PART="artix_crypt"

# PARTITION SIZES (You can edit these if desired)
EFI_SIZE=512M      # EFI applies to GPT disklabel

# EXTRA (You can edit these if desired)
TIMEZONE='America/New_York'
LOCALE="en_US.UTF-8"
KEYBOARD="us"
HOSTNAME="artix"

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
	wipefs -af /dev/$device[1-9]* # wipe old partitions
	wipefs -af /dev/$device       # wipe the disk itself
	wipefs -af /dev/$device[1-9]* # wipe the new partitions, just in case
}

encryptdisk(){
	cryptsetup luksFormat /dev/$device"2" # User may enter their encryption password
}

formatdisk(){
	echo -e "o\nn\np\n1\n\n+$EFI_SIZE\nn\np\n2\n\n\nw" | fdisk /dev/$device
	mkfs.fat -F32 /dev/$device"1"
	encryptdisk
	cryptsetup luksOpen /dev/$device"2" $CRYPT_PART # User will enter encryption password
	mkfs.btrfs /dev/mapper/$CRYPT_PART
}

mountdisk(){
	mount /dev/mapper/$CRYPT_PART /mnt
	mkdir /mnt/boot
	mount /dev/$device"1" /mnt/boot/
}

unmountdisk(){
	umount /dev/$device"1"
	umount /dev/mapper/$CRYPT_PART
	cryptsetup luksClose /dev/mapper/$CRYPT_PART
}

updatemirrors(){
	installpkg "pacman-contrib"
	cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist-backup
	rankmirrors -v -n 5 /etc/pacman.d/mirrorlist-backup > /etc/pacman.d/mirrorlist
}

installloop(){
	progs=''

	([ -f "$progsfile" ] && cp "$progsfile" /tmp/progs.csv) ||
		curl -Ls "$progsfile" | sed '/^#/d' >/tmp/progs.csv
	total=$(wc -l </tmp/progs.csv)
	while IFS=, read -r tag program comment; do
		n=$((n + 1))
		echo "$comment" | grep -q "^\".*\"$" &&
			comment="$(echo "$comment" | sed -E "s/(^\"|\"$)//g")"
		case "$tag" in
		*) progs+="$program " ;;
		esac
	done </tmp/progs.csv

	basestrap /mnt $progs
}

settimezone(){
	artix-chroot /mnt ln -s /usr/share/zoneinfo/$TIME_ZONE /etc/localtime
	artix-chroot /mnt hwclock --systohc
}

setlocale(){

	LOCALE=${LOCALE:="en_US.UTF-8"}
	sleep 2

	artix-chroot /mnt sed -i "s/#$LOCALE/$LOCALE/g" /etc/locale.gen
	artix-chroot /mnt locale-gen

	echo "export LANG=$LOCALE" > /mnt/etc/locale.conf 
	echo "export LC_COLLATE=\"C\"" >> /mnt/etc/locale.conf
}

sethostname(){
	echo "$HOSTNAME" > /mnt/etc/hostname

cat > /mnt/etc/hosts <<HOSTS
127.0.0.1      localhost
::1            localhost
127.0.1.1      $HOSTNAME.localdomain     $HOSTNAME
HOSTS
}

encrypthooks(){
	sed -i 's/^\(HOOKS=["(]base .*\) filesystems \(.*\)$/\1 encrypt lvm2 filesystems \2/g' /mnt/etc/mkinitcpio.conf

	artix-chroot /mnt mkinitcpio -p linux
}

generatefstab(){
	# clear
	fstabgen -U /mnt >> /mnt/etc/fstab

	sleep 3
}

setupgrub(){
	cryptdevice=$(blkid -s UUID -o value /dev/$device"2")
	rootdevice=$(blkid -s UUID -o value /dev/mapper/$CRYPT_PART)

	sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT=\"loglevel=3 quiet\"/GRUB_CMDLINE_LINUX_DEFAULT=\"loglevel=3 quiet cryptdevice=UUID='"$cryptdevice"':cryptlvm root=UUID='"$rootdevice"'\"/g' /mnt/etc/default/grub

	mkdir /mnt/boot/efi
	artix-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=grub
	artix-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
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

wipedisk

formatdisk

mountdisk

#updatemirrors # Update the best mirrors

installloop # Perform Installation

settimezone # Setting timezone

setlocale # Setting locale

sethostname # Setting hostname

# Enable the network manager
ln -s /mnt/etc/runit/sv/NetworkManager /mnt/etc/runit/runsvdir/current

# Setup Root Password
artix-chroot /mnt passwd

encrypthooks # Sets up encrypt + lvm2 hooks

generatefstab # Generates fstab file

setupgrub # Sets up grub with encrypted partitions
