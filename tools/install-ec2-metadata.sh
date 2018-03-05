#!/bin/sh
#
# Install/Update AWS instance: ec2-metadata 

# We need to be root
if [ $(id -u) -ne 0 ]; then
	printf "Need to be root!\n" 1>&2
	exit
fi

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
		printf "DONE\n"
	fi
fi
