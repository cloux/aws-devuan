#!/bin/sh
#
# Download latest Hiawatha webserver, compile and update.
# For Hiawatha v8.0 and higher.
#
# (cloux@rote.ch)
#########################################################################

# Set this variable, if you want to receive a status mail:
# example: MAILTO=admin@yourserver.com
MAILTO=

#########################################################################

PATH=/usr/local/sbin:/usr/sbin:/sbin:$PATH
# working directory
MY_ROOT=/usr/src/hiawatha


# stop hiawatha on supervised init
hiawatha_stop () {
	if [ "$(pgrep runsvdir)" ] || [ "$(pgrep s6-svscan)" ]; then
		# daemontools-type service supervision
		mv -n /etc/init.d/hiawatha /etc/init.d/hiawatha.dpkg
		rm -f /etc/init.d/hiawatha; touch /etc/init.d/hiawatha
		find /etc/rc*.d -iname '*hiawatha' -delete
	fi
	if [ "$(pgrep runsvdir)" ]; then
		# runit supervisor
		sv stop hiawatha
	elif [ "$(pgrep s6-svscan)" ]; then
		# s6 supervisor
		s6-svc -wd hiawatha
	else
		/etc/init.d/hiawatha stop
	fi
}

# start hiawatha on supervised init
hiawatha_start () {
	if [ "$(pgrep runsvdir)" ]; then
		sv start hiawatha
	elif [ "$(pgrep s6-svscan)" ]; then
		s6-svc -u hiawatha
	else
		/etc/init.d/hiawatha start
	fi
}

# Make sure that I'm root
if [ "$(id -u)" != "0" ]; then
	printf "Need to be root!\n"
	exit 1
fi

if [ -z "$(command -v hiawatha)" ]; then
	printf "Hiawatha not found. Install dependencies ...\n"
	APTINST=
	if [ "$(command -v aptitude)" ]; then
		APTINST=aptitude
	elif [ "$(command -v apt-get)" ]; then
		APTINST=apt-get
	fi
	if [ "$APTINST" ]; then
		$APTINST install cmake make lsof libxml2 libxml2-dev libxslt1.1 \
		         libxslt1-dev libc6-dev libssl-dev zlib1g-dev dpkg-dev \
		         debhelper fakeroot apache2-utils php php-cgi procps wget
	else
		printf "WARNING: Apt packaging system not found, dependencies installation skipped.\n"
	fi
fi

if [ -z "$(command -v lsof)" ]; then
	printf "ERROR: lsof not found, exiting.\n"
	exit 1
fi

[ -d "$MY_ROOT" ] || mkdir -p "$MY_ROOT"
cd "$MY_ROOT" || exit 1

LATEST=$(wget -q -O - https://www.hiawatha-webserver.org/latest 2>/dev/null)
if [ -z "$(printf "%s" "$LATEST" | head -n 1 | grep '^[0-9][0-9.]*$')" ]; then
	printf "WARNING: Hiawatha latest version checking failed.\n"
	exit 0
fi
if [ -s "$MY_ROOT/hiawatha-$LATEST.tar.gz" ]; then
	printf "Latest Hiawatha v%s already downloaded.\n" "$LATEST"
	exit 0
fi

printf "Downloading new Hiawatha v%s ..." "$LATEST"
wget -q -O "$MY_ROOT/hiawatha-$LATEST.tar.gz" "https://www.hiawatha-webserver.org/files/hiawatha-$LATEST.tar.gz"
if [ -s "$MY_ROOT/hiawatha-$LATEST.tar.gz" ]; then
	printf "OK\n"
else
	printf "FAILED\n"
	rm -f "$MY_ROOT/hiawatha-$LATEST.tar.gz"
	exit 0
fi

printf "Unpacking ..."
tar -xzf "$MY_ROOT/hiawatha-$LATEST.tar.gz" >/dev/null
if [ $? -ne 0 ]; then
	printf "ERROR\n"
	exit 1
fi
printf "OK\n"

if [ ! -d "$MY_ROOT/hiawatha-$LATEST" ]; then
	printf "ERROR: hiawatha-%s directory not found.\n" "$LATEST"
	exit 1
fi

EC=1
if [ "$(command -v dpkg)" ]; then
	printf "Compiling and packaging ...\n"
	cd "$MY_ROOT/hiawatha-$LATEST/extra" || exit
	"$MY_ROOT/hiawatha-$LATEST/extra/make_debian_package"

	DEBPAK=$(ls -1 "$MY_ROOT/hiawatha-$LATEST/hiawatha_$LATEST"_*.deb 2>/dev/null | tail -n 1)
	if [ ! -s "$DEBPAK" ]; then
		printf "\nFAILED\n"
		exit 1
	fi

	# stop hiawatha on supervised init
	hiawatha_stop

	printf "Installing new %s ...\n" "${DEBPAK##*/}"
	dpkg -i --force-all "$DEBPAK"
	EC=$?

	# start hiawatha after update
	hiawatha_start

	mv "$DEBPAK" "$MY_ROOT"
else
	printf "Cmake build ...\n"
	mkdir build
	cd build || exit
	cmake ..
	if [ $? -eq 0 ]; then
		# stop hiawatha on supervised init
		hiawatha_stop
		printf "Make install ...\n"
		make install/strip
		EC=$?
		# start hiawatha after update
		hiawatha_start
	fi
fi

printf "Removing temp files ..."
cd "$MY_ROOT" || exit
rm -rf "$MY_ROOT/hiawatha-$LATEST"
printf "DONE\n"

if [ $EC -eq 0 ]; then
	MSG="Hiawatha webserver successfully updated to v$LATEST."
else
	MSG="Hiawatha webserver update to v$LATEST FAILED."
fi
printf "%s\n" "$MSG"

# Email results
if [ "$MAILTO" ]; then
	printf "%s\n" "$MSG" | mail -s "$(hostname 2>/dev/null) (IP $(hostname -i 2>/dev/null)) - Hiawatha update v$LATEST" "$MAILTO"
fi

exit $EC
