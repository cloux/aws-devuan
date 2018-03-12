#!/bin/sh
#
# Download & apply the latest kernel binary from a master server.
#
# This eliminates the need to compile the same kernel on all running server instances.
# One master server compiles and offers the kernel, others can pull from there.
#
# By default, this script assumes the master server is the one responsible for
# the domain set in /etc/default/public-domain.
# Alternatively, other master domains or IP can be specified as a parameter.
#
# NOTE: the kernel on the master domain has to be shared through https as
#       https://$DOMAIN/boot/#KERNEL-FILES#  (e.g.: ln -s /boot /var/www/)
#       If update-kernel.sh is used for kernel compilation on the master, it
#       will automatically generate the necessary "latest" and "modules.tgz" files.
#
# (cloux@rote.ch)
exec 2>&1

# We need to be root
if [ $(id -u) -ne 0 ]; then
	echo "Need to be root!"
	exit
fi

# load default domains to search for latest kernel
[ -r /etc/default/public-domain ] && . /etc/default/public-domain
# allow to override defaults by script parameter 
[ "$1" ] && DOMAINS="$1"

# get the latest kernel version number from one of the domains
for DOMAIN in $DOMAINS; do
	printf "Latest kernel on %s: " "$DOMAIN"
	LATEST=$(wget -qO- "https://$DOMAIN/boot/latest" 2>/dev/null)
	printf "%s\n" "$LATEST"
	[ "$LATEST" ] && break
done

if [ -z "$LATEST" ]; then
	printf "None of the domains share a new kernel.\n"
	exit
fi

if [ -e "/boot/vmlinuz-$LATEST" ]; then
	printf "This kernel is already installed.\n"
	exit
fi

printf "New Kernel %s is available\n" "$LATEST"

# download the new binary kernel
cd /boot || exit
KERNEL_FILES="config System.map modules vmlinuz"
for FILE in $KERNEL_FILES; do
	printf "Downloading %s ... " "$FILE"
	NEWFILE="${FILE}-$LATEST"
	[ "$FILE" = "modules" ] && NEWFILE="$NEWFILE.tgz"
	wget --no-verbose "https://$DOMAIN/boot/$NEWFILE"
	[ $? -eq 0 ] || exit 1
done
printf "Unpack modules into /lib/modules ..."
cd /lib/modules || exit 1
mv -f "/boot/modules-$LATEST.tgz" .
tar xzf "modules-$LATEST.tgz" || exit 1
rm -f "modules-$LATEST.tgz"
printf "OK\n"

# use the new kernel
/usr/sbin/update-grub

exit
