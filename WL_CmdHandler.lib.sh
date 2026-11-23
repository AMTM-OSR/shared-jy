#!/bin/sh
#################################################################
# FILENAME: WL_CmdHandler.lib.sh
# TAG: _LIB_WL_CmdHandler_lib_SHELL_
#
# Library of Miscellaneous Helper Functions & Definitions to 
# handle 'wl' commands for calling process. This is done to
# avoid problems when the command gets "stuck" due to some
# firmware bug.
#----------------------------------------------------------------
# Original Author: Martinski W.
# Creation Date: 2026-Oct-24
# Last Modified: 2026-Nov-22 [Martinski W.]
#################################################################

if [ -z "${_LIB_WL_CmdHandler_lib_SHELL_:+xSETx}" ]
then _LIB_WL_CmdHandler_lib_SHELL_=0
else return 0
fi

readonly WL_LIB_VERSION="v0.9.5"
readonly WL_LIB_VERSTAG="26112223"
readonly WL_LIB_FNAME="WL_CmdHandler.lib.sh"

wl_ScriptFileName="${0##*/}"
wl_ScriptFNameTag="${wl_ScriptFileName%.*}"
wl_PID="$(printf "%05d" "$$")"

# Give FIRST priority to built-in binaries over any other #
wl_initPATHdirs='/bin:/usr/bin:/sbin:/usr/sbin'
if ! echo "$PATH" | grep -q "^$wl_initPATHdirs"
then export PATH="${wl_initPATHdirs}:$PATH"
fi

readonly _WL_cmd_="$(which wl | head -n1)"

wl_CLRct="\e[0m"
wl_REDct="\e[1;31m"
wl_GRNct="\e[1;32m"
wl_YLWct="\e[1;33m"
wl_MGNTct="\e[1;35m"

wl_SysLogALERT=1
wl_SysLogCRITC=2
wl_SysLogERROR=3
wl_SysLogWARNG=4
wl_SysLogNOTIC=5
wl_SysLogINFOR=6
wl_LogTagStr="${wl_ScriptFNameTag}_[$$]"

if [ -t 0 ] && ! tty | grep -qwi 'NOT'
then wl_IsInteractive=true
else wl_IsInteractive=false
fi

wl_InitUSleep=50000
wl_WaitUSleep=250
wl_WaitCntMAX=400
wl_CentiSecsN=200
wl_CmdTriesMAX=3
wl_TempPath="/tmp/var/tmp"
wl_OutTmpFPath="${wl_TempPath}/wl_OUT_${wl_ScriptFNameTag}_${wl_PID}.wOUT"
wl_ErrTmpFPath="${wl_TempPath}/wl_ERR_${wl_ScriptFNameTag}_${wl_PID}.wERR"

##---------------------------------------------##
_WL_PrintMsg_()
{ "$wl_IsInteractive" && printf "$1" ; }

