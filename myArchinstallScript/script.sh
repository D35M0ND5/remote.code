#!/usr/bin/env bash

# Enable error handling
set -euo pipefail
trap 'echo "Error on line $LINENO"; exit 1' ERR

# Configuration variables
USER_TARGET_DISK="nvme0n1"
IS_NVME="y"
HOSTNAME="N3M1S1S"
USERNAME="user"
TIMEZONE="Africa/Accra"
LOCALE="en_UK.UTF-8"
KEYMAP="uk"
PACKAGES="base linux linux-firmware networkmanager grub efibootmgr sudo git nano base-devel"

get_user_input() {
    read -p "Is the drive nvme? ('y' or 'n'): " IS_NVME
    read -p "Enter target disk (e.g., nvme0n1): " USER_TARGET_DISK
    TARGET_DISK="/dev/${USER_TARGET_DISK}"
    echo "Target disk $TARGET_DISK selected"
    read -p "Enter hostname: " HOSTNAME
    echo "hostname $HOSTNAME selected"
    read -p "Enter username: " USERNAME
    echo "username $TARGET_DISK selected"
}

partition_disk() {
    echo "Partitioning disk ..."
    
    # choose partition number scheme
    part_number=("p1" "p2" "p3")
    if [[ "$IS_NVME" == "n" ]]; then
        part_number=("1" "2" "3")
    fi

    # Unmount any existing partitions (safety check)
    umount -R /mnt 2>/dev/null || true
    
    # Create GPT partition table
    printf "g\nw" | fdisk "${TARGET_DISK}"
    
    # Create EFI partition
    printf "n\n1\n\n+512M\nt\n1\nw" | fdisk "$TARGET_DISK"
    
    # Create Swap partition
    printf "n\n2\n\n+4G\nt\nswap\nw" | fdisk "$TARGET_DISK"
    
    # Create root partition (remaining space)
    printf "n\n3\n\n\nw\n" | fdisk "$TARGET_DISK"
    
    # Inform kernel about partition changes
    partprobe "$TARGET_DISK"
    
    # Format partitions
    mkfs.fat -F32 "${TARGET_DISK}${part_number[0]}"
    mkswap -F "${TARGET_DISK}${part_number[1]}"
    mkfs.ext4 -F "${TARGET_DISK}${part_number[2]}"
    
    # Mount partitions
    mount "${TARGET_DISK}${part_number[2]}" /mnt
    mkdir -p /mnt/boot/efi
    mount "${TARGET_DISK}${part_number[0]}" /mnt/boot/efi
    swapon "${TARGET_DISK}${part_number[1]}"
    
    echo "Partitioning completed successfully."
}

install_base() {
    echo "Installing base system..."
    pacstrap -K /mnt $PACKAGES
    
    # Generate fstab
    genfstab -U /mnt >> /mnt/etc/fstab
    
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
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
    grub-mkconfig -o /boot/grub/grub.cfg
    
    # Enable NetworkManager
    systemctl enable NetworkManager
    
    # Create user
    useradd -m -G wheel -s /bin/bash $USERNAME
    echo "Set password for $USERNAME:"
    passwd $USERNAME
    
    # Configure sudo
    echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/wheel
    
EOF
}


main() {
    # collect user input variables
    get_user_input
    TARGET_DISK="/dev/${USER_TARGET_DISK}"

    # Verify boot mode
    if [[ ! -d /sys/firmware/efi ]]; then
        echo "System is not booted in UEFI mode!"
        exit 1
    fi
    
    # # Update mirrorlist
    # echo "Updating mirrorlist..."
    reflector --country Ghana --latest 20 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
    # rankmirrors -n 6 /etc/pacman.d/mirrorlist.backup > /etc/pacman.d/mirrorlist
    
    partition_disk
    # install_base
    # configure_system
    
    echo "Installation complete! Reboot your system."
    # umount -R /mnt
}

main "$@"