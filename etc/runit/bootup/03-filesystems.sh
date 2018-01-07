# *-*- Shell Script -*-*
# from VOID Linux (https://www.voidlinux.eu)

[ -n "$VIRTUALIZATION" ] && return 0

if [ -x /sbin/dmraid -o -x /bin/dmraid ]; then
	msg "Activating dmraid devices..."
	dmraid -i -ay 2>&1
fi

if [ -x /bin/btrfs ]; then
	msg "Activating btrfs devices..."
	btrfs device scan 2>&1
fi

if [ -x /sbin/vgchange -o -x /bin/vgchange ]; then
	msg "Activating LVM devices..."
	vgchange --sysinit -a y 2>&1
fi

if [ -e /etc/zfs/zpool.cache -a -x /usr/bin/zfs ]; then
	msg "Activating ZFS devices..."
	zpool import -c /etc/zfs/zpool.cache -N -a

	msg "Mounting ZFS file systems..."
	zfs mount -a

	msg "Sharing ZFS file systems..."
	zfs share -a

	# NOTE(dh): ZFS has ZVOLs, block devices on top of storage pools.
	# In theory, it would be possible to use these as devices in
	# dmraid, btrfs, LVM and so on. In practice it's unlikely that
	# anybody is doing that, so we aren't supporting it for now.
fi

[ -f /fastboot -o "$(grep fastboot /proc/cmdline)" ] && FASTBOOT=1
[ -f /forcefsck -o "$(grep forcefsck /proc/cmdline)" ] && FORCEFSCK="-f"

if [ -z "$FASTBOOT" ]; then
	if [ $(mount | grep -c ' / ') -gt 0 ]; then
		# only remount / if it needs to be repaired
		fsck -T / -- -n 2>/dev/null >/dev/null
		if [ $? -ne 0 -o "$FORCEFSCK" ]; then
			msg "Remounting rootfs read-only..."
			mount -o remount,ro / 2>&1
			msg "Checking rootfs:"
			fsck -T / -- -p $FORCEFSCK
		fi
	fi
	msg "Checking filesystems:"
	fsck -ART -t noopts=_netdev -- -p $FORCEFSCK
fi
if [ $(mount | grep ' / ' | grep -c '[(\s,]rw[\s,)]') -eq 0 ]; then
	msg "Mounting rootfs read-write..."
	mount -o remount,rw / 2>&1
fi

msg "Mounting all non-network filesystems..."
mount -a -t "nosysfs,nonfs,nonfs4,nosmbfs,nocifs" -O no_netdev
