#!/usr/bin/env bash

# Enable error handling
set -euo pipefail
trap 'echo "Error on line $LINENO"; exit 1' ERR

# Configuration variables
USER_TARGET_DISK="nvme0n1"
IS_NVME="y"
HOSTNAME="N3M1S1S"
USERNAME="user"
PASSWRD=""
TIMEZONE="Africa/Accra"
LOCALE="en_UK.UTF-8"
KEYMAP="uk"
PACKAGES="base linux linux-firmware networkmanager grub efibootmgr sudo git nano base-devel fish"

get_user_input() {
    read -p "Is the drive nvme? ('y' or 'n'): " IS_NVME
    read -p "Enter target disk (e.g., nvme0n1): " USER_TARGET_DISK
    TARGET_DISK="/dev/${USER_TARGET_DISK}"
    echo "Target disk $TARGET_DISK selected"
    echo "Warning! stuff's gonna get cleared off $TARGET_DISK!! Check again!"
    echo " "
    read -p "Enter hostname: " HOSTNAME
    read -p "Enter username: " USERNAME
}

partition_disk() {
    echo " "
    echo "------------------------------------------"
    echo " "
    echo "Partitioning disk ..."
    echo " "
    
    # choose partition number scheme
    part_number=("p1" "p2" "p3")
    if [[ "$IS_NVME" == "n" ]]; then
        part_number=("1" "2" "3")
    fi

    fdisk "$TARGET_DISK" <<EOF
# Create new GPT table
g
# Create new EFI partition
n


+512M
t
1
# Create new Swap partition
n


+4G
t
2
swap
# Create root partition
n



w
EOF

    # # Unmount any existing partitions (safety check)
    # umount -R /mnt 2>/dev/null || true
    
    # # Create GPT partition table
    # printf "g\nw" | fdisk "${TARGET_DISK}"
    
    # # Create EFI partition
    # printf "n\n1\n\n+512M\nt\n1\nw" | fdisk "$TARGET_DISK"
    
    # # Create Swap partition
    # printf "n\n2\n\n+4G\nt\nswap\nw" | fdisk "$TARGET_DISK"
    
    # # Create root partition (remaining space)
    # printf "n\n3\n\n\nw\n" | fdisk "$TARGET_DISK"
    
    # Inform kernel about partition changes
    partprobe "$TARGET_DISK"
    
    # Format partitions
    mkfs.fat -F32 "${TARGET_DISK}${part_number[0]}"
    mkswap "${TARGET_DISK}${part_number[1]}"
    mkfs.ext4 "${TARGET_DISK}${part_number[2]}"
    
    # Mount partitions
    mount "${TARGET_DISK}${part_number[2]}" /mnt
    mkdir -p /mnt/boot/efi
    mount "${TARGET_DISK}${part_number[0]}" /mnt/boot/efi
    swapon "${TARGET_DISK}${part_number[1]}"
    
    echo "Partitioning completed successfully."
}

install_base() {
    echo " "
    echo "------------------------------------------"
    echo " "
    echo "Installing base system..."
    echo " "
    pacstrap -K /mnt $PACKAGES
    
    # Generate fstab
    echo " "
    echo "------------------------------------------"
    echo " "
    genfstab -U /mnt >> /mnt/etc/fstab
    
}

configure_system() {
    echo " "
    echo "------------------------------------------"
    echo " "
    echo "Configuring system..."
    echo " "
    arch-chroot /mnt /bin/bash <<EOF
    ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime                                       # Set timezone
    hwclock --systohc

    sed -i "s/#$LOCALE/$LOCALE/" /etc/locale.gen                                              # Set locale
    locale-gen
    echo "LANG=$LOCALE" > /etc/locale.conf

    echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf                                                # Set keymap

    echo "$HOSTNAME" > /etc/hostname# Set hostname

    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB          # Install bootloader
    grub-mkconfig -o /boot/grub/grub.cfg

    systemctl enable NetworkManager                                                          # Enable NetworkManager and Bluetooth
EOF

    echo " "
    echo "------------------------------------------"
    echo " "
    echo "Set new root password..."                                                            # Root password
    passwd

    useradd -m -G wheel $USERNAME                                                           # Create user
    echo " "
    echo "Set user password..."
    passwd $USERNAME

    echo " "
    echo "------------------------------------------"
    echo " "
    echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/wheel                                     # Configure sudo
    
    echo " "
    su $USERNAME
    chsh -s /bin/fish                                                                      # Set fish as shell
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
    
    # Update mirrorlist
    echo " "
    echo "------------------------------------------"
    echo " "
    echo "Updating mirrorlist..."
    echo " "
    reflector --latest 20 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
    
    partition_disk
    install_base
    configure_system
    
    echo " "
    echo "------------------------------------------"
    echo " "
    echo "Installation complete! Reboot your system."
    # umount -R /mnt
}

main "$@"
