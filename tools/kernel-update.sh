#!/bin/sh
#
# Check/Download/Compile the latest Linux kernel from https://www.kernel.org.
# If checking in GUI, show notification balloon if a new kernel is available.
#
# Usage: kernel-update [moniker] [-c]
#
#        moniker: stable, mainline, longterm, linux-next, etc.
#             -c: just check if new version is available, don't update
#
# dependencies: wget bc libncurses5-dev
#     optional: notify-send, for kernel check GUI notification support
#
# (cloux@rote.ch)
###########################################################

# Linux kernel branch
MONIKER=stable

# How to run kernel configuration:
# "ask"  - use config from previous kernel, ask user for new symbols
# "menu" - same as "ask", then run ncurses tool for modifications
# empty (default) - use config from previous kernel, and apply defaults for
#                   new symbols. Fully automated, for unattended upgrades.
#CONFIGTYPE=ask
CONFIGTYPE=

# Number of simultaneous compilation jobs.
# If not set, detect and use all CPU cores.
JOBS=

# Compilation log will go into: /usr/src/kernel-VERSION/$LOGFILE
LOGFILE=compile.log

# Delete obsolete kernels, keep only the currently used and the new one
#CLEANUP=y
CLEANUP=

# Pack kernel modules into an archive in /boot for sharing.
# Useful when combined with a webserver, and kernel-pull-binary.sh
#SHARE=y
SHARE=

###########################################################

# use configuration file to change above defaults, if available
[ -r /etc/default/kernel-update ] && . /etc/default/kernel-update

# parse parameters
CHECK=""
for PARAM in "$@"; do
	if [ "$PARAM" = "-c" ]; then
		CHECK="Y"
	else
		MONIKER="$PARAM"
	fi
done

# We need to be root to install new kernel
if [ -z "$CHECK" ] && [ $(id -u) -ne 0 ]; then
	printf "Need to be root to update kernel!\n" 1>&2
	exit 1
fi

# Check dependencies
for DEP in wget bc bison flex; do
	if [ -z "$(command -v $DEP)" ]; then
		printf "ERROR: Please install '%s' to continue.\n" "$DEP"
		exit 1
	fi
done

#
# Get information about the latest kernel on kernel.org
#
printf "Searching for kernel update ...\n"
# JSON file with current kernel information.
RELEASES_LINK=https://www.kernel.org/releases.json
cd /tmp || exit 1
wget -q -N "$RELEASES_LINK"
RELEASES_FILE=$(printf "%s" "$RELEASES_LINK" | grep -Po '(?<=/)[^"/]+$')
if [ ! -e "$RELEASES_FILE" ]; then
	printf "ERROR: Link %s not available!\n" "$RELEASES_LINK"
	exit 1
fi
if [ "$MONIKER" = "stable" ]; then
	LATEST_STABLE_VER=$(tr -d ' \n' < "$RELEASES_FILE" | grep -Po '"latest_stable"[^}]+' | grep -Po '\d[^"}]+')
	JSON=$(tr -d ' \n' < "$RELEASES_FILE" | grep -Po "[^{]+\"$LATEST_STABLE_VER\"[^}]+}[^}]*")
else
	JSON=$(tr -d ' \n' < "$RELEASES_FILE" | grep -Po "[^{]+\"$MONIKER\"[^}]+}[^}]*" | head -n 1)
fi
# remove temporary JSON kernel info file
rm "$RELEASES_FILE"
if [ -z "$JSON" ]; then
	echo "ERROR: JSON moniker section for '$MONIKER' not found."
	exit 1
fi
KERNEL_DATE=$(printf "%s" "$JSON" | grep -Po 'isodate[^,}]+' | grep -Po '\d[^"]+')
KERNEL_LINK=$(printf "%s" "$JSON" | grep -Po 'source[^,}]+' | grep -Po '[^"]+/[^"]+')
KERNEL_FILE=$(printf "%s" "$KERNEL_LINK" | grep -Po '[^/]+$')
# Work around weird version numbering differences:
# The numbering scheme in the JSON might differ from vmlinuz-XY kernel
# file name when 0's are involved, like "4.0.0", but "4.0-rc1" :/
KERNEL_VERSION=$(printf "%s" "$JSON" | grep -Po 'version[^,}]+' | grep -Po '\d[^"}]+' | sed 's/-/.0-/')
[ $(printf "%s" "$KERNEL_VERSION" | grep -o '\.' | wc -l) -eq 1 ] && KERNEL_VERSION=$KERNEL_VERSION.0
KERNEL_VERSION=$(printf "%s" "$KERNEL_VERSION" | sed 's/\.0\.0-/.0-/')

