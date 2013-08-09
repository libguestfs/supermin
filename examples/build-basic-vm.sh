#!/bin/bash -

set -e

# This script builds a simple VM that just contains bash (plus any
# dependencies) and an init script that runs bash to give the user a
# shell.  Also included is coreutils so that commands such as 'ls'
# will work.

pkgs="bash coreutils"

# Create a supermin appliance in basic-supermin.d/ subdirectory.
rm -rf basic-supermin.d
mkdir basic-supermin.d
supermin -v --names $pkgs -o basic-supermin.d

# Create an init script.
rm -f init
cat > init <<EOF
#!/bin/bash
exec bash
EOF
chmod 0755 init

# Create an init cpio file containing the init script as "/init".
echo -e "init\n" | cpio --quiet -o -H newc > basic-supermin.d/init.img

# Normally the contents of basic-supermin.d are what you would
# distribute to users.  However for this example, I'm now going to run
# supermin-helper to build the final appliance.
echo "Built the supermin appliance:"
ls -lh basic-supermin.d/

# Build the full appliance.
supermin-helper --copy-kernel -f ext2 basic-supermin.d "$(uname -m)" \
  basic-kernel basic-initrd basic-root

echo "Built the full appliance:"
ls -lh basic-kernel basic-initrd basic-root
echo
echo "To run the full appliance, use a command such as:"
echo "  qemu-kvm -m 512 -kernel basic-kernel -initrd basic-initrd \\"
echo "      -append 'vga=773 selinux=0' \\"
echo "      -drive file=basic-root,format=raw,if=virtio"

# Clean up temporary files.
rm init
