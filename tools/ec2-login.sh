#!/bin/bash
# AWS EC2 - SSH login, using defaults
#
# Usage: 
# ec2-login.sh
#   Login using internal defaults
# ec2-login.sh 12.34.56.78
#   Login as default user to given IP
# ec2-login.sh admin@ec2-12-34-56-78.compute-1.amazonaws.com
#   Login as 'admin' to an instance
# 

SSH_KEYFILE=path-to-your-key-file.pem

# if not provided as parameter, login to this IP or URI:
DEFAULT_INSTANCE_ADDR=

# if not provided as parameter, login as this user:
SSH_USER=admin
#SSH_USER=ec2-user

if [ ! -e "$SSH_KEYFILE" ]; then
	echo -e "Keyfile '$SSH_KEYFILE' not found.\nSet the SSH_KEYFILE variable first."
	exit
fi

if [[ $1 = *@* ]]; then
	ssh -i "$SSH_KEYFILE" "$1"
elif [ "$1" ]; then
	ssh -i "$SSH_KEYFILE" $SSH_USER@$1
elif [ "$DEFAULT_INSTANCE_ADDR" ]; then
	ssh -i "$SSH_KEYFILE" ${SSH_USER}@${DEFAULT_INSTANCE_ADDR}
else
	echo "Enter parameter: IPADDR, or USER@ADDR"
fi
