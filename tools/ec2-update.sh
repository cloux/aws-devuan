#!/bin/sh
#
# Install/Update EC2 tools in the AWS instance

# We need to be root
if [ $(id -u) -ne 0 ]; then
	printf "Need to be root!\n" 1>&2
	exit
fi

#
# ec2-metadata
#
if [ -x /usr/local/bin/ec2-metadata ]; then
	printf "Update "
else
	printf "Install "
fi
printf "ec2-metadata tool ... "
cd /tmp || exit
rm -f ec2-metadata
wget -q http://s3.amazonaws.com/ec2metadata/ec2-metadata
if [ $? -ne 0 ] || [ ! -f ec2-metadata ]; then
	printf "download FAILED\n"
else
	if [ $(head -n 1 ec2-metadata | grep -c '#!') -ne 1 ]; then
		printf "FAILED: file is not a shell script\n"
		rm ec2-metadata
	else
		chmod 755 ec2-metadata
		mv -f ec2-metadata /usr/local/bin/
		printf "OK\n"
	fi
fi

#
# amazon-ssm-agent
#
SSM_BINDIR=/usr/bin
[ -d $SSM_BINDIR ] || exit
if [ -x $SSM_BINDIR/amazon-ssm-agent ]; then
	printf "Update "
else
	printf "Install "
fi
printf "amazon-ssm-agent ...\n"

if [ -z "$(command -v go)" ]; then
	printf "ERROR: Golang not found. Install 'golang' first.\n"
	exit
fi
if [ -z "$(command -v git)" ]; then
	printf "ERROR: git not found. Install 'git' first.\n"
	exit
fi

SSM_SRCDIR=/usr/lib/go-1.7/src/github.com/aws
[ -d "$SSM_SRCDIR" ] || mkdir -p "$SSM_SRCDIR"
cd "$SSM_SRCDIR" || exit
if [ -d amazon-ssm-agent ]; then
	# update: git pull
	cd amazon-ssm-agent || exit
	git pull
else
	# clone repository
	# NOTE: as of 2018-02-26, the official aws repository is buggy and won't compile.
	#       pull from cloux until fixed
	#git clone https://github.com/aws/amazon-ssm-agent
	git clone https://github.com/cloux/amazon-ssm-agent
	cd amazon-ssm-agent || exit
fi
# link the codebase to /usr/src, to make it more "visible"
ln -sf "$SSM_SRCDIR/amazon-ssm-agent" /usr/src/

printf "Get additional tools ...\n"
make get-tools
printf "Build ...\n"
make build-linux
[ $? -eq 0 ] || exit

# stop service if running
if [ "$(pgrep runsvdir)" ] && [ -d /etc/service/amazon-ssm-agent ]; then
	printf "Stop service ...\n"
	sv stop amazon-ssm-agent
fi

# install compiled ssm-agent
printf "Installing compiled amazon-ssm-agent into the system ...\n"
cp -vf bin/linux_amd64/* $SSM_BINDIR/
[ -d /etc/amazon/ssm ] || mkdir -p /etc/amazon/ssm
cp -vf bin/amazon-ssm-agent.json.template /etc/amazon/ssm/
cp -vn bin/amazon-ssm-agent.json.template /etc/amazon/ssm/amazon-ssm-agent.json
cp -vn bin/seelog_unix.xml /etc/amazon/ssm/seelog.xml
# stop flooding the /dev/console (see bootlogd: /var/log/boot.log)
sed -i 's/.*<console.*\/>.*//' /etc/amazon/ssm/seelog.xml

# start service after update
if [ "$(pgrep runsvdir)" ] && [ -d /etc/service/amazon-ssm-agent ]; then
	printf "Start service ...\n"
	sv start amazon-ssm-agent
fi

# cleanup (240 MB -> 175 MB)
printf "Cleanup ...\n"
make clean
#rm -rf "$SSM_SRCDIR"

printf "DONE\n"
