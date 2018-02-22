# *-*- Shell Script -*-*
# from VOID Linux (https://www.voidlinux.eu)

[ -n "$VIRTUALIZATION" ] && return 0

if [ -x /sbin/udevd ] || [ -x /bin/udevd ]; then
	_udevd=udevd
elif [ -x /usr/lib/systemd/systemd-udevd ]; then
	_udevd=/usr/lib/systemd/systemd-udevd
else
	msg_warn "cannot find udevd!"
fi

if [ -n "${_udevd}" ]; then
	msg "Starting udev and waiting for devices to settle ..."
	${_udevd} --daemon
	udevadm trigger --action=add --type=subsystems
	udevadm trigger --action=add --type=devices
	# NOTE: Settle might wait very long (>30sec) for crng,
	#       this random number generator initialization takes ages.
	#       See: dmesg | grep 'random: crng init done'
	udevadm settle  --timeout=1
fi