##---------------------------------------------##
_WL_LogMsg_()
{
   local logPrioNum

   if [ $# -gt 1 ] && [ -n "$2" ] && \
      echo "$2" | grep -qE '^[1-6]$'
   then logPrioNum="$2"
   else logPrioNum="$wl_SysLogNOTIC"
   fi
   logger -t "$wl_LogTagStr" -p "$logPrioNum" "$1"
}

##---------------------------------------------##
_WL_GetUptimeCSecs_()
{ awk -F' ' '{print int($1 * 100)}' /proc/uptime ; }

##---------------------------------------------##
_wl_CMD_()
{
   local wl_ProcID  wl_ProcOK=false  retCode=1
   local waitCountNUM=0  logMsgStr
   local startCSecs  nowCSecs  maxCSecs  diffCSecs=0

   printf '' > "$wl_OutTmpFPath"
   printf '' > "$wl_ErrTmpFPath"
   $_WL_cmd_ "$@" 1>"$wl_OutTmpFPath" 2>"$wl_ErrTmpFPath" &
   wl_ProcID="$!"
   usleep "$wl_InitUSleep"

   startCSecs="$(_WL_GetUptimeCSecs_)"
   nowCSecs="$startCSecs"
   maxCSecs="$((startCSecs + wl_CentiSecsN))"

   while true
   do
       if ! kill -EXIT "$wl_ProcID" 2>/dev/null
       then wl_ProcOK=true ; break
       fi
       usleep "$wl_WaitUSleep"
       nowCSecs="$(_WL_GetUptimeCSecs_)"
       waitCountNUM="$((waitCountNUM + 1))"
       if [ "$nowCSecs" -gt "$maxCSecs" ] || \
          [ "$waitCountNUM" -ge "$wl_WaitCntMAX" ]
       then break
       fi
   done

   if kill -EXIT "$wl_ProcID" 2>/dev/null
   then
       retCode=127 ; wl_ProcOK=false
       kill -KILL "$wl_ProcID" 2>/dev/null ; wait "$wl_ProcID"
       if [ "$nowCSecs" -gt "$startCSecs" ]
       then diffCSecs="$((nowCSecs - startCSecs))"
       fi
       logMsgStr="**ALERT**: Wait timeout [TryCount=$cmdNumTries, WaitCount=$waitCountNUM, CSecs=$diffCSecs] for [$_WL_cmd_ $*] command was reached [$WL_LIB_FNAME]."
       _WL_LogMsg_ "$logMsgStr" "$wl_SysLogWARNG"
   fi
   if "$wl_ProcOK"
   then retCode=0
   fi
   return "$retCode"
}

##---------------------------------------------##
_WL_Cmd_()
{
    if [ $# -eq 0 ] || [ -z "$1" ] || \
       printf '%s\n' "$1" | grep -qE '^[-]{0,2}help$'
    then $_WL_cmd_ ; return "$?"
    fi
    if printf '%s\n' "$1" | grep -qE '^[-]?version$'
    then
        printf "\nVersion: ${wl_GRNct}${WL_LIB_VERSION}${wl_CLRct} [${wl_YLWct}${WL_LIB_VERSTAG}${wl_CLRct}]\n\n"
        return 0
    fi

    local retCode  cmdNumTries=1  logMsgStr  wl_CmdOK=false

    while true
    do
        _wl_CMD_ "$@"
        retCode="$?"
        if [ "$retCode" -eq 0 ]
        then wl_CmdOK=true ; break
        fi
        if [ "$cmdNumTries" -ge "$wl_CmdTriesMAX" ]
        then break
        fi
        sleep 1
        cmdNumTries="$((cmdNumTries + 1))"
    done

    if "$wl_CmdOK"
    then
        cat "$wl_OutTmpFPath"
        if [ -s "$wl_ErrTmpFPath" ] && \
           [ ! -s "$wl_OutTmpFPath" ]
        then
            retCode=1
            cat "$wl_ErrTmpFPath" >&2
        fi
    else
        echo
        logMsgStr="**ERROR**: Maximum number of tries [Count=$cmdNumTries] for [$_WL_cmd_ $*] command was reached [$WL_LIB_FNAME]."
        _WL_LogMsg_ "$logMsgStr" "$wl_SysLogERROR"
    fi

    rm -f "$wl_OutTmpFPath" "$wl_ErrTmpFPath"
    return "$retCode"
}

WL_Cmd='_WL_Cmd_'
alias wl='_WL_Cmd_'

_LIB_WL_CmdHandler_lib_SHELL_=1

if [ ! -x "$_WL_cmd_" ]
then
   wl_LogMsgStr="**ERROR**: Path to 'wl' command was *NOT* found [$WL_LIB_FNAME]."
   wl_TheMsgStr="${wl_REDct}**ERROR**${wl_CLRct}: Path to 'wl' command was *NOT* found."
   _WL_PrintMsg_ "\n${wl_TheMsgStr}\n"
   _WL_LogMsg_ "$wl_LogMsgStr" "$wl_SysLogERROR"
   exit 100
fi

if false && [ $# -gt 1 ] && [ "$1" = "doDebugMode" ] && [ -n "$*" ]
then shift ; _WL_Cmd_ "$@"
fi

#EOF#
