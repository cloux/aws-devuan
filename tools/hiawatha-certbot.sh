#!/bin/sh
#
# Create and maintain TLS local and letsencrypt certificates for
# Hiawatha. Use certbot to manage letsencrypt service, generate a
# self-signed certificate chain if letsencrypt is not available.
#
# Certbot working conditions:
# - Webserver must deliver WEBROOT content on $(hostname) over HTTP
# - $(hostname) entry should be present in /etc/default/public-domain
#
# To create letsencrypt certificate for multiple domains, run e.g.:
# certbot certonly --webroot -w /var/www -d example.com -d www.example.com
#
# (cloux@rote.ch)
#########################################################################

# Domain that is expected to be resolved to WEBROOT over HTTP.
# Setting this domain directly in /etc/hostname makes the automation easier.
# See also /etc/default/public-domain and the public-ip command.
# This parameter is mandatory.
DOMAIN="$(hostname 2>/dev/null)"

# Webroot of DOMAIN
# Default: parse the WebsiteRoot path configured for DOMAIN in hiawatha.conf
#WEBROOT="/var/www"
WEBROOT=""

# TLScertFile parameter in hiawatha.conf has to be set to
# /etc/ssl/private/hiawatha.pem. If you change the CERTDIR variable here,
# you have to modify TLScertFile in hiawatha.conf accordingly.
CERTDIR="/etc/ssl/private"

# Log output
LOGFILE="/var/log/certificates.log"

#########################################################################

# Make sure that I'm root
if [ "$(id -u)" != "0" ]; then
	printf "Need to be root!\n"
	exit
fi

# Local server certificate file name, without extension
CERTNAME="server"
# Do we have a new or updated certificate?
RENEWED=0

printf "===============================================================================\n%s\n" \
       "$(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$LOGFILE"

#
# Manage local certificates as fallback, if letsencrypt service is not available
#
[ -d "$CERTDIR" ] || mkdir -p "$CERTDIR"
if [ -f "$CERTDIR/$CERTNAME".crt ] && [ ! -h "$CERTDIR/$CERTNAME".crt ] && \
   [ "$(openssl x509 -in "$CERTDIR/$CERTNAME".crt -text -noout | grep Subject: | grep -o 'CN *=[^,]*' | grep -o '[^ ]*$')" = "$DOMAIN" ]; then
	printf "Certificate for '%s': %s\n" "$DOMAIN" "$CERTDIR/$CERTNAME".crt | tee -a "$LOGFILE"
else
	#
	# Generate local self-signed certificate chain.
	# For fully unattended operation, guessing the certificate parameters
	# from server IP location, local timezone etc.
	#
	printf "Building new local certificate for: %s\n" "$DOMAIN" | tee -a "$LOGFILE"
	CA_KEY="ca.key"
	CA_CRT="ca.crt"
	COUNTRY="$(whois $(/usr/local/bin/public-ip 2>/dev/null | grep -o '^[0-9.]*') 2>/dev/null | grep -i '^country' | head -n 1 | grep -io '[a-z]*$')"
	[ $(printf "%s" "$COUNTRY" | wc -m) -eq 2 ] || COUNTRY="US"
	STATE="$(grep -io '^[a-z]*' /etc/timezone)"
	LOCATION="$(grep -io '[a-z]*$' /etc/timezone)"
	ORGANIZATION="$(grep -io '^[a-z0-9\-]*' /etc/issue)"
	UNIT="Automated CA"
	EMAIL="admin@$DOMAIN"
	VALIDITY=3650
	if [ ! -f "$CERTDIR/$CA_CRT" ]; then
		printf "Generate New Certificate Authority:\n" | tee -a "$LOGFILE"
		openssl req -newkey rsa:4096 -nodes -sha512 -x509 -days $VALIDITY \
		        -keyform PEM -outform PEM -keyout "$CERTDIR/$CA_KEY" -out "$CERTDIR/$CA_CRT" \
		        -subj "/C=$COUNTRY/ST=$STATE/L=$LOCATION/O=$ORGANIZATION/OU=$UNIT/CN=$DOMAIN/emailAddress=$EMAIL" 2>&1 | tee -a "$LOGFILE"
	fi
	printf "Generate Client Key:\n" | tee -a "$LOGFILE"
	openssl req -newkey rsa:4096 -nodes -sha512 -keyform PEM -outform PEM \
	        -keyout "$CERTDIR/$CERTNAME".key -out "$CERTDIR/$CERTNAME".csr \
	        -subj "/C=$COUNTRY/ST=$STATE/L=$LOCATION/O=$ORGANIZATION/OU=$UNIT/CN=$DOMAIN/emailAddress=$EMAIL" 2>&1 | tee -a "$LOGFILE"
	printf "Build signed Client Certificate using CA:\n" | tee -a "$LOGFILE"
	printf "\n[SAN]\nsubjectAltName=DNS:%s\n" "$DOMAIN" > "$CERTDIR"/SANdata
	openssl x509 -req -in "$CERTDIR/$CERTNAME".csr -CA "$CERTDIR/$CA_CRT" -CAkey "$CERTDIR/$CA_KEY" \
	        -sha512 -set_serial "$(shuf -i 256-65535 -n 2 2>/dev/null | tr -d '\n')" -extensions client -days $VALIDITY \
	        -outform PEM -out "$CERTDIR/$CERTNAME".crt -extensions SAN -extfile "$CERTDIR"/SANdata 2>&1 | tee -a "$LOGFILE"
	        # in BASH, the temporary SANdata file can be faked:
	        # -extfile <(printf "\n[SAN]\nsubjectAltName=DNS:%s\n" "$DOMAIN")
	rm -f "$CERTDIR"/SANdata
	if [ -s "$CERTDIR/$CERTNAME".crt ]; then
		# Build certificate chain
		cat "$CERTDIR/$CERTNAME".crt "$CERTDIR/$CA_CRT" >fullchain.crt 2>/dev/null
		# Build Hiawatha TLScertFile
		cat "$CERTDIR/$CERTNAME".key "$CERTDIR/$CERTNAME".crt "$CERTDIR/$CA_CRT" >"$CERTDIR"/hiawatha.pem 2>/dev/null
		# Force service restart
		RENEWED=1
	fi
