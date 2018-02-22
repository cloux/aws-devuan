# *-*- Shell Script -*-*
# from VOID Linux (https://www.voidlinux.eu)

[ -n "$VIRTUALIZATION" ] && return 0

if [ -x /sbin/dmraid ] || [ -x /bin/dmraid ]; then
	msg "Activating dmraid devices ..."
	dmraid -i -ay 2>&1
fi

if [ -x /bin/btrfs ]; then
	msg "Activating btrfs devices ..."
	btrfs device scan 2>&1
fi

if [ -x /sbin/vgchange ] || [ -x /bin/vgchange ]; then
	msg "Activating LVM devices ..."
	vgchange --sysinit -a y 2>&1
fi

if [ -e /etc/zfs/zpool.cache ] && [ -x /usr/bin/zfs ]; then
	msg "Activating ZFS devices ..."
	zpool import -c /etc/zfs/zpool.cache -N -a

	msg "Mounting ZFS file systems ..."
	zfs mount -a

	msg "Sharing ZFS file systems ..."
	zfs share -a

	# NOTE(dh): ZFS has ZVOLs, block devices on top of storage pools.
	# In theory, it would be possible to use these as devices in
	# dmraid, btrfs, LVM and so on. In practice it's unlikely that
	# anybody is doing that, so we aren't supporting it for now.
fi

# Filesystem check
[ -f /fastboot -o "$(grep fastboot /proc/cmdline)" ] && FASTBOOT=1
[ -f /forcefsck -o "$(grep forcefsck /proc/cmdline)" ] && FORCEFSCK="-f"
MOUNT_RW=$(mount | grep -m 1 -c ' / .*[(\s,]rw[\s,)]')
if [ -z "$FASTBOOT" ]; then
	if [ "$FORCEFSCK" ]; then
		if [ $MOUNT_RW -eq 1 ]; then
			msg "Remounting root read-only ..."
			mount -o remount,ro / 2>&1
			MOUNT_RW=0
		fi
		msg "Force checking rootfs:"
		fsck -T / -- -p $FORCEFSCK
	else
		# repair the filesystem only if damaged.
		# this should allow faster boot if filesystem is OK
		msg "Checking rootfs:"
		fsck -T / -- -n
		if [ $? -ne 0 ]; then
			if [ $MOUNT_RW -eq 1 ]; then
				msg "Remounting root read-only ..."
				mount -o remount,ro / 2>&1
				MOUNT_RW=0
			fi
			msg "Repairing damaged rootfs:"
			fsck -T / -- -p $FORCEFSCK
		fi
	fi
	msg "Checking non-root filesystems:"
	fsck -ART -t noopts=_netdev -- -p $FORCEFSCK
fi
if [ $MOUNT_RW -eq 0 ]; then
	msg "Mounting rootfs read-write ..."
	mount -o remount,rw / 2>&1
fi

# growpart in cloud-init needs rootfs linked to /dev/root
if [ ! -e /dev/root ]; then
	ROOTDEVICE="$(findmnt --noheadings --output SOURCE /)"
	msg "Link $ROOTDEVICE to /dev/root ..."
	ln -s "$ROOTDEVICE" /dev/root
fi

msg "Mounting all non-network filesystems ..."
mount -a -t "nosysfs,nonfs,nonfs4,nosmbfs,nocifs" -O no_netdev


