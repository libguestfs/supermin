#!/bin/sh -

# Before running, make sure 'vmlinuz' in this examples directory is a
# bootable Linux kernel or a symlink to one.  You can just use any
# kernel out of the /boot directory for this.
#
# eg:
# cd examples
# ln -s /boot/vmlinuz-NNN vmlinuz

# This creates a very minimal filesystem, just containing bash and a
# few command line utilities.  One of the joys of Fedora is that even
# this minimal install is still 200 MB ...

../febootstrap -i bash -i coreutils fedora-10 ./minimal $1

# ... but let's minimize it aggressively.

echo -n "Before minimization: "; du -sh minimal
../febootstrap-minimize --all ./minimal
echo -n "After minimization:  "; du -sh minimal

# Create the /init which is just a simple script to give users an
# interactive shell.

( cd minimal && cat > init <<'__EOF__'
#!/bin/sh
echo; echo; echo
echo "Welcome to the minimal filesystem example"
echo; echo; echo
/bin/bash -i
__EOF__
chmod +x init
)

# Convert the filesystem to an initrd image.

../febootstrap-to-initramfs ./minimal > minimal-initrd.img

# This is needed because of crappiness with qemu.

rm -f zero
dd if=/dev/zero of=zero bs=2048 count=1

# Now run qemu to boot this minimal system.

qemu-system-$(arch) \
  -m 128 \
  -kernel vmlinuz -initrd minimal-initrd.img \
  -hda zero -boot c
