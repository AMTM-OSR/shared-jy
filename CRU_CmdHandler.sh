#!/bin/sh
###################################################################
# CRU_CmdHandler.sh
#
# Mounts a modified version of the built-in 'cru' shell script
# [/jffs/addons/shared-libs/CRU_Cmd.sh]
# This script handles and prevents the stuck 'nvram' commands.
#
# Also, a statement is added to the 'init-start' hook script to
# mount the modified script automatically during reboot.
#----------------------------------------------------------------
# Original Author: Martinski W.
# Creation Date: 2026-Oct-24
# Last Modified: 2026-Nov-22 [Martinski W.]
###################################################################
set -u

readonly SCRIPT_VERSION="v0.9.5"
readonly SCRIPT_VERSTAG="26112223"

readonly scriptFName="${0##*/}"
readonly scriptTName="${scriptFName%.*}"

doDebugLog=true
readonly theLOGpath="/tmp/var/tmp"
readonly sharedLibsPATH="/jffs/addons/shared-libs"
readonly initStartScript="/jffs/scripts/init-start"

readonly CLRct="\e[0m"
readonly BOLDct="\e[1m"
readonly REDct="\e[1;31m"
readonly GRNct="\e[1;32m"
readonly YLWct="\e[1;33m"
readonly MGNTct="\e[1;35m"
readonly CYANct="\e[1;36m"

readonly logMaxSize=16384
readonly logTagStr="${scriptTName}_[$$]"
readonly logPrioNum=4   ##WARNING##
readonly logTagEXIT="EXIT_$logTagStr"
readonly logTagSTART="START_$logTagStr"
readonly theDEBUGLog="${theLOGpath}/${scriptTName}.LOG"

readonly versionStrInfo="${GRNct}${SCRIPT_VERSION}${CLRct} [${GRNct}${SCRIPT_VERSTAG}${CLRct}]"

# Give higher priority to built-in binaries #
export PATH="/bin:/usr/bin:/sbin:/usr/sbin:$PATH"

if [ -t 0 ] && ! tty | grep -qwi 'NOT'
then isInteractive=true
else isInteractive=false
fi

readonly ORIG_CRU_CMD="$(which cru | head -n1)"
readonly MODF_CRU_CMD="${sharedLibsPATH}/CRU_Cmd.sh"
readonly SCRIPT_FPATH="${sharedLibsPATH}/$scriptFName"
readonly CRU_CMD_CONF="${sharedLibsPATH}/${scriptTName}.conf"
readonly CRU_CMD_RegExp="[[:blank:]]+${ORIG_CRU_CMD}[[:blank:]]+"

##--------------------------------------------------##
_ShowUsage_()
{
    ! "$isInteractive" && return 0
    cat <<EOF | xargs -0 echo -e
-------------------------------------------------------------------
Version: $versionStrInfo
Author: Martinski W.

The ${GRNct}${scriptFName}${CLRct} script is a utility used to mount and
unmount a modified version of the F/W built-in 'cru' script:

   ${MGNTct}${MODF_CRU_CMD}${CLRct}

This modified version handles and prevents stuck 'nvram' commands 
that can occur when running the original ${YLWct}cru${CLRct} command.

USAGE:

To enable mounting a modified version of the built-in 'cru' script.
The initial default configuration is ENABLED. This setting does NOT
automatically mount the modified version of the 'cru' script.

   ${GRNct}./${scriptFName}${CLRct} ${CYANct}-enable${CLRct}


To disable mounting a modified version of the built-in 'cru' script.
This setting does NOT automatically unmount the modified version of
the 'cru' script.

   ${GRNct}./${scriptFName}${CLRct} ${CYANct}-disable${CLRct}


To mount a modified version of the built-in 'cru' script. It also
adds a statement to the 'init-start' script to automatically mount
the modified 'cru' script during every reboot. 

   ${GRNct}./${scriptFName}${CLRct} ${CYANct}-mount${CLRct}


To remove a mount of the modified version of the built-in 'cru' 
script, leaving behind the original 'cru' command. It removes
the statement that was added to the 'init-start' script.

   ${GRNct}./${scriptFName}${CLRct} ${CYANct}-unmount${CLRct}


Reports whether the modified version of the built-in 'cru' script
is mounted or unmounted.

   ${GRNct}./${scriptFName}${CLRct} ${CYANct}-status${CLRct}


Reports whether mounting the modified version of the built-in 
'cru' script is enabled or disabled.

   ${GRNct}./${scriptFName}${CLRct} ${CYANct}-checkEnable${CLRct}

-------------------------------------------------------------------
EOF
}

