#!/bin/sh
#################################################################
# FILENAME: NVRAM_CmdHandler.lib.sh
# TAG: _LIB_NVRAM_CmdHandler_lib_SHELL_
#
# Library of Miscellaneous Helper Functions & Definitions to 
# handle 'nvram' commands for calling process. This is done
# to avoid problems when the command gets "stuck" due to some
# firmware bug.
#----------------------------------------------------------------
# Original Author: Martinski W.
# Creation Date: 2026-Oct-24
# Last Modified: 2026-Nov-22 [Martinski W.]
#################################################################

if [ -z "${_LIB_NVRAM_CmdHandler_lib_SHELL_:+xSETx}" ]
then _LIB_NVRAM_CmdHandler_lib_SHELL_=0
else return 0
fi

readonly NVRAM_LIB_VERSION="v0.9.5"
readonly NVRAM_LIB_VERSTAG="26112223"
readonly NVRAM_LIB_FNAME="NVRAM_CmdHandler.lib.sh"

nvramScriptFileName="${0##*/}"
nvramScriptFNameTag="${nvramScriptFileName%.*}"
nvramPID="$(printf "%05d" "$$")"

# Give FIRST priority to built-in binaries over any other #
nvramInitPATHdirs='/bin:/usr/bin:/sbin:/usr/sbin'
if ! echo "$PATH" | grep -q "^$nvramInitPATHdirs"
then export PATH="${nvramInitPATHdirs}:$PATH"
fi

readonly _NVRAM_cmd_="$(which nvram | head -n1)"

nvramCLRct="\e[0m"
nvramREDct="\e[1;31m"
nvramGRNct="\e[1;32m"
nvramYLWct="\e[1;33m"
nvramMGNTct="\e[1;35m"

nvramSysLogALERT=1
nvramSysLogCRITC=2
nvramSysLogERROR=3
nvramSysLogWARNG=4
nvramSysLogNOTIC=5
nvramSysLogINFOR=6
nvramLogTagStr="${nvramScriptFNameTag}_[$$]"

if [ -t 0 ] && ! tty | grep -qwi 'NOT'
then nvramIsInteractive=true
else nvramIsInteractive=false
fi

nvramInitUSleep=10
nvramWaitUSleep=40
nvramWaitCntMAX=400
nvramCentiSecsN=200
nvramCmdTriesMAX=3
nvramTempPath="/tmp/var/tmp"
nvramOutTmpFPath="${nvramTempPath}/nvramOUT_${nvramScriptFNameTag}_${nvramPID}.nOUT"
nvramErrTmpFPath="${nvramTempPath}/nvramERR_${nvramScriptFNameTag}_${nvramPID}.nERR"

##---------------------------------------------##
_NVRAM_PrintMsg_()
{ "$nvramIsInteractive" && printf "$1" ; }

