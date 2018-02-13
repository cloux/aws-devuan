#!/bin/sh
#
# Install/Update EC2 tools in the AWS instance

if [ -x /usr/local/bin/ec2-metadata ]; then
	echo -n "Update ec2-metadata tool ... "
else
	echo -n "Install ec2-metadata tool ... "
fi
cd /tmp
rm -f ec2-metadata
wget -q http://s3.amazonaws.com/ec2metadata/ec2-metadata
if [ $? -ne 0 -o ! -f ec2-metadata ]; then
	echo "download FAILED"
	exit 1
fi
if [ $(head -n 1 ec2-metadata | grep -c '#!') -ne 1 ]; then
	echo "FAILED: file is not a shell script"
	rm ec2-metadata
	exit 1
fi
chmod 755 ec2-metadata
mv -f ec2-metadata /usr/local/bin/
echo "OK"
