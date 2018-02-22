# *-*- Shell Script -*-*
# from VOID linux (https://www.voidlinux.eu)
exec 2>&1

[ -n "$VIRTUALIZATION" ] && return 0

msg "Loading kernel modules:"
# modules loading, taken from /etc/init.d/kmod

# Silently return if the kernel does not support modules.
[ -f /proc/modules ] || return 0
[ -x /sbin/modprobe  ] || return 0

# get all module config files
modules_files() {
	local modules_load_dirs='/etc/modules-load.d /run/modules-load.d /usr/local/lib/modules-load.d /usr/lib/modules-load.d /lib/modules-load.d'
	local processed=' '
	local add_etc_modules=true

	for dir in $modules_load_dirs; do
		[ -d "$dir" ] || continue
		for file in $(run-parts --list --regex='\.conf$' "$dir" 2> /dev/null || true); do
			local base=${file##*/}
			if echo -n "$processed" | grep -qF " $base "; then
				continue
			fi
			if [ "$add_etc_modules" ] && [ -L "$file" ] && [ "$(readlink -f "$file")" = /etc/modules ]; then
				add_etc_modules=
			fi
			processed="$processed$base "
			echo "$file"
		done
	done

	if [ "$add_etc_modules" ]; then
		printf "/etc/modules\n"
	fi
}

files=$(modules_files)
if [ "$files" ]; then
	grep -h '^[^#]' $files |
	while read -r module args; do
		[ "$module" ] || continue
		msg "+ modprobe '$module'"
		modprobe "$module" "$args"
	done
fi

