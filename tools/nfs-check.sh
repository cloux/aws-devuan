#!/bin/sh
#
# check all NFS mounts for stale condition,
# exit code is the number of stale NFS mounts
# (cloux@rote.ch)

# how long to wait for NFS to respond before considered stale
NFS_TIMEOUT=20

printf "nfs-check started: %s\n" "$(date --iso-8601=ns)"

RET=0
for NFS_MOUNT in $(grep ' nfs' /proc/mounts | cut -d ' ' -f 2); do
	timeout --kill-after=1 $NFS_TIMEOUT ls -1 "$NFS_MOUNT" >/dev/null
	if [ $? -eq 0 ]; then
		printf "AVAILABLE: '%s'\n" "$NFS_MOUNT"
	else
		printf "STALE: '%s'\n" "$NFS_MOUNT"
		RET=$(($RET+1))
	fi
done
exit $RET

printf "nfs-check finished: %s\n" "$(date --iso-8601=ns)"
