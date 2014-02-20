#!/bin/bash -

set -e

# This script builds a simple VM that just contains bash (plus any
# dependencies) and an init script that runs bash to give the user a
# shell.  Also included is coreutils so that commands such as 'ls'
# will work.

if [ "$(id -u)" -eq "0" ]; then
    echo "Do not run this script as root!"
    exit 1
fi

#----------------------------------------------------------------------

# Prepare mode:

pkgs="bash coreutils"

echo "Building a supermin appliance containing $pkgs ..."
echo

# Create a supermin appliance in basic-supermin.d/ subdirectory.
rm -rf basic-supermin.d
mkdir basic-supermin.d
../src/supermin --prepare $pkgs -o basic-supermin.d

# Create an init script.
rm -f init
cat > init <<EOF
#!/bin/bash
exec bash
EOF
chmod 0755 init

# Create a tar file containing the init script as "/init".
tar zcf basic-supermin.d/init.tar.gz init

echo "Built the supermin appliance:"
ls -lh basic-supermin.d/
echo

# Clean up temporary files.
rm init

#----------------------------------------------------------------------

# Build mode:

# Normally the contents of basic-supermin.d are what you would
# distribute to users.  However for this example, I'm now going to run
# supermin --build to build the final appliance.

echo "If you see 'Permission denied' errors here, it could be because your"
echo "distro has decided to engage in security-by-obscurity by making"
echo "some host binaries unreadable by ordinary users.  Normally you can"
echo "ignore these errors."
echo

# Build the full appliance.
rm -rf basic-full-appliance
mkdir basic-full-appliance
../src/supermin --build -f ext2 \
    --copy-kernel --host-cpu "$(uname -m)" \
    -o basic-full-appliance \
    basic-supermin.d

echo
echo "Built the full appliance:"
ls -lsh basic-full-appliance
echo

#----------------------------------------------------------------------

echo "To run the full appliance, use a command such as:"
echo "  qemu-kvm -m 512 -kernel kernel -initrd initrd \\"
echo "      -append 'vga=773 selinux=0' \\"
echo "      -drive file=root,format=raw,if=virtio"
echo

echo "You can examine the supermin appliance in basic-supermin.d/"
echo "You can examine the full appliance in basic-full-appliance/"
echo
