#!/bin/sh
#
# renew certificates, update the hiawatha certificate full chain
# into /etc/letsencrypt/archive/$DOMAIN/hiawatha.pem
#
# To create/update a certificate, run certbot like:
# certbot certonly --webroot -w /var/www -d example.com -d www.example.com
#
# NOTE: TLSCertFile parameter in hiawatha.conf has to be set to:
#       /etc/letsencrypt/archive/DOMAIN/hiawatha.pem
#
# (cloux@rote.ch)
#########################################################################
# Set this variable if you want an email on certificate renewal
# example: MAILTO=admin@yourserver.com
MAILTO=
#########################################################################
exec 2>&1

if [ -z "$(command -v certbot)" ]; then
	printf "ERROR: certbot not installed, exiting.\n"
	exit 1
fi

# Kill the annoying certbot systemd auto-updater service.
# That would otherwise perform the update sooner, and this script
# would never get to update anything!
# NOTE: this "disabling" has to be done periodically!!!
#       Sadly, I was unable to find a better way to disable systemd
#       updater, so this is a crude hack :/
if [ -s "/lib/systemd/system/certbot.timer" ]; then
	printf "" > /lib/systemd/system/certbot.timer
	printf "" > /lib/systemd/system/certbot.service
fi

LETSENCRYPT_BASE=/etc/letsencrypt/archive
LOGFILE="$LETSENCRYPT_BASE/renewal.log"

printf "Certificate Renewal at %s by $0\n" "$(date '+%Y-%m-%d %H:%M:%S')" | tee "$LOGFILE"
certbot renew 2>/dev/null | tee -a "$LOGFILE"

RENEWED=0
DOMAINS=$(find "$LETSENCRYPT_BASE" -mindepth 1 -maxdepth 1 -type d -printf '%f ' 2>/dev/null)
for DOMAIN in $DOMAINS; do
	LETSENCRYPT_DIR="$LETSENCRYPT_BASE/$DOMAIN"
	cat "$(ls -t1 "$LETSENCRYPT_DIR/privkey"* 2>/dev/null | head -n 1)" \
	    "$(ls -t1 "$LETSENCRYPT_DIR/fullchain"* 2>/dev/null | head -n 1)" \
	     >"$LETSENCRYPT_DIR/hiawatha.pem.new" 2>/dev/null
	if [ -s "$LETSENCRYPT_DIR/hiawatha.pem.new" ]; then
		NEWCERT="YES"
		if [ -s "$LETSENCRYPT_DIR/hiawatha.pem" ]; then
			NEWCERT=$(diff -q "$LETSENCRYPT_DIR/hiawatha.pem.new" "$LETSENCRYPT_DIR/hiawatha.pem" 2>/dev/null)
		fi
		if [ "$NEWCERT" ]; then
			mv -f "$LETSENCRYPT_DIR/hiawatha.pem.new" "$LETSENCRYPT_DIR/hiawatha.pem"
			RENEWED=1
		fi
	fi
	rm -f "$LETSENCRYPT_DIR/hiawatha.pem.new"
done

if [ $RENEWED -eq 1 ]; then
	printf "Generated New Hiawatha Certificate: %s/hiawatha.pem\n" "$LETSENCRYPT_DIR" | tee -a "$LOGFILE"

	# restart services
	printf "Restarting services ...\n"
	if [ "$(pgrep runsvdir)" ]; then
		# runit supervisor
		if [ -e "/etc/service/hiawatha" ] && [ "$(sv status hiawatha | grep '^run')" ]; then
			sv restart hiawatha | tee -a "$LOGFILE"
		fi
		if [ -e "/etc/service/dovecot" ] && [ "$(sv status dovecot | grep '^run')" ]; then
			sv restart dovecot | tee -a "$LOGFILE"
		fi
	elif [ "$(runlevel 2>/dev/null | grep -v unknown)" ]; then
		# sysvinit
		[ -x "/etc/init.d/hiawatha" ] && /etc/init.d/hiawatha restart | tee -a "$LOGFILE"
		[ -x "/etc/init.d/dovecot" ] && /etc/init.d/dovecot restart | tee -a "$LOGFILE"
	fi
	printf "DONE\n" | tee -a "$LOGFILE"

	if [ "$MAILTO" ]; then
		printf "Sending status EMail to: %s... \n" "$MAILTO"
		mail -s "$(hostname 2>/dev/null) (IP $(hostname -i 2>/dev/null)) - Webserver Certificate Renewal" "$MAILTO" < "$LOGFILE"
	fi
fi
