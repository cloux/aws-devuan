#!/bin/sh
#
# Check/Download/Compile the latest PHP-FPM from stable sources on http://php.net
#  - GCC native architecture optimization
#  - statically linked extensions
#  - without libsystemd dependency
#
# dependencies:
# gcc sed wget bison gawk re2c autoconf automake
# libcurl4-gnutls-dev libicu-dev libbz2-dev libwebp-dev libpng-dev libjpeg-dev
# libreadline-dev libfreetype6-dev libpq-dev libxpm-dev libsodium-dev
#
# (cloux@rote.ch)
###########################################################

printf "PHP-FPM - Download, compile and install the latest stable release\n\n"

# Need to be root
if [ $(id -u) -ne 0 ]; then
	printf "Need to be root!\n"
	exit 1
fi

# Check dependencies
for DEP in gcc bison re2c gawk sed wget autoconf automake bzip2; do
	if [ -z "$(command -v $DEP)" ]; then
		printf "ERROR: Please install '%s' to continue.\n" "$DEP"
		exit 1
	fi
done

#
# Download
#
MAIN_SITE="http://php.net"
LATEST_STABLE_MIRRORS="$MAIN_SITE"$(wget -q -O - "$MAIN_SITE"/downloads.php 2>/dev/null | grep '/get/php' | grep -o '/get/[^"]*' | grep '\.xz/' | sort -n | tail -n 1)
LATEST_STABLE_LINK=$(wget -q -O - $LATEST_STABLE_MIRRORS 2>/dev/null | grep 'tar\.xz' | grep -o 'http[^"]*tar\.xz[^"]*' | sort -R | head -n 1)
SRC_XZ=$(printf "%s" "$LATEST_STABLE_LINK" | grep -o '[^/]*tar\.xz[^/]*')
if [ ! "$SRC_XZ" ]; then
	printf "Error: PHP download link not found.\n"
	exit
fi
cd /usr/src
if [ -f "$SRC_XZ" ]; then
	printf "INFO: File %s already exists, skip download.\n" "/usr/src/$SRC_XZ"
else
	printf "Download: %s\n\n" "$SRC_XZ"
	wget -O $SRC_XZ $LATEST_STABLE_LINK
fi
if [ ! -f "$SRC_XZ" ]; then
	printf "\nError: PHP source file %s download failed.\n" "$SRC_XZ"
	exit
fi

#
# Unpack
#
printf "Unpacking ..."
SRC_DIR=$(printf "%s" $SRC_XZ | sed 's/.tar.xz//')
[ -d "$SRC_DIR" ] && rm -rf "$SRC_DIR"
tar xJf $SRC_XZ
if [ -d "$SRC_DIR" ]; then
	printf "OK\n"
else
	printf "FAILED\n"
	exit
fi
cd "$SRC_DIR"

#
# Configure
#
PHP_VERSION=$(grep 'PHP_VERSION ' main/php_version.h 2>/dev/null | grep -o '[0-9][0-9]*\.[0-9]*')
[ "$PHP_VERSION" ] || PHP_VERSION=$(printf "%s" "$SRC_DIR" | grep -o '[0-9][0-9]*\.[0-9]*')
printf "\nConfigure PHP-FPM v%s ...\n\n" "$PHP_VERSION" | tee "../php-$PHP_VERSION.build.log"
# optimize for native platform, don't generate debug info (-g)
export CFLAGS="-O2 -march=native"
export CXXFLAGS="-O2 -march=native"
./configure --disable-all --enable-fpm --without-fpm-systemd --disable-cgi --disable-cli --disable-phpdbg \
--enable-calendar --enable-ctype --enable-dom \
--enable-exif --enable-fileinfo --enable-filter --enable-hash --enable-intl \
--enable-json --enable-libxml --enable-mbstring --enable-mysqlnd \
--enable-opcache --enable-opcache-file --enable-pdo --enable-phar --enable-posix \
--enable-session --enable-shmop --enable-simplexml --enable-sockets \
--enable-sysvmsg --enable-sysvsem --enable-sysvshm \
--enable-tokenizer --enable-xmlreader --enable-zip \
--with-bz2 --with-curl --with-gd --with-gettext \
--with-mysqli --with-pdo-mysql --with-pgsql --with-readline --with-openssl --with-xsl --with-sodium \
--with-webp-dir --with-jpeg-dir --with-xpm-dir --with-freetype-dir --with-iconv-dir --with-zlib-dir=shared \
--localstatedir=/var --datadir=/usr/local/share/doc --mandir=/usr/local/share/man \
--sysconfdir=/etc --sbindir=/usr/local/sbin --libdir=/usr/lib/php \
--with-config-file-path="/etc/php/$PHP_VERSION/fpm" \
--with-config-file-scan-dir="/etc/php/$PHP_VERSION/fpm/conf.d" | tee -a "../php-$PHP_VERSION.build.log"
if [ ! -s Makefile ]; then
	printf "\nERROR: configuring PHP failed.\n"
	exit
fi

#
# Compile
#
printf "\nCompile PHP-FPM ...\n\n" | tee -a "../php-$PHP_VERSION.build.log"
nice -n 1 make -j $(nproc 2>/dev/null) 2>&1 | tee -a "../php-$PHP_VERSION.build.log"
if [ ! -x sapi/fpm/php-fpm ]; then
	printf "\nERROR: output file sapi/fpm/php-fpm not found!\n"
	exit
fi

#
# Install PHP-FPM
#
#make install
make install-fpm | tee -a "../php-$PHP_VERSION.build.log"
if [ $? -ne 0 ]; then
	printf "\nERROR: installing PHP-FPM failed.\n"
	exit
fi

#
# Install extensions
#
make install-modules | tee -a "../php-$PHP_VERSION.build.log"
EXT_DIR=$(grep '^EXTENSION_DIR' Makefile | grep -o '/.*')
if [ -d "$EXT_DIR" ]; then
	INI_DIR="/etc/php/$PHP_VERSION/extensions"
	[ -d "$INI_DIR" ] || mkdir -p "$INI_DIR"
	for extension in "$EXT_DIR"/*.so; do
		INI_FILE=$(printf "%s" "$extension" | grep -o '[^/]*$' | sed 's/so$/ini/')
		printf " Configure shared extension: %s - %s\n" "${extension##*/}" "$INI_DIR/$INI_FILE"
		if [ "$INI_FILE" = "opcache.ini" ] || [ "$INI_FILE" = "xdebug.ini" ]; then
			printf "zend_extension=%s\n" "$extension" > "$INI_DIR/$INI_FILE"
		else
			printf "extension=%s\n" "$extension" > "$INI_DIR/$INI_FILE"
		fi
	done
fi

#
# Cleanup
#
printf "\nCleanup ..."
cd /usr/src
rm -rf "/usr/src/$SRC_DIR"
#rm -f "/usr/src/$SRC_XZ"
printf "OK\n"

printf "\nDONE\n"
exit

