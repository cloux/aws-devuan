#!/usr/bin/env bash
#
# Check/Download/Unpack/Compile the latest Linux kernel from www.kernel.org.
# Save progress into /usr/src/linux-NEW/compile.log
#
# Usage: kernel-update [moniker] [-c]
#
#        moniker: stable, mainline, longterm, linux-next...
#                 Go for stable version if empty.
#             -c: just check if new version is available, don't update
#
# dependencies: wget bc libncurses5-dev
#   for -check GUI notification: notify-send
#
# (cloux@rote.ch)
###########################################################

# If not empty, run configuration tool 'make menuconfig'  before compilation
MENUCONFIG=

# Number of simultaneous compilation jobs.
# If not set, detect and use all CPU cores.
JOBS=

# Compilation log will be: /usr/src/kernel-VERSION/$LOGFILE
LOGFILE=compile.log

###########################################################

# parse parameters
MONIKER=stable
CHECK=0
if [ "$1" = "-c" ]; then
	CHECK=1
elif [ "$2" = "-c" ]; then
	MONIKER=$1
	CHECK=1
elif [ "$1" ]; then
	MONIKER=$1
fi

# We need to be root to install new kernel
if [ $CHECK -eq 0 -a $(id -u) -ne 0 ]; then
	echo "Need to be root to update kernel!" 1>&2
	exit 1
fi

# JSON file with current kernel information.
RELEASES_LINK=https://www.kernel.org/releases.json

echo "Searching for kernel update..."
cd /tmp
wget -q -N $RELEASES_LINK
RELEASES_FILE=$(echo $RELEASES_LINK | grep -Po '(?<=/)[^"/]+$')
if [ ! -e "$RELEASES_FILE" ]; then
	echo "Error: Link $RELEASES_LINK not available!"
	exit 1
fi

if [ "$MONIKER" = "stable" ]; then
	LATEST_STABLE_VER=$(cat $RELEASES_FILE | tr -d ' \n' | grep -Po '"latest_stable"[^}]+' | grep -Po '\d[^"}]+')
	JSON=$(cat $RELEASES_FILE | tr -d ' \n' | grep -Po "[^{]+\"$LATEST_STABLE_VER\"[^}]+}[^}]*")
else
	JSON=$(cat $RELEASES_FILE | tr -d ' \n' | grep -Po "[^{]+\"$MONIKER\"[^}]+}[^}]*" | head -n 1)
fi
if [ -z "$JSON" ]; then
	echo "Moniker section for '$MONIKER' not found. Abort."
	exit 1
fi
KERNEL_VERSION=$(echo $JSON | grep -Po 'version[^,}]+' | grep -Po '\d[^"}]+')
KERNEL_VERSION_0=$(echo $KERNEL_VERSION | sed s/-/\.0-/ | sed s/\.0\.0/\.0/)
KERNEL_DATE=$(echo $JSON | grep -Po 'isodate[^,}]+' | grep -Po '\d[^"]+')
KERNEL_LINK=$(echo $JSON | grep -Po 'source[^,}]+' | grep -Po '[^"]+/[^"]+')

echo "Latest $MONIKER version: $KERNEL_VERSION ($KERNEL_DATE)"
KERNEL_FILE=$(echo $KERNEL_LINK | grep -Po '[^/]+$')

rm $RELEASES_FILE

if [ -e "/boot/vmlinuz-$KERNEL_VERSION" -o \
     -e "/boot/vmlinuz-$KERNEL_VERSION_0" -o \
     -e "/boot/vmlinuz-$KERNEL_VERSION.0" ]; then
	echo "We already have that one."
	exit 0
fi

# if we are just checking, notify the user and exit
if [ $CHECK -ne 0 ]; then
	echo "This is a new kernel, you may update."
	# show notification balloon in GUI environment
	if [ -x "$(which notify-send 2>/dev/null)" ]; then
		export DISPLAY=:0
		notify-send --expire-time=30000 \
		  --icon=/usr/share/icons/gnome/48x48/status/software-update-available.png \
		"New $MONIKER kernel $KERNEL_VERSION found"
	fi
	exit 0
fi