##--------------------------------------------------##
_CheckLogFileSize_()
{
   if [ ! -s "$theDEBUGLog" ]
   then return 1
   fi
   local fileSize
   fileSize="$(ls -1l "$theDEBUGLog" | awk -F' ' '{print $3}')"
   if [ "$fileSize" -gt "$logMaxSize" ]
   then
       cp -fp "$theDEBUGLog" "${theDEBUGLog}.BKUP"
       printf '' > "$theDEBUGLog"
       "$isInteractive" && \
       printf "\nReset $theDEBUGLog [$fileSize > $logMaxSize]\n"
   fi
}

##--------------------------------------------------##
_ShowDebugMsg_()
{
   if ! "$isInteractive" ; then return 1 ; fi
   if [ $# -eq 0 ]
   then echo
   elif [ $# -eq 1 ]
   then echo "$1"
   else echo "${1}: $2"
   fi
}

##--------------------------------------------------##
_DoLog_()
{
   if [ $# -eq 0 ] && "$doDebugLog"
   then
      _ShowDebugMsg_
      echo >> "$theDEBUGLog"
      return 0
   fi
   if [ $# -eq 0 ] || [ -z "$1" ]
   then return 1
   fi
   if [ "$1" != "$logTagSTART" ] && [ "$1" != "$logTagEXIT" ]
   then
       LOGmsg="$1"
       logger -t "$logTagStr" -p "$logPrioNum" "$1"
   else
       if [ "$1" = "$logTagSTART" ]
       then
           LOGmsg="[$(date +"%Y-%m-%d %H:%M:%S")] $1 ARGs=[$2]"
       else
           LOGmsg="[$(date +"%Y-%m-%d %H:%M:%S")] $1"
       fi
   fi
   if "$doDebugLog"
   then
       _ShowDebugMsg_ "$LOGmsg"
       echo "$LOGmsg" >> "$theDEBUGLog"
       [ "$1" = "$logTagEXIT" ] && echo >> "$theDEBUGLog"
   fi
}

_DoExit_() { _DoLog_ "$logTagEXIT" ; exit "$1" ; }

##--------------------------------------------------##
_DOStoUNIX_()
{
    if [ $# -eq 0 ] || [ -z "$1" ] || [ ! -s "$1" ]
    then return 1 ; fi
    if grep -q "$(printf '\r\n')" "$1" 2>/dev/null
    then dos2unix "$1" ; fi
}

##--------------------------------------------------##
_DoInitStart_()
{
    local theScriptNameTag="#${scriptTName}#"

    case "$1" in
        create)
            if [ -s "$initStartScript" ]
            then
               theLineTagCount="$(grep -c "${theScriptNameTag}$" "$initStartScript")"
               theLineCmdCount="$(grep -cx '\[ -x '"$SCRIPT_FPATH"' \] && '"$SCRIPT_FPATH"' -mount &  '"$theScriptNameTag" "$initStartScript")"

               if [ "$theLineTagCount" -gt 1 ] || { [ "$theLineCmdCount" -eq 0 ] && [ "$theLineTagCount" -gt 0 ] ; }
               then
                    sed -i "/${theScriptNameTag}/d" "$initStartScript"
               fi

               theLineCmdCount="$(grep -cx '\[ -x '"$SCRIPT_FPATH"' \] && '"$SCRIPT_FPATH"' -mount &  '"$theScriptNameTag" "$initStartScript")"
               if [ "$theLineCmdCount" -eq 0 ]
               then
                  {
                    echo '[ -x '"$SCRIPT_FPATH"' ] && '"$SCRIPT_FPATH"' -mount &  '"$theScriptNameTag"
                  } >> "$initStartScript"
               fi
            else
               {
                  echo "#!/bin/sh" ; echo
                  echo '[ -x '"$SCRIPT_FPATH"' ] && '"$SCRIPT_FPATH"' -mount &  '"$theScriptNameTag"
                  echo
               } > "$initStartScript"
            fi
            chmod 755 "$initStartScript"
            ;;
        delete)
            if [ -s "$initStartScript" ] && \
               { grep -q "${theScriptNameTag}$" "$initStartScript" || \
                 grep -q " $SCRIPT_FPATH -mount" "$initStartScript" ; }
            then
               sed -i "/${theScriptNameTag}/d" "$initStartScript"
               sed -i "\\~ $SCRIPT_FPATH -mount~d" "$initStartScript"
            fi
            ;;
        status)
            if [ -s "$MODF_CRU_CMD" ] && [ -s "$SCRIPT_FPATH" ] && \
               [ "$(grep -cx '\[ -x '"$SCRIPT_FPATH"' \] && '"$SCRIPT_FPATH"' -mount &  '"$theScriptNameTag" "$initStartScript")" -gt 0 ]
            then
                echo ENABLED ; return 0
            else
                echo DISABLED ; return 1
            fi
            ;;
    esac
}

##--------------------------------------------------##
_CheckConfig_()
{
    [ ! -f "$CRU_CMD_CONF" ] && printf '' > "$CRU_CMD_CONF"

	if [ -s "$CRU_CMD_CONF" ]
	then
		chmod 644 "$CRU_CMD_CONF"
		_DOStoUNIX_ "$CRU_CMD_CONF"

		if ! grep -q '^CRU_CMD_MOUNT_ENABLE=' "$CRU_CMD_CONF"
		then
			{
			   echo "# To handle and prevent stuck 'nvram' commands #"
			   printf "CRU_CMD_MOUNT_ENABLE=true\n"
			} >> "$CRU_CMD_CONF"
		fi
        if ! grep -qE '^CRU_CMD_MOUNT_ENABLE=(true|false)$' "$CRU_CMD_CONF"
        then
            sed -i 's/^CRU_CMD_MOUNT_ENABLE=.*/CRU_CMD_MOUNT_ENABLE=true/' "$CRU_CMD_CONF"
        fi
	else
		{
		   echo "# To handle and prevent stuck 'nvram' commands #"
		   printf "CRU_CMD_MOUNT_ENABLE=true\n"
		} >> "$CRU_CMD_CONF"
		chmod 644 "$CRU_CMD_CONF"
	fi
}

##--------------------------------------------------##
_ConfigSetMount_()
{
    if [ $# -eq 0 ] || [ -z "$1" ] || \
       ! printf '%s\n' "$1" | grep -qE '^-(enable|disable)$'
    then return 1
    fi

    local boolVal
    if [ "$1" = "-enable" ]
    then boolVal=true
    else boolVal=false
    fi

	if [ ! -s "$CRU_CMD_CONF" ] || \
       ! grep -q '^CRU_CMD_MOUNT_ENABLE=' "$CRU_CMD_CONF"
	then
        {
		   echo "# To handle and prevent stuck 'nvram' commands #"
		   printf "CRU_CMD_MOUNT_ENABLE=${boolVal}\n"
		} >> "$CRU_CMD_CONF"
    else
		_DOStoUNIX_ "$CRU_CMD_CONF"
		if ! grep -qE "^CRU_CMD_MOUNT_ENABLE=${boolVal}$" "$CRU_CMD_CONF"
		then
			sed -i "s/^CRU_CMD_MOUNT_ENABLE=.*/CRU_CMD_MOUNT_ENABLE=${boolVal}/" "$CRU_CMD_CONF"
		fi
	fi
    chmod 644 "$CRU_CMD_CONF"

    return 0
}

##--------------------------------------------------##
_GetMountEnable_()
{
    local retCode  doLog=false  theMsg

    if [ $# -gt 0 ] && [ "$1" = "-doLOG" ]
    then doLog=true
    else doLog=false
    fi

	if [ ! -s "$CRU_CMD_CONF" ] || \
	   ! grep -q '^CRU_CMD_MOUNT_ENABLE=' "$CRU_CMD_CONF" || \
	   grep -q '^CRU_CMD_MOUNT_ENABLE=true$' "$CRU_CMD_CONF"
	then
        retCode=0
        theMsg="Mounting the modified CRU script [$MODF_CRU_CMD] is currently ENABLED."
        if "$doLog"
        then _DoLog_ "$theMsg"
        else _ShowDebugMsg_ "$theMsg"
        fi
	else
        retCode=1
        theMsg="Mounting the modified CRU script [$MODF_CRU_CMD] is currently DISABLED."
        if "$doLog"
        then _DoLog_ "$theMsg"
        else _ShowDebugMsg_ "$theMsg"
        fi
	fi

    return "$retCode"
}

##--------------------------------------------------##
_GetMountStatus_()
{
    local retCode  mountedCRU  mountedSRC  doMountCheck

    if [ $# -gt 0 ] && [ "$1" = "-check" ]
    then doMountCheck=true
    else doMountCheck=false
    fi
    
    mountedCRU="$(grep -E "$CRU_CMD_RegExp" /proc/mounts | awk -F' ' '{print $2}')"
    mountedSRC="$(grep -E "$CRU_CMD_RegExp" /proc/self/mountinfo | awk -F' ' '{print $4}')"

    if [ -z "$mountedCRU" ] || [ -z "$mountedSRC" ]
    then
        retCode=1
        _ShowDebugMsg_ "The modified script file [$MODF_CRU_CMD] is *NOT* mounted."
    else
        retCode=0
        if "$doMountCheck" && ! echo "$MODF_CRU_CMD" | grep -qE "${mountedSRC}$"
        then retCode=1
        fi
        if [ "$retCode" -eq 0 ]
        then _ShowDebugMsg_ "The modified script file [$MODF_CRU_CMD] is found mounted."
        else _ShowDebugMsg_ "The modified script file [$MODF_CRU_CMD] is *NOT* mounted."
        fi
    fi

    _GetMountEnable_
    return "$retCode"
}

##--------------------------------------------------##
_DoMount_()
{
    local retCode

    if ! _GetMountEnable_ -doLOG
    then return 1
    fi

    if _GetMountStatus_ >/dev/null
    then
        _ShowDebugMsg_ "Unmounting modified script file [$MODF_CRU_CMD]..."
        umount "$ORIG_CRU_CMD" 2>/dev/null
    fi

    _DoLog_ "Mounting modified script file [$MODF_CRU_CMD]..."
    mount -o bind "$MODF_CRU_CMD" "$ORIG_CRU_CMD"

    if _GetMountStatus_ -check >/dev/null 
    then
        retCode=0
        _DoLog_ "Modified script file [$MODF_CRU_CMD] was mounted successfully."
    else
        retCode=1
        _DoLog_ "**ERROR**: Modified script file [$MODF_CRU_CMD] was *NOT* mounted."
    fi

    _DoInitStart_ create
    return "$retCode"
}

##--------------------------------------------------##
_DoUnMount_()
{
    local retCode

    if ! _GetMountStatus_ >/dev/null
    then
        _DoLog_ "Modified script file [$MODF_CRU_CMD] was NOT found mounted."
        return 0
    fi

    _DoLog_ "Unmounting modified script file [$MODF_CRU_CMD]..."
    umount "$ORIG_CRU_CMD" 2>/dev/null

    if ! _GetMountStatus_ -check >/dev/null
    then
        retCode=0
        _DoLog_ "Modified script file [$MODF_CRU_CMD] was unmounted successfully."
    else
        retCode=1
        _DoLog_ "**ERROR**: Modified script file [$MODF_CRU_CMD] was *NOT* unmounted."
    fi

    _DoInitStart_ delete
    return "$retCode"
}

##--------------------------------------------------##
if [ $# -eq 0 ] || [ -z "$1" ] || \
   printf '%s\n' "$1" | grep -qE '^[-]?help$'
then
    _ShowUsage_
    exit 1
fi
if ! printf '%s\n' "$1" | grep -qE '^-(mount|unmount|status|check|enable|disable|checkEnable)$'
then
    printf "\n**ERROR**: UNKNOWN or INVALID argument was provided.\n\n"
    _ShowUsage_
    exit 1
fi
if [ ! -s "$ORIG_CRU_CMD" ]
then
    _DoLog_ "**ERROR**: Original script file [$ORIG_CRU_CMD] is *NOT* found."
    exit 1
fi
if [ ! -s "$MODF_CRU_CMD" ]
then
    _DoLog_ "**ERROR**: Modified script file [$MODF_CRU_CMD] is *NOT* found."
    exit 1
fi

_CheckConfig_

if printf '%s\n' "$1" | grep -qE '^-(mount|unmount)$'
then doDebugLog=true
else doDebugLog=false
fi

_CheckLogFileSize_
_DoLog_ "$logTagSTART" "$@"

exitCode=1
case "$1" in
          -mount)
              _DoMount_ ; exitCode="$?"
              ;;
        -unmount)
              _DoUnMount_ ; exitCode="$?"
              ;;
         -status)
              _GetMountStatus_ ; exitCode="$?"
              ;;
          -check)
              _GetMountStatus_ -check ; exitCode="$?"
              ;;
         -enable)
              _ConfigSetMount_ -enable
              _GetMountEnable_ ; exitCode="$?"
              ;;
        -disable)
              _ConfigSetMount_ -disable
              _GetMountEnable_ ; exitCode="$?"
              ;;
    -checkEnable)
              _GetMountEnable_ ; exitCode="$?"
              ;;
esac

_DoExit_ "$exitCode"

#EOF#
