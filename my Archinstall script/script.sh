#!/usr/bin/env bash

# Enable error handling
set -euo pipefail
trap 'echo "Error on line $LINENO"; exit 1' ERR

# Configuration variables
TARGET_DISK="/dev/nvme0n1"
HOSTNAME="myarch"
USERNAME="user"
TIMEZONE="Europe/London"
LOCALE="en_US.UTF-8"
KEYMAP="us"
PACKAGES="base linux linux-firmware networkmanager grub efibootmgr sudo git"

get_user_input() {
    read -p "Enter target disk (e.g., /dev/nvme0n1): " TARGET_DISK
    echo "Target disk $TARGET_DISK selected"
    read -p "Enter hostname: " HOSTNAME
    echo "HOSTNAME $HOSTNAME selected"
    read -p "Enter username: " USERNAME
    echo "username $TARGET_DISK selected"
}

partition_disk() {
    echo "Partitioning disk..."
    
    # GPT partition table
    parted -s "$TARGET_DISK" mklabel gpt
    
    # EFI partition (512MB)
    parted -s "$TARGET_DISK" mkpart primary fat32 1MiB 513MiB
    parted -s "$TARGET_DISK" set 1 esp on
    
    # Root partition (remainder)
    parted -s "$TARGET_DISK" mkpart primary ext4 513MiB 100%
    
    # Format partitions
    mkfs.fat -F32 "${TARGET_DISK}p1"
    mkfs.ext4 "${TARGET_DISK}p2"
    
    # Mount partitions
    mount "${TARGET_DISK}p2" /mnt
    mkdir /mnt/boot
    mount "${TARGET_DISK}p1" /mnt/boot
}

install_base() {
    echo "Installing base system..."
    pacstrap /mnt $PACKAGES
    
    # Generate fstab
    genfstab -U /mnt >> /mnt/etc/fstab
    
    # Copy the install script to new system for stage 2
    cp "$0" /mnt/root/install.sh
    chmod +x /mnt/install.sh
}

configure_system() {
    echo "Configuring system..."
    arch-chroot /mnt /bin/bash <<EOF
    # Set timezone
    ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
    hwclock --systohc
    
    # Set locale
    sed -i "s/#$LOCALE/$LOCALE/" /etc/locale.gen
    locale-gen
    echo "LANG=$LOCALE" > /etc/locale.conf
    
    # Set keymap
    echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf
    
    # Set hostname
    echo "$HOSTNAME" > /etc/hostname
    
    # Configure hosts file
    cat > /etc/hosts <<HOSTS
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
HOSTS
    
    # Install bootloader
    grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
    grub-mkconfig -o /boot/grub/grub.cfg
    
    # Enable NetworkManager
    systemctl enable NetworkManager
    
    # Create user
    useradd -m -G wheel -s /bin/bash $USERNAME
    echo "Set password for $USERNAME:"
    passwd $USERNAME
    
    # Configure sudo
    echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/wheel
    
    # Run stage 2 of installation
    /root/install.sh --stage2
EOF
}

stage2_install() {
    echo "Running stage 2 installation..."
    
    # Install yay for AUR packages
    sudo -u $USERNAME bash <<EOF
    git clone https://aur.archlinux.org/yay.git /tmp/yay
    cd /tmp/yay
    makepkg -si --noconfirm
EOF
    
    # Install additional packages
    yay -S --noconfirm neovim git zsh tmux
    
    # Clone dotfiles
    sudo -u $USERNAME bash <<EOF
    git clone https://github.com/yourusername/dotfiles.git ~/.dotfiles
    ~/.dotfiles/install.sh
EOF
    
    # Set zsh as default shell
    chsh -s /bin/zsh $USERNAME
}

main() {
    # collect user input variables
    get_user_input

    if [[ "$1" == "--stage2" ]]; then
        stage2_install
        exit 0
    fi
    
    # Verify boot mode
    if [[ ! -d /sys/firmware/efi ]]; then
        echo "System is not booted in UEFI mode!"
        exit 1
    fi
    
    # Update mirrorlist
    echo "Updating mirrorlist..."
    reflector --country UK --latest 10 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
    
    partition_disk
    install_base
    configure_system
    
    echo "Installation complete! Reboot your system."
    umount -R /mnt
}

main "$@"