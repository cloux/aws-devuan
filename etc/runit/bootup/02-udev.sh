# *-*- Shell Script -*-*
# from VOID Linux (https://www.voidlinux.eu)

[ -n "$VIRTUALIZATION" ] && return 0

if [ -x /sbin/udevd -o -x /bin/udevd ]; then
    _udevd=udevd
elif [ -x /usr/lib/systemd/systemd-udevd ]; then
    _udevd=/usr/lib/systemd/systemd-udevd
else
    msg_warn "cannot find udevd!"
fi

if [ -n "${_udevd}" ]; then
    msg "Starting udev and waiting for devices to settle..."
    ${_udevd} --daemon
    udevadm trigger --action=add --type=subsystems
    udevadm trigger --action=add --type=devices
    # NOTE: On AWS EC2, 'settle' waits until timeout (the default is 2 min!)
    #       However, this seems to happen only with udev, not with eudev.
    udevadm settle  --timeout=5
fi