printf "Latest %s version: %s (%s)\n" "$MONIKER" "$KERNEL_VERSION" "$KERNEL_DATE"
if [ -e "/boot/vmlinuz-$KERNEL_VERSION" ]; then
	printf "We already have that one.\n"
	exit
fi

#
# If checking, notify the user and exit
#
if [ "$CHECK" ]; then
	printf "This is a new kernel, you may update.\n"
	# show notification balloon in GUI environment
	if [ "$(command -v notify-send)" ]; then
		export DISPLAY=:0
		notify-send --expire-time=30000 \
		  --icon=/usr/share/icons/gnome/48x48/status/software-update-available.png \
		"New $MONIKER kernel $KERNEL_VERSION found"
	fi
	exit
fi

#
# Start Kernel Update
#
exec 2>&1
printf "===================\n%s\n===================\n" "$(date '+%Y-%m-%d %H:%M:%S')"

#
# Download
#
cd /usr/src || exit 1
if [ ! -e "$KERNEL_FILE" ]; then
	printf "\nDownloading ...\n"
	wget --progress=dot:giga "$KERNEL_LINK"
	if [ $? -ne 0 ]; then
		printf "ERROR: kernel download failed.\n"
		exit 1
	fi
fi

#
# Check free space in /usr/src
#
FREE_MB=$(df --block-size=M --output=avail /usr/src | grep -o '[0-9]*')
# rough estimate how much do we need
KERNEL_SIZE_MB=$(du --block-size=M "$KERNEL_FILE" | grep -o '^[0-9]*')
NEEDED_MB=$(printf "22 * %s\n" "$KERNEL_SIZE_MB" | bc)
if [ $NEEDED_MB -gt $FREE_MB ]; then
	printf "ERROR: not enough free space in /usr/src\n"
	printf "You should have at least %s GB free to continue.\n" "$(printf "scale=1; %s/1000\n" "$NEEDED_MB" | bc)"
	exit 1
fi

#
# Unpack
#
printf "Unpacking ...\n"
tar xJf "$KERNEL_FILE"
if [ $? -ne 0 ]; then
	printf "ERROR: Unpacking /usr/src/%s Failed!\n" "$KERNEL_FILE"
	exit 1
fi
rm -f "$KERNEL_FILE"

KERNEL_DIR=$(printf "%s" "$KERNEL_FILE" | grep -Po '.*(?=.tar)')
if [ ! -d "$KERNEL_DIR" ]; then
	printf "ERROR: Kernel path /usr/src/%s not found!\n" "$KERNEL_DIR"
	exit 1
fi
cd "$KERNEL_DIR"

