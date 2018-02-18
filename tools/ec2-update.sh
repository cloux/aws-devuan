#!/bin/sh
#
# Install/Update EC2 tools in the AWS instance

# We need to be root
if [ $CHECK -eq 0 -a $(id -u) -ne 0 ]; then
	echo "Need to be root!" 1>&2
	exit
fi

#
# ec2-metadata
#
if [ -x /usr/local/bin/ec2-metadata ]; then
	echo -n "Update "
else
	echo -n "Install "
fi
echo -n "ec2-metadata tool ... "
cd /tmp
rm -f ec2-metadata
wget -q http://s3.amazonaws.com/ec2metadata/ec2-metadata
if [ $? -ne 0 -o ! -f ec2-metadata ]; then
	echo "download FAILED"
else
	if [ $(head -n 1 ec2-metadata | grep -c '#!') -ne 1 ]; then
		echo "FAILED: file is not a shell script"
		rm ec2-metadata
	else
		chmod 755 ec2-metadata
		mv -f ec2-metadata /usr/local/bin/
		echo "OK"
	fi
fi

#
# amazon-ssm-agent
#
SSM_BINDIR=/usr/bin
[ -d $SSM_BINDIR ] || exit
if [ -x $SSM_BINDIR/amazon-ssm-agent ]; then
	echo -n "Update "
else
	echo -n "Install "
fi
echo "amazon-ssm-agent ..."

if [ ! -x "$(which go)" ]; then
	echo "ERROR: Golang not found. Install 'golang' first."
	exit
fi
if [ ! -x "$(which git)" ]; then
	echo "ERROR: git not found. Install 'git' first."
	exit
fi

# stop service if running
if [ "$(pgrep runsvdir)" -a -d /etc/service/amazon-ssm-agent ]; then
	echo "Stop service ..."
	sv stop amazon-ssm-agent
fi

SSM_SRCDIR=/usr/lib/go-1.7/src/github.com/aws
[ -d $SSM_SRCDIR ] || mkdir -p $SSM_SRCDIR
cd $SSM_SRCDIR
if [ -d amazon-ssm-agent ]; then
	# update: git pull
	cd amazon-ssm-agent
	git pull
else
	# install: git clone
	#git clone https://github.com/aws/amazon-ssm-agent
	git clone https://github.com/cloux/amazon-ssm-agent
	cd amazon-ssm-agent
	[ $? -eq 0 ] || exit
fi
# link the codebase to /usr/src, to make it more "visible"
ln -sf $SSM_SRCDIR/amazon-ssm-agent /usr/src/

echo "Get additional tools ..." 
make get-tools
echo "Build ..."
make build-linux
[ $? -eq 0 ] || exit

# install compiled ssm-agent
echo "Installing compiled amazon-ssm-agent into the system..."
cp -vf bin/linux_amd64/* $SSM_BINDIR/
[ -d /etc/amazon/ssm ] || mkdir -p /etc/amazon/ssm
cp -vf bin/amazon-ssm-agent.json.template /etc/amazon/ssm/
cp -vn bin/amazon-ssm-agent.json.template /etc/amazon/ssm/amazon-ssm-agent.json
cp -vn bin/seelog_unix.xml /etc/amazon/ssm/seelog.xml

 # cleanup (240 MB -> 175 MB)
echo "Cleanup ..."
make clean
#rm -rf "$SSM_SRCDIR"

# start service after update
if [ "$(pgrep runsvdir)" -a -d /etc/service/amazon-ssm-agent ]; then
	echo "Start service ..."
	sv start amazon-ssm-agent
fi

echo "DONE"
