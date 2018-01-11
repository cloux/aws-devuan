# *-*- Shell Script -*-*
#
# Enable/disable additional services in stage 2

msg "Service activation:"

# irqbalance - distribute hardware interrupts across processors
# Enable this service only in multi-CPU environment.
# It would not run on a single-CPU anyway.
if [ -d /etc/sv/irqbalance ]; then
	#CPU_COUNT=$(grep -c '^processor' /proc/cpuinfo)
	CPU_COUNT=$(nproc --all 2>/dev/null)
	echo -n "   CPUs detected: $CPU_COUNT, "
	if [ $CPU_COUNT -gt 1 ]; then
		echo -n "activate irqbalance ..."
		RET=$(/etc/runit/svactivate irqbalance >/dev/null 2>/dev/null)
	else
		echo -n "deactivate irqbalance ..."
		RET=$(/etc/runit/svdeactivate irqbalance >/dev/null 2>/dev/null)
	fi
	if [ $? -eq 0 ]; then
		msg_ok
	else
		echo " $RET"
	fi
fi