# Download
cd /usr/src || exit 1
if [ ! -e "$KERNEL_FILE" ]; then
	echo "Downloading ..."
	wget $KERNEL_LINK
	if [ $? -ne 0 ]; then
		echo "ERROR: kernel download failed."
		exit 1
	fi
fi

# is there enough free space in /usr/src ?
FREE_MB=$(df --block-size=M --output=avail /usr/src | grep -o '[0-9]*')
# rough estimate how much do we need
KERNEL_SIZE_MB=$(du --block-size=M "$KERNEL_FILE" | grep -o '^[0-9]*')
NEEDED_MB=$(echo "22 * $KERNEL_SIZE_MB" | bc)
if [ $NEEDED_MB -gt $FREE_MB ]; then
	echo "ERROR: not enough free space in /usr/src"
	echo "You should have at least $(echo "scale=1; ${NEEDED_MB}/1000" | bc) GB free to continue."
	exit 1
fi

echo "Unpacking ..."
tar -Jxf "$KERNEL_FILE"
if [ $? -ne 0 ]; then
	echo "ERROR: Unpacking /usr/src/$KERNEL_FILE Failed!"
	exit 1
fi
rm -f "$KERNEL_FILE"

KERNEL_DIR=$(echo $KERNEL_FILE | grep -Po '.*(?=.tar)')
if [ ! -d "$KERNEL_DIR" ]; then
	echo "Error: Kernel path /usr/src/$KERNEL_DIR not found!"
	exit 1
fi
cd "$KERNEL_DIR"

# from here on, pipe everything to stdout and compile.log
echo -e "===================\n$(date '+%Y-%m-%d %H:%M:%S')\n===================\n" > \
        "/usr/src/$KERNEL_DIR/compile.log"
exec &> >(tee -a "/usr/src/$KERNEL_DIR/compile.log")

echo "Configure ..."
make oldconfig

# optionally, run ncurses configuration tool
[ "$MENUCONFIG" ] && make menuconfig

# if JOBS not set, use all CPU cores
[ -z "$JOBS" -o "$JOBS" = "0" ] && JOBS=$(nproc --all 2>/dev/null)

echo "Compile using $JOBS threads..."
START=$(date +%s.%N)
make -j $JOBS
END=$(date +%s.%N)

if [ -s vmlinux ]; then
	echo "Install modules ..."
	make modules_install

	# do not generate initrd if the feature is disabled in the kernel
	# see /etc/kernel/postinst.d/initramfs-tools hook script
	[ $(grep -c 'BLK_DEV_INITRD *= *y' .config) -eq 0 ] && export INITRD=No

	echo "Install kernel ..."
	make install

	echo -n "DONE! Compile time using $JOBS threads [s.ms]: "
else
	echo -n "Compilation FAILED after [s.ms]: "
fi
echo "scale=3; ($END - $START)/1" | bc

if [ ! -e "/boot/vmlinuz-$KERNEL_VERSION" -a \
     ! -e "/boot/vmlinuz-$KERNEL_VERSION_0" -a \
     ! -e "/boot/vmlinuz-$KERNEL_VERSION.0" ]; then
	exit 1
fi

# apply dkms
[ -x "$(which dkms 2>/dev/null)" ] && dkms autoinstall

# clean up automatically, if the free space left is less than the size of this kernel
FREE_SPACE_MB=$(df --block-size=M --output=avail /usr/src | grep -o '[0-9]*')
KERNEL_SRC_MB=$(du --summarize --block-size=M . | grep -o '^[0-9]*')
if [ $KERNEL_SRC_MB -gt $FREE_SPACE_MB ]; then
	echo "Free space left is only $FREE_SPACE_MB MB, Cleanup..."
	make clean
	# keep only "include", "arch" and "scripts"
	find -mindepth 1 -maxdepth 1 -type d ! -iname 'arch' ! -iname 'include' ! -iname 'scripts' -exec rm -rf '{}' \;
	# in arch, keep only "x86" and "x86_64"
	cd arch
	find -mindepth 1 -maxdepth 1 -type d ! -iname 'x86*' -exec rm -rf '{}' \;
fi

