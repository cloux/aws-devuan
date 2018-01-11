# *-*- Shell Script -*-*
# from VOID Linux (https://www.voidlinux.eu)

msg "Cleanup..."

install -m0664 -o root -g utmp /dev/null /run/utmp
if [ ! -e /var/log/wtmp ]; then
	install -m0664 -o root -g utmp /dev/null /var/log/wtmp
fi
if [ ! -e /var/log/btmp ]; then
	install -m0600 -o root -g utmp /dev/null /var/log/btmp
fi
#install -dm1777 /tmp/.X11-unix /tmp/.ICE-unix
rm -f /etc/nologin /forcefsck /forcequotacheck /fastboot

# runit shutdown/reboot markers
install --mode=0 /dev/null /run/runit.stopit
install --mode=755 /dev/null /run/runit.reboot
# set soft reboot as the default operation
#install --mode=755 /dev/null /run/runit.kexecreboot