fi

#
# Manage letsencrypt certificates using certbot
#
if [ -x "$(command -v certbot)" ]; then
	# Disable the default certbot cronjob. That would otherwise run certbot sooner,
	# and this script would never get to update anything.
	[ -s "/etc/cron.d/certbot" ] && printf "" >/etc/cron.d/certbot

	#
	# Wait for kernel random nuber generator (crng) to initialize,
	# certbot certonly will fail without it. Only relevant if started right after boot.
	#
	if [ -z "$(dmesg | grep 'crng.* done')" ]; then
		printf "Wait for kernel crng to initialize ... "
		TIMEOUT=300
		COUNT=0
		while [ $COUNT -lt $TIMEOUT ]; do
			dmesg | grep -q 'crng.* done' && break
			sleep 2
			COUNT=$(($COUNT+1))
		done
		if [ $COUNT -ge $TIMEOUT ]; then
			printf "failed, certbot might not work.\n"
		else
			printf "OK\n"
		fi
	fi

	#
	# Check/obtain new certificate for DOMAIN
	#
	printf -- "-----\n" | tee -a "$LOGFILE"
	LECERT="/etc/letsencrypt/live/$DOMAIN/cert.pem"
	if [ -f "$LECERT" ] && \
	   [ "$(openssl x509 -in "$LECERT" -text -noout | grep Subject: | grep -o 'CN *=[^,]*' | grep -o '[^ ]*$')" = "$DOMAIN" ]; then
		printf "Letsencrypt certificate for '%s' found, valid until: %s\n" "$DOMAIN" \
		       "$(openssl x509 -in "$LECERT" -text -noout | grep -i 'Not After' | sed 's/.* : //')" | tee -a "$LOGFILE"
	else
		printf "'%s' has no letsencrypt certificate.\nNetwork check: " "$DOMAIN" | tee -a "$LOGFILE"
		# Is this server responsible for DOMAIN?
		PUBLIC_IP="$(/usr/local/bin/public-ip 2>/dev/null)"
		if printf "%s" "$PUBLIC_IP" | grep -Fq "$DOMAIN"; then
			printf "OK, our external IP matches our domain: %s\n" "$PUBLIC_IP" | tee -a "$LOGFILE"
			if [ ! -d "$WEBROOT" ]; then
				printf "Trying webroot from hiawatha.conf: " | tee -a "$LOGFILE"
				# Wait for Hiawatha to start. Only relevant during OS boot.
				sleep 2
				# Parse the WEBROOT for DOMAIN from hiawatha.conf:
				WEBROOT="$(grep -v '^\s*#' /etc/hiawatha/hiawatha.conf 2>/dev/null | \
				         tr -s '\n' '|' | grep -o '[^{]*[=,]\s*'"$DOMAIN"'[\s,|][^}]*' | \
				         grep -io 'WebsiteRoot[^|]*' | sed 's/.*=\s*//')"
				printf "%s\n" "$WEBROOT" | tee -a "$LOGFILE"
			fi
			if [ -d "$WEBROOT" ]; then
				# Obtain a new certificate from letsencrypt, if Hiawatha is running
				if [ -e "/etc/service/hiawatha" ] && sv status hiawatha | grep -q '^run'; then
					certbot certonly -n -m "admin@$DOMAIN" --agree-tos --webroot -w "$WEBROOT" -d "$DOMAIN" 2>&1 | tee -a "$LOGFILE"
				else
					printf "Hiawatha is down, can't request new certificate.\n" | tee -a "$LOGFILE"
				fi
			else
				printf "Webroot path '%s' not found, can't request new certificate.\n" "$WEBROOT" | tee -a "$LOGFILE"
			fi
		else
			printf "%s - this server does not seem responsible for '%s'\n" "$PUBLIC_IP" "$DOMAIN" | tee -a "$LOGFILE"
		fi
	fi

	#
	# Try to renew all existing certificates
	#
	if [ "$(find /etc/letsencrypt/live -mindepth 1 -maxdepth 1 -type d -printf '%f' 2>/dev/null)" ]; then
		# is Hiawatha webserver running?
		if [ -e "/etc/service/hiawatha" ] && sv status hiawatha | grep -q '^run'; then
			certbot renew 2>/dev/null | tee -a "$LOGFILE"
		fi
	fi

	#
	# Rebuild and link certificates into CERTDIR
	#
	LETSENCRYPT_BASE="/etc/letsencrypt/archive"
	LE_DOMAINS="$(find "$LETSENCRYPT_BASE" -mindepth 1 -maxdepth 1 -type d -printf '%f ' 2>/dev/null)"
	for LEDOMAIN in $LE_DOMAINS; do
		LETSENCRYPT_DIR="$LETSENCRYPT_BASE/$LEDOMAIN"
		cat "$(ls -t1 "$LETSENCRYPT_DIR/privkey"* 2>/dev/null | head -n 1)" \
		    "$(ls -t1 "$LETSENCRYPT_DIR/fullchain"* 2>/dev/null | head -n 1)" \
		    >"$LETSENCRYPT_DIR/hiawatha.pem.new" 2>/dev/null
		if [ -s "$LETSENCRYPT_DIR/hiawatha.pem.new" ]; then
			NEWCERT="YES"
			if [ -s "$LETSENCRYPT_DIR/hiawatha.pem" ]; then
				NEWCERT="$(diff -q "$LETSENCRYPT_DIR/hiawatha.pem.new" "$LETSENCRYPT_DIR/hiawatha.pem" 2>/dev/null)"
			fi
			if [ "$NEWCERT" ]; then
				mv -f "$LETSENCRYPT_DIR/hiawatha.pem.new" "$LETSENCRYPT_DIR/hiawatha.pem"
				if [ "$LEDOMAIN" = "$DOMAIN" ]; then
					# Replace locally issued certificate for DOMAIN with letsencrypt certificate
					printf "Replacing local certificate in %s ...\n" "$CERTDIR" | tee -a "$LOGFILE"
					ln -sf "$LETSENCRYPT_DIR/hiawatha.pem" "$CERTDIR"/hiawatha.pem
					ln -sf hiawatha.pem "$CERTDIR"/pure-ftpd.pem
					ln -sf "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" "$CERTDIR"/fullchain.crt
					ln -sf "/etc/letsencrypt/live/$DOMAIN/cert.pem" "$CERTDIR/$CERTNAME".crt
					ln -sf "/etc/letsencrypt/live/$DOMAIN/privkey.pem" "$CERTDIR/$CERTNAME".key
				fi
				# Force service restart
				RENEWED=1
			fi
		fi
		rm -f "$LETSENCRYPT_DIR/hiawatha.pem.new"
	done
fi

#
# Restart services to apply new certificates
#
if [ $RENEWED -eq 1 ]; then
	for SRV in hiawatha dovecot pureftpd; do
		if [ -e "/etc/service/$SRV" ] && sv status $SRV | grep -q '^run'; then
			printf "Restarting %s: " "$SRV" | tee -a "$LOGFILE"
			sv restart $SRV | tee -a "$LOGFILE"
		fi
	done
fi

