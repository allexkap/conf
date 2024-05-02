set -e
set -o pipefail

if [ ! -b "$DEST" -o ! -b "$EFI" -o -z "$USERADD" ]; then
	echo DEST, EFI and USERADD must be set >&2
	exit 1
fi

mkfs.btrfs "$DEST"

mount -m "$DEST" /@mnt
btrfs subvolume create /@mnt/@
btrfs subvolume create /@mnt/@home

mount -m -o noatime,subvol=@ "$DEST" /mnt
mount -m -o noatime,subvol=@home "$DEST" /mnt/home
mount -m "$EFI" /mnt/boot/efi

# otherwise systemd create subvolumes
mkdir -p /mnt/var/lib/portables/
mkdir -p /mnt/var/lib/machines/

sed '/ParallelDownloads/s/#//' -i /etc/pacman.conf

pacstrap -K /mnt \
	linux linux-firmware base \
	btrfs-progs grub efibootmgr \

genfstab -U /mnt | sed 's/,subvolid=[0-9]\+//' >> /mnt/etc/fstab

mkdir /@mnt/snapshots/
btrfs subvolume snapshot -r /@mnt/@ /@mnt/snapshots/@_$(date -Is)_pacstrap

arch-chroot /mnt <<- ENDOFCHROOT
	set -e
	ln -s /usr/share/zoneinfo/Europe/Moscow /etc/localtime
	echo -e 'en_US.UTF-8 UTF-8\nru_RU.UTF-8 UTF-8' >> /etc/locale.gen
	locale-gen
	passwd -d root
	grub-install --bootloader-id=auto
	grub-mkconfig -o /boot/grub/grub.cfg
ENDOFCHROOT

btrfs subvolume snapshot -r /@mnt/@ /@mnt/snapshots/@_$(date -Is)_bootable


arch-chroot /mnt <<- ENDOFCHROOT
	set -e
	useradd -mU "$USERADD"
	passwd -d "$USERADD"

	sed -e '/GRUB_TIMEOUT=/s/5/0/' \\
		-e '/GRUB_TIMEOUT_STYLE=/s/menu/hidden/' \\
		-e '/GRUB_DISABLE_OS_PROBER=/s/#//' \\
		-i /etc/default/grub
	grub-mkconfig -o /boot/grub/grub.cfg
	echo 'install nouveau /usr/bin/false' > /etc/modprobe.d/blacklist.conf
	mkinitcpio -P

	sed '/ParallelDownloads/s/#//' -i /etc/pacman.conf

	pacman --noconfirm -S \\
		hyprland hyprlock hypridle waybar \\
		foot vim yazi imv firefox nautilus \\
		fuzzel grim slurp wl-clipboard \\
		networkmanager brightnessctl power-profiles-daemon \\
		doas fish man git jq neofetch \\
		polkit ttf-font-awesome \\

	ln -s /usr/bin/doas /usr/local/bin/sudo
	echo 'permit persist :wheel' > /etc/doas.conf
	usermod -aG wheel "$USERADD"

	mkdir /etc/systemd/system/getty@tty1.service.d/
	echo -e "[Service]\nExecStart=\nExecStart=-/sbin/agetty -a "$USERADD" %I \\\$TERM" \\
		> /etc/systemd/system/getty@tty1.service.d/autologin.conf
	echo -e "\nif [ -z \"\\\$WAYLAND_DISPLAY\" ] && [ \"\\\$XDG_VTNR\" -eq 1 ]; then\n\texec Hyprland\nfi" \\
		>> /etc/profile
	# \\\$ ok...

	systemctl enable NetworkManager

	su "$USERADD" <<- ENDOFSU
		set -e
		mkdir ~/projects/ && cd \\\$_
		git clone https://github.com/allexkap/conf

		mkdir ~/.ssh/
		ln -s ~/projects/conf/.ssh/config ~/.ssh/
		ln -s ~/projects/conf/.config/ ~/

		mkdir -p ~/.tmp/clone && cd \\\$_
		git clone https://aur.archlinux.org/paru.git

		# todo
	ENDOFSU
ENDOFCHROOT

btrfs subvolume snapshot -r /@mnt/@ /@mnt/snapshots/@_$(date -Is)_hyprland
