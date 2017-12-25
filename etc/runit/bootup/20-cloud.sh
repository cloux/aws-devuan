# *-*- Shell Script -*-*
#
# AWS EC2 cloud-init
# see /etc/init.d/cloud-init

# Exit if the package is not installed
[ -x "/usr/bin/cloud-init" ] || return 0

msg "AWS EC2 Cloud initialization..."

# clean up
rm -f /var/log/cloud-init.log /var/log/cloud-init-output.log
[ -d /var/lib/cloud/instance ] && rm -rf /var/lib/cloud/instance
# load config
[ -r /etc/default/cloud-init ] && . /etc/default/cloud-init
# init
/usr/bin/cloud-init init
/usr/bin/cloud-init init --local
/usr/bin/cloud-init modules --mode config
/usr/bin/cloud-init modules --mode final
