set -e
set -x

if [ ! -d "$DEST" -o ! -d "$EFI" ]; then
    echo DEST and EFI must be set >&2
    exit 1
fi

mkfs.btrfs "$DEST"

mount --mkdir "$DEST" /@mnt
btrfs subvolume create /@mnt
btrfs subvolume create /@mnt/@
btrfs subvolume create /@mnt/@home

mount --mkdir -o noatime,subvol=@ "$DEST" /mnt
mount --mkdir -o noatime,subvol=@home "$DEST" /mnt/home
mount --mkdir "$EFI" /mnt/boot/efi

# otherwise systemd create subvolumes
mkdir -p /mnt/var/lib/portables/
mkdir -p /mnt/var/lib/machines/

pacstrap -K /mnt \
    linux linux-firmware base \
    btrfs-progs grub efibootmgr \
    iwd vim man git base-devel \

genfstab -U /mnt | sed 's/,subvolid=[0-9]\+//' >> /mnt/etc/fstab

mkdir /@mnt/snapshots/
btrfs subvolume snapshot -r /@mnt/@ /@mnt/snapshots/@_$(date -Is)_pacstrap

arch-chroot /mnt << 'ENDOFCHROOT'
ln -s /usr/share/zoneinfo/Europe/Moscow /etc/localtime
echo -e 'en_US.UTF-8 UTF-8\nru_RU.UTF-8 UTF-8' >> /etc/locale.gen
locale-gen
echo root | chpasswd
grub-install --bootloader-id=auto
grub-mkconfig -o /boot/grub/grub.cfg
systemctl enable systemd-resolved
systemctl enable iwd
mkdir /etc/iwd/
echo -e '[General]\nEnableNetworkConfiguration=true' >> /etc/iwd/main.conf
ENDOFCHROOT

btrfs subvolume snapshot -r /@mnt/@ /@mnt/snapshots/@_$(date -Is)_chroot