#
# Configure (see CONFIGTYPE variable)
#
printf "\nConfigure "
# clean up logfile variable
LOGFILE=${LOGFILE##*/}
[ "$LOGFILE" ] || LOGFILE=compile.log
if [ "$CONFIGTYPE" = "ask" ]; then
	# use same configuration as previous kernel, ask user for new symbols
	printf "'%s' ...\n" "$CONFIGTYPE"
	make oldconfig
elif [ "$CONFIGTYPE" = "menu" ]; then
	# same as "old", then run ncurses configuration tool for additional changes
	printf "'%s' ...\n" "$CONFIGTYPE"
	make oldconfig
	make menuconfig
else
	# by default, run automatic unattended update: use previous kernel config, 
	# and apply default values for new symbols
	printf "'unattended' ...\n"
	make olddefconfig
fi

#
# Define compiler threads (see JOBS variable)
#
[ $JOBS -gt 0 ] 2>/dev/null
[ $? -ne 0 ] && JOBS=0
[ $JOBS -gt 0 ] || JOBS=$(nproc --all 2>/dev/null)

#
# Compile
#
printf "Logfile: %s\n" "/usr/src/$KERNEL_DIR/$LOGFILE"
printf "Compile using %s threads ..." "$JOBS"
START=$(date +%s.%N)
nice -n 1 make -j $JOBS >"/usr/src/$KERNEL_DIR/$LOGFILE"
END=$(date +%s.%N)
printf "DONE\n"

#
# Install
#
if [ -s vmlinux ]; then
	printf "\nInstall modules ..."
	make modules_install >>"/usr/src/$KERNEL_DIR/$LOGFILE"
	printf "DONE\n"

	# Do not generate initrd if the feature is disabled in the kernel.
	# See /etc/kernel/postinst.d/initramfs-tools hook script
	(grep -iq 'BLK_DEV_INITRD *= *y' .config) || export INITRD=No

	printf "\nInstall kernel ...\n"
	make install

	printf "\nCompilation FINISHED after [s.ms]: "
else
	tail -n 15 "/usr/src/$KERNEL_DIR/$LOGFILE"
	printf "\nCompilation FAILED after [s.ms]: "
fi
printf "scale=3; (%s - %s)/1\n" "$END" "$START" | bc

[ -e "/boot/vmlinuz-$KERNEL_VERSION" ] || exit 1

#
# Delete obsolete kernels (see CLEANUP variable)
#
OLD_KERNELS=""
CUR_KERNEL=$(uname -r)
if [ "$CLEANUP" = "y" ] && [ -f "/boot/vmlinuz-$CUR_KERNEL" ]; then
	printf "\nKernel cleanup ...\n"
	printf "Current active kernel: %s\n" "$CUR_KERNEL"
	printf "   New updated kernel: %s\n" "$KERNEL_VERSION"
	OLD_KERNELS=$(find /boot -maxdepth 1 -type f -name "vmlinuz*" ! -name "*$CUR_KERNEL" ! -name "*$KERNEL_VERSION" ! -name "*memtest*" -printf '%f ')
	OLD_KERNELS=$(printf "%s" "$OLD_KERNELS" | sed 's/vmlinuz-//g')
	printf "     Obsolete kernels: "
	if [ "$OLD_KERNELS" ]; then
		printf "%s\n" "$OLD_KERNELS"
		printf "Deleting obsolete kernels ..."
		find /boot -maxdepth 1 -type f ! -name "*$CUR_KERNEL" ! -name "*$KERNEL_VERSION" ! -name "*memtest*" -delete
		printf "OK\nDeleting obsolete modules in /lib/modules ..."
		for OLD_KERNEL in $OLD_KERNELS; do
			[ -d "/lib/modules/$OLD_KERNEL" ] && rm -rf "/lib/modules/$OLD_KERNEL"
		done
		printf "OK\nDeleting obsolete sources in /usr/src ..."
		for OLD_KERNEL in $OLD_KERNELS; do
			KERNELSRC_DIR=$(printf "%s" "$OLD_KERNEL" | sed 's/\.0$//')
			[ -d "/usr/src/linux-$KERNELSRC_DIR" ] && rm -rf "/usr/src/linux-$KERNELSRC_DIR"
		done
		printf "OK\n"
		/usr/sbin/update-grub
	else
		printf "none\n"
	fi
elif [ "$CLEANUP" = "y" ]; then
	printf "WARNING: unable to determine current kernel, skipping /boot cleanup.\n"
fi

#
# Clean up /usr/src
#
# force cleanup if the free space left is less than the size of this kernel
FREE_SPACE_MB=$(df --block-size=M --output=avail /usr/src | grep -o '[0-9]*')
KERNEL_SRC_MB=$(du --summarize --block-size=M . | grep -o '^[0-9]*')
if [ $KERNEL_SRC_MB -gt $FREE_SPACE_MB ]; then
	printf "\nFree space left is only %s MB, Cleanup ...\n" "$FREE_SPACE_MB"
	make clean
	# keep only "include", "arch" and "scripts"
	find . -mindepth 1 -maxdepth 1 -type d ! -iname 'arch' ! -iname 'include' ! -iname 'scripts' -exec rm -rf '{}' \;
	# in arch, keep only "x86" and "x86_64"
	find ./arch -mindepth 1 -maxdepth 1 -type d ! -iname 'x86*' -exec rm -rf '{}' \; 2>/dev/null
fi

#
# Pack new kernel modules into /boot (see SHARE variable)
#
# the /boot path can be shared with other systems that need the same kernel, see 'kernel-pull-binary.sh'
if [ "$SHARE" = "y" ] && [ -d "/lib/modules/$KERNEL_VERSION" ]; then
	cd /lib/modules
	printf "\nPack modules into /boot for sharing ..."
	tar czf "/boot/modules-$KERNEL_VERSION.tgz" "$KERNEL_VERSION"
	printf "OK\n"
	# mark the latest available version into /boot/latest
	printf "%s" "$KERNEL_VERSION" > /boot/latest
fi

printf "\nDONE\n"

exit
