# *-*- Shell Script -*-*
#
# Autorun
# Run scripts in /etc/runit/autorun in parallel at the end of the bootup stage.
# These should perform tasks only needed once after boot,
# should not daemonize and will not be supervised.
#
# (cloux@rote.ch)

msg "Starting autorun scripts in parallel..."

OUTPUT=/dev/null
for f in /etc/runit/autorun/*; do
	[ -x "$f" ] || continue
	msg "  '$f'"
	[ -d /var/log ] && OUTPUT=/var/log/autorun-${f##*/}.log
	nohup "$f" >"$OUTPUT" 2>&1 &
done
