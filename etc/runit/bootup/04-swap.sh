# *-*- Shell Script -*-*
# from VOID Linux (https://www.voidlinux.org)

[ -n "$VIRTUALIZATION" ] && return 0

msg "Initializing swap ..."
swapon -a 2>&1

