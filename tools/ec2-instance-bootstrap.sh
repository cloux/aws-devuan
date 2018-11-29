#!/bin/sh
#
# AWS EC2 instance cleanup for redistribution
#
# WARNING: BIOHAZARD!!!
# The instance will become unaccessible after this!
# Run only before creating AMI for distribution.
#

# Make sure that I'm root
if [ $(id -u) -ne 0 ]; then
	printf "Need to be root!\n"
	exit 1
fi

if [ "$1" != "force" ]; then
	printf "WARNING:\n"
	printf "After shutdown, this instance will not be accessible anymore!\n"
	printf "Instance must be exported as AMI and terminated afterwards.\n"
	printf "Do not proceed if not absolutely sure that an AMI\n"
	printf "exported from this instance will start properly.\n"
	printf "This will remove all history, logs, and SSH keys!!!\n\n"
	printf "To proceed, use the 'force' parameter.\n"
	exit
fi

# delete package cache
printf "Delete apt cache ..."
aptitude --quiet=2 clean >/dev/null
printf "OK\n"

# Delete all SSH keys. New will be generated by cloud-init when spawning
# a new instance from AMI.
printf  "Delete SSH keys ..."
rm -f /etc/ssh/ssh_host_* 2>/dev/null
rm -f /root/.ssh/*
find /home -type f -iname authorized_keys -delete
printf "OK\n"

# stop log-creating services before deleting logfiles
printf "Stop services:\n"
sv stop $(find /etc/service/ -type l ! -iname 'ssh' ! -iname '*getty*')

printf "Delete logfiles ..."
rm -f /var/log/boot.log* /var/log/cloud-init*.log* /var/log/dmesg.log* \
 /var/log/apt/history.log* /var/log/apt/term.log* /var/log/hiawatha/* \
 /var/log/pure*.log /var/log/autorun*.log* /var/log/dpkg.log* /var/log/lastlog \
 /var/log/wtmp* /var/log/btmp* /var/backups/* \
 /var/log/amazon/ssm/*.log /var/log/aptitude 2>/dev/null
find /var/log -type f \( -iname current -o -iname '@*' -o -iname '*.gz' -o -iname '*.xz' \) -delete
touch /var/log/lastlog
printf "OK\n"

printf "Delete /var/lib/cloud/instances ..."
rm -rf /var/lib/cloud/instances/*
printf "OK\n"

printf "Delete /var/lib/amazon/ssm ..."
rm -rf /var/lib/amazon/ssm/*
printf "OK\n"

printf "Delete history ..."
find /home -type f -iname history -delete
find /home -type f -iname dead.letter -delete
find /root -type f -iname dead.letter -delete
find /home -maxdepth 2 -type f -iname .bash_history -delete
printf "OK\n"

printf "DONE. The instance can be shutdown and exported as AMI.\n"
exit
