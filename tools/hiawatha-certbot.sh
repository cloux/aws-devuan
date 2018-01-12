#!/bin/bash
#
# renew certificates, update the hiawatha certificate full chain
# into /etc/letsencrypt/archive/$DOMAIN/hiawatha.pem
#
# To create/update a certificate, run certbot like:
# certbot certonly --webroot -w /var/www -d rote.ch -d secure.rote.ch -d www.rote.ch
# certbot certonly --webroot -w /var/www/clixt.net -d clixt.net -d www.clixt.net
#
# NOTE: TLSCertFile in hiawatha.conf has to be set to:
#       /etc/letsencrypt/archive/DOMAIN/hiawatha.pem
#
#########################################################################
# Set this variable, if you want to be informed per email:
# example: MAILTO=admin@yourserver.com
MAILTO=
#########################################################################

if [ ! -x "$(which certbot 2>/dev/null)" ]; then
  echo "certbot not installed, exiting."
  exit 1
fi

# Kill the annoying certbot systemd auto-updater service.
# That would otherwise perform the update sooner, and this script
# would never get to update anything!
# NOTE: this "disabling" has to be done periodically!!!
#       Sadly, I was unable to find a better way to disable systemd
#       updater, so this is a crude hack :/
if [ -s "/lib/systemd/system/certbot.timer" ]; then
	echo -n "" > /lib/systemd/system/certbot.timer
	echo -n "" > /lib/systemd/system/certbot.service
fi

LETSENCRYPT_BASE=/etc/letsencrypt/archive
LOGFILE="$LETSENCRYPT_BASE/renewal.log"

echo -e "Certificate Renewal at $(date '+%Y-%m-%d %H:%M:%S') by $0\n" | tee "$LOGFILE"
certbot renew 2>/dev/null | tee -a "$LOGFILE"

RENEWED=0
DOMAINS=$(find "$LETSENCRYPT_BASE" -mindepth 1 -maxdepth 1 -type d -printf '%f ' 2>/dev/null)
for DOMAIN in ${DOMAINS[@]}; do
	LETSENCRYPT_DIR="$LETSENCRYPT_BASE/$DOMAIN"
	cat "$LETSENCRYPT_DIR/$(ls -t1 privkey* 2>/dev/null | head -n 1)" \
	    "$LETSENCRYPT_DIR/$(ls -t1 fullchain* 2>/dev/null | head -n 1)" \
	     >"$LETSENCRYPT_DIR/hiawatha.pem.new" 2>/dev/null
	if [ -s "$LETSENCRYPT_DIR/hiawatha.pem.new" ]; then
		NEWCERT="YES"
		if [ -s "$LETSENCRYPT_DIR/hiawatha.pem" ]; then
			NEWCERT=$(diff -q "$LETSENCRYPT_DIR/hiawatha.pem.new" "$LETSENCRYPT_DIR/hiawatha.pem" 2>/dev/null)
		fi
		if [ -z "$NEWCERT" ]; then
			rm "$LETSENCRYPT_DIR/hiawatha.pem.new"
		else
			mv -f "$LETSENCRYPT_DIR/hiawatha.pem.new" "$LETSENCRYPT_DIR/hiawatha.pem"
			RENEWED=1
		fi
	fi
done

if [ $RENEWED -eq 1 ]; then
	echo "Generated New Hiawatha Certificate: $LETSENCRYPT_DIR/hiawatha.pem" | tee -a "$LOGFILE"

	# restart services
	if [ -e "/etc/service/hiawatha" ]; then
		sv restart hiawatha 2>&1 | tee -a "$LOGFILE"
	elif [ -e "/etc/init.d/hiawatha" ]; then
		/etc/init.d/hiawatha restart 2>&1 | tee -a "$LOGFILE"
	fi
	if [ -e "/etc/service/dovecot" ]; then
		sv restart dovecot 2>&1 | tee -a "$LOGFILE"
	elif [ -e "/etc/init.d/dovecot" ]; then
		/etc/init.d/dovecot restart 2>&1 | tee -a "$LOGFILE"
	fi
	echo "DONE" | tee -a "$LOGFILE"

	if [ "$MAILTO" ]; then
		echo -n "Sending status EMail to: $MAILTO... "
		cat "$LOGFILE" | mail -s "$(hostname 2>/dev/null) (IP $(hostname -i 2>/dev/null)) - Webserver Certificate Renewal" "$MAILTO"
	fi
fi
