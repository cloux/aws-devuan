# *-*- Shell Script -*-*
# Print additional system info to the console
#
# NOTE: this is run in series during boot. Slow
# commands (e.g. network checks) will cost you boot time!
#
# (cloux@rote.ch)

msg "Time: $(date --iso-8601=seconds)"
msg "CPU: $(grep -i 'model name' /proc/cpuinfo | head -n 1 | sed 's/[^:]*:\s*//') ($(nproc --all) Cores)"
msg "RAM: $(grep MemTotal /proc/meminfo | sed 's/[^:]*:\s*//')"

LOCAL_IP="$(hostname -I 2>/dev/null)"
if [ "$LOCAL_IP" ]; then
	msg "LAN IP: $LOCAL_IP"
#	PUBLIC_IP="$(/usr/local/bin/public-ip 2>/dev/null)"
#	[ "$PUBLIC_IP" ] && msg "WAN IP: $PUBLIC_IP"
fi

