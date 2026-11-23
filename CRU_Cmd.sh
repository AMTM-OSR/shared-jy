#!/bin/sh
#---------------------------------------------------#
# MODIFIED script to handle 'stuck' nvram commands.
#---------------------------------------------------#
# Last Modified: 2026-Oct-25 [Martinski W.]
#---------------------------------------------------#

readonly SCRIPT_VERSION="v0.9.5"
readonly SCRIPT_VERSTAG="26102523"

# To handle and prevent stuck 'nvram' commands when running cru #
readonly sharedLibsPATH="/jffs/addons/shared-libs"
readonly NVRAM_CmdHandler="${sharedLibsPATH}/NVRAM_CmdHandler.lib.sh"

if [ -s "$NVRAM_CmdHandler" ]
then . "$NVRAM_CmdHandler"
else NVRAM_Cmd="$(which nvram | head -n1)"
fi

D="/var/spool/cron/crontabs"
U="$D/cron.update"
F="$D/$($NVRAM_Cmd get http_username)"
N="$F.new"
L="/var/lock/cron.lock"

if [ $# -gt 1 ] && [ "$1" = "a" -o "$1" = "d" ]
then
	{
		flock -x 278
		ID="$2"
		grep -v "#$ID#\$" "$F" >"$N" 2>/dev/null
		if [ "$1" = "a" ]
		then
			shift
			shift
			echo "$* #$ID#" >>"$N"
		fi
		mv "$N" "$F"
		echo "$($NVRAM_Cmd get http_username)" >>"$U"
	} 278>$L

	exit 0
fi

if [ $# -gt 0 ] && [ "$1" = "l" ]
then
	cat "$F" 2>/dev/null
	exit 0
fi

cat <<END

Version: $SCRIPT_VERSION [$SCRIPT_VERSTAG]
Cron Utility
add:    cru a <unique id> <"min hour day month week command">
delete: cru d <unique id>
list:   cru l

END
exit 0