##---------------------------------------------##
_NVRAM_LogMsg_()
{
   local logPrioNum

   if [ $# -gt 1 ] && [ -n "$2" ] && \
      echo "$2" | grep -qE '^[1-6]$'
   then logPrioNum="$2"
   else logPrioNum="$nvramSysLogNOTIC"
   fi
   logger -t "$nvramLogTagStr" -p "$logPrioNum" "$1"
}

##---------------------------------------------##
_NVRAM_GetUptimeCSecs_()
{ awk -F' ' '{print int($1 * 100)}' /proc/uptime ; }

##---------------------------------------------##
_nvramGET_()
{
   local nvramProcID  nvramProcOK=false  retCode=1
   local waitCountNUM=0  logMsgStr
   local startCSecs  nowCSecs  maxCSecs  diffCSecs=0

   nvramKeyValue=""
   printf '' > "$nvramOutTmpFPath"
   $_NVRAM_cmd_ get "$1" > "$nvramOutTmpFPath" &
   nvramProcID="$!"
   usleep "$nvramInitUSleep"

   startCSecs="$(_NVRAM_GetUptimeCSecs_)"
   nowCSecs="$startCSecs"
   maxCSecs="$((startCSecs + nvramCentiSecsN))"

   while true
   do
       if ! kill -EXIT "$nvramProcID" 2>/dev/null
       then nvramProcOK=true ; break
       fi
       usleep "$nvramWaitUSleep"
       nowCSecs="$(_NVRAM_GetUptimeCSecs_)"
       waitCountNUM="$((waitCountNUM + 1))"
       if [ "$nowCSecs" -gt "$maxCSecs" ] || \
          [ "$waitCountNUM" -ge "$nvramWaitCntMAX" ]
       then break
       fi
   done

   if kill -EXIT "$nvramProcID" 2>/dev/null
   then
       retCode=127 ; nvramProcOK=false
       kill -KILL "$nvramProcID" 2>/dev/null ; wait "$nvramProcID"
       if [ "$nowCSecs" -gt "$startCSecs" ]
       then diffCSecs="$((nowCSecs - startCSecs))"
       fi
       logMsgStr="**ALERT**: Wait timeout [TryCount=$cmdNumTries, WaitCount=$waitCountNUM, CSecs=$diffCSecs] for [$_NVRAM_cmd_ get $1] command was reached [$NVRAM_LIB_FNAME]."
       _NVRAM_LogMsg_ "$logMsgStr" "$nvramSysLogWARNG"
   fi
   if "$nvramProcOK"
   then
       retCode=0
       [ -s "$nvramOutTmpFPath" ] && \
       nvramKeyValue="$(cat "$nvramOutTmpFPath")"
   fi

   rm -f "$nvramOutTmpFPath"
   return "$retCode"
}

##---------------------------------------------##
_NVRAM_Get_()
{
    local retCode  cmdNumTries=1  logMsgStr
    local nvramKeyValue=""  nvramCmdOK=false

    while true
    do
        _nvramGET_ "$1"
        retCode="$?"
        if [ "$retCode" -eq 0 ]
        then nvramCmdOK=true ; break
        fi
        if [ "$cmdNumTries" -ge "$nvramCmdTriesMAX" ]
        then break
        fi
        sleep 1
        cmdNumTries="$((cmdNumTries + 1))"
    done

    if "$nvramCmdOK"
    then
        echo "$nvramKeyValue"
    else
        echo
        logMsgStr="**ALERT**: Maximum number of tries [Count=$cmdNumTries] for [$_NVRAM_cmd_ get $1] command was reached [$NVRAM_LIB_FNAME]."
        _NVRAM_LogMsg_ "$logMsgStr" "$nvramSysLogERROR"
    fi
    return "$retCode"
}

##---------------------------------------------##
_nvramSHOW_()
{
   local nvramProcID  nvramProcOK=false
   local waitCountNUM=0  logMsgStr  retCode=1
   local startCSecs  nowCSecs  maxCSecs  diffCSecs=0

   printf '' > "$nvramOutTmpFPath"
   printf '' > "$nvramErrTmpFPath"
   $_NVRAM_cmd_ "$1" 1>"$nvramOutTmpFPath" 2>"$nvramErrTmpFPath" &
   nvramProcID="$!"
   usleep "$nvramInitUSleep"

   startCSecs="$(_NVRAM_GetUptimeCSecs_)"
   nowCSecs="$startCSecs"
   maxCSecs="$((startCSecs + nvramCentiSecsN))"

   while true
   do
       if ! kill -EXIT "$nvramProcID" 2>/dev/null
       then nvramProcOK=true ; break
       fi
       usleep "$nvramWaitUSleep"
       nowCSecs="$(_NVRAM_GetUptimeCSecs_)"
       waitCountNUM="$((waitCountNUM + 1))"
       if [ "$nowCSecs" -gt "$maxCSecs" ] || \
          [ "$waitCountNUM" -ge "$nvramWaitCntMAX" ]
       then break
       fi
   done

   if kill -EXIT "$nvramProcID" 2>/dev/null
   then
       retCode=127 ; nvramProcOK=false
       kill -KILL "$nvramProcID" 2>/dev/null ; wait "$nvramProcID"
       if [ "$nowCSecs" -gt "$startCSecs" ]
       then diffCSecs="$((nowCSecs - startCSecs))"
       fi
       logMsgStr="**ALERT**: Wait timeout [TryCount=$cmdNumTries, WaitCount=$waitCountNUM, CSecs=$diffCSecs] for [$_NVRAM_cmd_ $1] command was reached [$NVRAM_LIB_FNAME]."
       _NVRAM_LogMsg_ "$logMsgStr" "$nvramSysLogWARNG"
   fi
   if "$nvramProcOK"
   then retCode=0
   fi
   return "$retCode"
}

##---------------------------------------------##
_NVRAM_Show_()
{
    local retCode  cmdNumTries=1  nvramCmdOK=false  logMsgStr

    while true
    do
        _nvramSHOW_ "$1"
        retCode="$?"
        if [ "$retCode" -eq 0 ]
        then nvramCmdOK=true ; break
        fi
        if [ "$cmdNumTries" -ge "$nvramCmdTriesMAX" ]
        then break
        fi
        sleep 1
        cmdNumTries="$((cmdNumTries + 1))"
    done

    if "$nvramCmdOK"
    then
        cat "$nvramOutTmpFPath"
        [ -s "$nvramErrTmpFPath" ] && cat "$nvramErrTmpFPath" >&2
    else
        echo
        logMsgStr="**ALERT**: Maximum number of tries [Count=$cmdNumTries] for [$_NVRAM_cmd_ $1] command was reached [$NVRAM_LIB_FNAME]."
        _NVRAM_LogMsg_ "$logMsgStr" "$nvramSysLogERROR"
    fi

    rm -f "$nvramOutTmpFPath" "$nvramErrTmpFPath"
    return "$retCode"
}

##---------------------------------------------##
_NVRAM_Cmd_()
{
    if [ $# -eq 0 ] || [ -z "$1" ] || \
       printf '%s\n' "$1" | grep -qE '^[-]{0,2}help$'
    then $_NVRAM_cmd_ ; return "$?"
    fi

    local retCode

    case "$1" in
        get) _NVRAM_Get_ "$2" ; retCode="$?"
             ;;
        show|dump)
             _NVRAM_Show_ "$1" ; retCode="$?"
             ;;
        version|-version)
             printf "\nVersion: ${nvramGRNct}${NVRAM_LIB_VERSION}${nvramCLRct} [${nvramYLWct}${NVRAM_LIB_VERSTAG}${nvramCLRct}]\n\n"
             retCode=0
             ;;
          *) $_NVRAM_cmd_ "$@" ; retCode="$?"
             ;;
    esac

    return "$retCode"
}

NVRAM_Cmd='_NVRAM_Cmd_'
alias nvram='_NVRAM_Cmd_'

_LIB_NVRAM_CmdHandler_lib_SHELL_=1

if [ ! -x "$_NVRAM_cmd_" ]
then
   nvramLogMsgStr="**ERROR**: Path to 'nvram' command was *NOT* found [$NVRAM_LIB_FNAME]."
   nvramTheMsgStr="${nvramREDct}**ERROR**${nvramCLRct}: Path to 'nvram' command was *NOT* found."
   _NVRAM_PrintMsg_ "\n${nvramTheMsgStr}\n"
   _NVRAM_LogMsg_ "$nvramLogMsgStr" "$nvramSysLogERROR"
   exit 100
fi

if false && [ $# -gt 1 ] && [ "$1" = "doDebugMode" ] && [ -n "$*" ]
then shift ; _NVRAM_Cmd_ "$@"
fi

#EOF#
