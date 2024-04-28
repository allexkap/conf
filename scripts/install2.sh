set -e
set -o pipefail

if [ -z "$USER"]; then
    echo USER must be set >&2
    exit 1
fi

useradd -mU "$USER"
passwd "$USER"

sed -i "\
/GRUB_TIMEOUT=/s/5/0/;\
/GRUB_TIMEOUT_STYLE=/s/menu/hidden/;\
/GRUB_DISABLE_OS_PROBER=/s/#//;\
" /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg
echo 'install nouveau /usr/bin/false' > /etc/modprobe.d/blacklist.conf
mkinitcpio -P

pacman --noconfirm -S \
    hyprland hyprlock hypridle \
    waybar foot doas \
    polkit ttf-font-awesome \

ln -s /usr/bin/doas /usr/local/bin/sudo
echo 'permit persist :wheel' > /etc/doas.conf
usermod -aG wheel "$USER"

mkdir /etc/systemd/system/getty@tty1.service.d/
echo -e "[Service]\nExecStart=\nExecStart=-/sbin/agetty -a $USER %I \$TERM" \
    > /etc/systemd/system/serial-getty@ttyS0.service.d/autologin.conf
echo -e "if [ -z \"\$WAYLAND_DISPLAY\" ] && [ \"\$XDG_VTNR\" -eq 1 ]; then\n    exec hyprland\nfi" \
    > /etc/profile.d/autologin.sh

mkdir -p ~/.tmp/clone && cd $_
git clone https://aur.archlinux.org/paru.git
cd paru
makepkg -si

paru iwgtk
