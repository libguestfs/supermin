#!/bin/sh -

# Before running, make sure 'vmlinuz' in this examples directory is a
# bootable Linux kernel or a symlink to one.  You can just use any
# kernel out of the /boot directory for this.
#
# eg:
# cd examples
# ln -s /boot/vmlinuz-NNN vmlinuz
#
# Also make 'guest-image' be a symlink to a virtual machine disk image.

# This is a realistic example for 'libguestfs', which contains a
# selection of command-line tools, LVM, NTFS and an NFS server.

set -e

if [ $(id -u) -eq 0 ]; then
    echo "Don't run this script as root.  Read instructions in script first."
    exit 1
fi

if [ ! -e vmlinuz -o ! -e guest-image ]; then
    echo "Read instructions in script first."
    exit 1
fi

febootstrap \
    -i bash \
    -i coreutils \
    -i lvm2 \
    -i ntfs-3g \
    -i nfs-utils \
    -i util-linux-ng \
    -i MAKEDEV \
    fedora-10 ./guestfs $1

echo -n "Before minimization: "; du -sh guestfs
febootstrap-minimize --all ./guestfs
echo -n "After minimization:  "; du -sh guestfs

# Create the /init which will scan for and enable all LVM volume groups.

create_init ()
{
  cat > /init <<'__EOF__'
#!/bin/sh
PATH=/sbin:/usr/sbin:$PATH
MAKEDEV mem null port zero core full ram tty console fd \
  hda hdb hdc hdd sda sdb sdc sdd loop sd
mount -t proc /proc /proc
mount -t sysfs /sys /sys
mount -t devpts -o gid=5,mode=620 /dev/pts /dev/pts
modprobe sata_nv pata_acpi ata_generic
lvm vgscan --ignorelockingfailure
lvm vgchange -ay --ignorelockingfailure
/bin/bash -i
__EOF__
  chmod +x init
}
export -f create_init
febootstrap-run ./guestfs -- bash -c create_init

# Convert the filesystem to an initrd image.

febootstrap-to-initramfs ./guestfs > guestfs-initrd.img

# Now run qemu to boot this guestfs system.

qemu-system-$(arch) \
  -m 256 \
  -kernel vmlinuz -initrd guestfs-initrd.img \
  -hda guest-image -boot c
