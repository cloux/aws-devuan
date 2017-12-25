# *-*- Shell Script -*-*
# from VOID Linux (https://www.voidlinux.eu)

[ -n "$VIRTUALIZATION" ] && return 0

msg "Remounting rootfs read-only..."
#mount -o remount,ro / || emergency_shell
mount -o remount,ro / || return 0

if [ -x /sbin/dmraid -o -x /bin/dmraid ]; then
    msg "Activating dmraid devices..."
    dmraid -i -ay
fi

if [ -x /bin/btrfs ]; then
    msg "Activating btrfs devices..."
    #btrfs device scan || emergency_shell
    btrfs device scan 2>&1
fi

if [ -x /sbin/vgchange -o -x /bin/vgchange ]; then
    msg "Activating LVM devices..."
    #vgchange --sysinit -a y || emergency_shell
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

[ -f /fastboot ] && FASTBOOT=1
[ -f /forcefsck ] && FORCEFSCK="-f"
for arg in $(cat /proc/cmdline); do
    case $arg in
        fastboot) FASTBOOT=1;;
        forcefsck) FORCEFSCK="-f";;
    esac
done

if [ -z "$FASTBOOT" ]; then
    msg "Checking filesystems:"
    fsck -A -T -a -t noopts=_netdev $FORCEFSCK
#    if [ $? -gt 1 ]; then
#        emergency_shell
#    fi
fi

msg "Mounting rootfs read-write..."
#mount -o remount,rw / || emergency_shell
mount -o remount,rw /

msg "Mounting all non-network filesystems..."
#mount -a -t "nosysfs,nonfs,nonfs4,nosmbfs,nocifs" -O no_netdev || emergency_shell
mount -a -t "nosysfs,nonfs,nonfs4,nosmbfs,nocifs" -O no_netdev

