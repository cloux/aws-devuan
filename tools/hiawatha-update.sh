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

# Make sure that I'm root
if [ "$(id -u)" != "0" ]; then
	echo "$0 - This script must be run as root!" 1>&2
	exit 1
fi

if [ ! -x "$(which hiawatha)" ]; then
	echo "Hiawatha not found. Install dependencies..."
	APTINST=
	if [ -x "$(which aptitude)" ]; then
		APTINST=aptitude
	elif [ -x "$(which apt-get)" ]; then
		APTINST=apt-get
	fi
	if [ "$APTINST" ]; then
		$APTINST install cmake make lsof libxml2 libxml2-dev libxslt1.1 \
		         libxslt1-dev libc6-dev libssl-dev zlib1g-dev dpkg-dev \
		         debhelper fakeroot apache2-utils php php-cgi procps wget
	else
		echo "WARNING: Apt packaging system not found, dependencies installation skipped."
	fi
fi

if [ ! -x "$(which lsof)" ]; then
	echo "ERROR: lsof not found, exiting."
	exit 1
fi

[ -d "$MY_ROOT" ] || mkdir -p "$MY_ROOT"
cd "$MY_ROOT" || exit 1

LATEST=$(wget -q -O - http://www.hiawatha-webserver.org/latest)
if [ -z "$LATEST" ]; then
	echo "ERROR: Hiawatha version number downloading failed"
	exit 1
fi
if [ -s $MY_ROOT/hiawatha-$LATEST.tar.gz ]; then
	echo "Latest Hiawatha v$LATEST already downloaded."
	exit 0
fi

echo -n "Downloading new Hiawatha v$LATEST ..."
wget -q -O $MY_ROOT/hiawatha-$LATEST.tar.gz http://www.hiawatha-webserver.org/files/hiawatha-$LATEST.tar.gz
if [ -s $MY_ROOT/hiawatha-$LATEST.tar.gz ]; then
	echo "OK"
else
	echo "ERROR"
	rm -f $MY_ROOT/hiawatha-$LATEST.tar.gz
	exit 1
fi

echo -n "Unpacking..."
tar -xzf $MY_ROOT/hiawatha-$LATEST.tar.gz >/dev/null
if [ $? -ne 0 ]; then
	echo "ERROR"
	exit 1
fi
echo "OK"

if [ ! -d $MY_ROOT/hiawatha-$LATEST ]; then
	echo "ERROR: hiawatha-$LATEST directory not found."
	exit 1
fi

EC=1
if [ -x "$(which dpkg)" ]; then
	echo "Compiling and packaging..."
	cd $MY_ROOT/hiawatha-$LATEST/extra
	$MY_ROOT/hiawatha-$LATEST/extra/make_debian_package

	DEBPAK=$(ls -1 $MY_ROOT/hiawatha-$LATEST/hiawatha_$LATEST\_*.deb 2>/dev/null | tail -n 1)
	if [ ! -s "$DEBPAK" ]; then
		echo -e "\nFAILED"
		echo "DEB package not found!"
		exit 1
	fi

	# stop hiawatha on supervised init:
	if [ -z "$(runlevel 2>/dev/null | grep -v unknown)" ]; then
		mv -n /etc/init.d/hiawatha /etc/init.d/hiawatha.dpkg
		rm -f /etc/init.d/hiawatha; touch /etc/init.d/hiawatha
		if [ "$(pgrep runsvdir)" ]; then
			# runit supervisor
			sv stop hiawatha
		elif [ "$(pgrep s6-svscan)" ]; then
			# s6 supervisor
			s6-svc -wd hiawatha
		fi
	fi

	echo "Installing new ${DEBPAK##*/}..."
	dpkg -i --force-all $DEBPAK
	EC=$?

	# start hiawatha after update
	if [ "$(pgrep runsvdir)" ]; then
		sv start hiawatha
	elif [ "$(pgrep s6-svscan)" ]; then
		s6-svc -u hiawatha
	fi

	mv "$DEBPAK" "$MY_ROOT"
else
	echo "Cmake build..."
	mkdir build && cd build
	cmake ..
	if [ $? -eq 0 ]; then
		echo "Make install..."
		make install/strip
		EC=$?
	fi
fi

echo -n "Removing temp files..."
cd $MY_ROOT
rm -rf $MY_ROOT/hiawatha-$LATEST
echo "DONE"

if [ $EC -eq 0 ]; then
	MSG="Hiawatha webserver successfully updated to v$LATEST."
else
	MSG="Hiawatha webserver update to v$LATEST FAILED."
fi
echo $MSG

# Email results
if [ "$MAILTO" ]; then
	echo "$MSG" | mail -s "$(hostname 2>/dev/null) (IP $(hostname -i 2>/dev/null)) - Hiawatha update v$LATEST" "$MAILTO"
fi

exit $EC
