# *-*- Shell Script -*-*
#
# Tasks started in parallel
# (cloux@rote.ch)

# AWS EC2 cloud-init, see /etc/init.d/cloud-init
if [ -x "/usr/bin/cloud-init" ]; then
	msg "Run cloud-init in parallel, see /var/log/cloud-init.log"
	nohup /etc/runit/bootup/20-cloud >/dev/null &
fi
