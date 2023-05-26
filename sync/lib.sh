#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   lib.sh of /distribution/Library/sync
#   Description: A multihost synchronization library
#   Authors: Ondrej Moris <omoris@redhat.com>
#            Dalibor Pospisil <dapospis@redhat.com>
#            Jaroslav Aster <jaster@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2023 Red Hat, Inc. All rights reserved.
#
#   This copyrighted material is made available to anyone wishing
#   to use, modify, copy, or redistribute it subject to the terms
#   and conditions of the GNU General Public License version 2.
#
#   This program is distributed in the hope that it will be
#   useful, but WITHOUT ANY WARRANTY; without even the implied
#   warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#   PURPOSE. See the GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public
#   License along with this program; if not, write to the Free
#   Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
#   Boston, MA 02110-1301, USA.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#   library-prefix = sync
#   library-version = 1
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Synchronization counter.
syncCOUNT=0

# Pattern for valid filename representing flag.
syncFLAG_PATTERN="^[A-Za-z0-9_-]*$"

# Logging prefix.
__syncLogPrefix="sync"

# port where the flags are published
syncPort=${syncPort-2134}

true <<'=cut'
=pod

=head1 NAME

ControlFlow/sync - a multihost synchronization library

=head1 DESCRIPTION

This is a synchronization library for multihost testing. It provides signal
setting and waiting as well as mutual synchronization or message and data
exchange.

The host specification is take from TMT_GUEST_* varaibles. There's a fallback
to CLIENTS and SERVERS variables for the beaker-like backwards compatibility.

The synchronization is done using a pyton's simple http server on each of the
hosts. I.e. each host publishes its own flags while others can pull them o
their own.

The library design is inspired by the Karel Srot's keylime/sync [1] library
while keeping most of the Ondrej Moris's sync/sync [2] library API.

1. https://github.com/RedHat-SP-Security/keylime-tests/tree/main/Library/sync
2. https://github.com/beakerlib/sync/tree/master/sync

=cut

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#   Variables
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

true <<'=cut'
=pod

=head1 GLOBAL VARIABLES

=over

=item syncIF (set automatically)

NIC interface which is used as a default route for machine IPv4/6 
address stored in syncME. This is useful, for instance, when 
sniffing traffic via tcpdump.

=item syncIFv6

This is IPv6 variant of syncIF.

=item syncCLIENT (set automatically)

IP address of the CLIENT. By default, IPv4 is preferred over IPv6
address.

=item syncCLIENTv6 (set automatically)

IPv6 address of the CLIENT. If the CLIENT has no IPv6 address of
a global scope, syncCLIENTv6 is empty.

=item syncME (set automatically)

IP address of the actual machine running the test. By default, 
IPv4 is preferred over IPv6 address.

=item syncMEv6 (set automaticall)

IPv6 address of the actual machine running the test. If the machine
has no IPv6 address of a global scope, syncMEv6 is empty.

=item syncOTHER (set automatically)

IP address of the other machine running the test. By default, IPv4
address is preferred over IPv6 address.

=item syncOTHERv6 (set automatically)

IPv6 address of the other machine running the test. If the machine
has no IPv6 address of a global scope, syncMEv6 is empty.

=item syncSERVER (set automatically)

IP address of the SERVER. By default, IPv4 address is preferred
over IPv6 address.

=item syncSERVERv6 (set automatically)

IPv6 address of the SERVER. If the SERVER has no IPv6 address of
a global scope, syncSERVERv6 is empty.

=item syncROLE (set automatically)

A role in a mutual communication played by the actual machine - 
either CLIENT or SERVER.

=item syncTEST (set automatically)

Unique test identifier (e.g. its name). By default, it is derived 
from TEST variable exported in Makefile. If there is no Makefile 
then it is derived from the test directory.

=item syncSLEEP (optional, 5 seconds by default)

A time (in seconds) to sleep between the flag polling.
In other words, whenever a host waits for the other 
side to set the flag of upload some data, it iteratively checks 
for those flags or data on synchronization storage, syncSLEEP
variable represents sleep time (in seconds) between those checks.

=item syncTIMEOUT (optional, 1800 seconds / 30 minutes by default)

A maximum time (in seconds) to wait for a synchronization flags or
data, this value should be considerably high. Notice that when 
waiting hits the syncTIMEOUT limit it fails and the rest of the 
test on both sides fails as well. The important is that the test
will be to clean-up phases eventually (as long as the time limit
of the test is not yet reached).

=back

=cut

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#   Private Functions - used only within lib.sh
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# These two private functions are called before (mount) and after
# (umount) working with shared storage. By default they are not
# doing anything but they can be overriden to perform task such as
# read-only / read-write remounting if needed.

__syncSHARE="/var/tmp/syncMultihost"
syncProvider="http"

__syncWget() {
  local QUIET CONNREFUSED
  [[ "$1" == "--quiet" ]] && { QUIET=1; shift; }
  local FILE="$1"
  local URL="$2"
  local res=0
  if command -v curl > /dev/null; then
    rlLogDebug "${FUNCNAME[0]}(): using curl for download of $URL"
    CONNREFUSED="--retry-connrefused"
    curl --help | grep -q -- $CONNREFUSED || CONNREFUSED=''
    curl --fail ${QUIET:+"--silent"} --location $CONNREFUSED --retry-delay 3 --retry-max-time 5 --retry 3 --connect-timeout 5 --max-time 5 --insecure -o "$FILE" "$URL" || let res++
  elif command -v wget > /dev/null; then
    rlLogDebug "${FUNCNAME[0]}(): using wget for download"
    wget ${QUIET:+"--quiet"} -t 3 -T 5 -w 5 --waitretry=3 --no-check-certificate --progress=dot:giga -O "$FILE" "$URL" || let res++
  else
    rlLogError "${FUNCNAME[0]}(): no tool for downloading web content is available"
    let res++
  fi
  return $res
}

__syncDownload() {
  __syncFoundOnHost="${1/|*}"
  if [[ "$syncProvider" =~ http ]]; then
    local flag
    flag="${1#*|}"
    rlLogDebug "${FUNCNAME[0]}(): downloading flag $flag raised by host $__syncFoundOnHost"
    __syncWget --quiet - "http://$__syncFoundOnHost:$syncPort/$flag"
  fi
}

__syncList() {
  local host hosts
  if [[ $# -eq 0 ]]; then
    hosts=( "${syncOTHER[@]}" )
  else
    hosts=( "$@" )
  fi
  for host in "${hosts[@]}"; do
    rlLogDebug "${FUNCNAME[0]}(): listing flags raised by host $host"
    if [[ "$syncProvider" =~ http ]]; then
      __syncWget --quiet - "http://$host:$syncPort/flags.txt" | sed -r "s/^/${host}|/"
    elif [[ "$syncProvider" =~ ncat ]]; then
      ncat --recv-only "$host" "$syncPort"
    fi
  done
}

__syncGet() {
  if [[ -z "$1" ]]; then
    rlLogError "${__syncLogPrefix}: Missing flag specification!"
    return 2
  fi
  local flag="$1"
  shift

  rlLogDebug "${FUNCNAME[0]}(): $syncROLE is checking the flag $flag"
  local rc=0 found
  found=$(__syncList "$@" | grep -m1 "|${syncTEST}/${flag}$" ) \
    && __syncDownload "${found}" \
      || rc=1

  return $rc
}

__syncSet() {
  local flag_name flag_file res
  res=0
  flag_name="$1"
  flag_file="${__syncSHARE}/${syncTEST}/${flag_name}"
  [[ "$syncProvider" =~ http ]] && {
    rlLogDebug "${FUNCNAME[0]}(): make sure the path is available"
    mkdir -p "${__syncSHARE}/${syncTEST}" || ((res++))

    rlLogDebug "${FUNCNAME[0]}(): create the flag file temporary file"
    cat - > "${flag_file}.partial" || ((res++))

    rlLogDebug "${FUNCNAME[0]}(): move to the final flag file"
    mv -f "${flag_file}.partial" "${flag_file}" || ((res++))
  }
  rlLogDebug "${FUNCNAME[0]}(): populate a list of flag names"
  echo "${syncTEST}/${flag_name}" >> "$__syncSHARE/flags.txt" || ((res++))
  systemctl restart syncHelper
}

__syncInstallNcatHelperService() {
  cat > /etc/systemd/system/syncHelper.service <<EOF
[Unit]
Description=a multihost ncat synchronization helper service
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/ncat -l -k -e '/usr/bin/cat $__syncSHARE/__FLAGS' --send-only $syncPort
TimeoutStopSec=5
Restart=always
RestartSec=5s

[Install]
WantedBy=default.target
EOF
}

__syncInstallHttpHelperService() {
  local helper_script=/usr/local/bin/syncHelper
  local PYTHON
  if [[ -x /usr/libexec/platform-python ]]; then
      PYTHON="/usr/libexec/platform-python -m http.server"
  elif command -v python3; then
      PYTHON="$(command -v python3) -m http.server"
  else
      PYTHON="$(command -v python) -m SimpleHTTPServer"
  fi
  cat > $helper_script <<EOF
#!/bin/bash
cd $__syncSHARE
$PYTHON $syncPort
EOF
  chmod a+x $helper_script
  cat > /etc/systemd/system/syncHelper.service <<EOF
[Unit]
Description=a multihost http synchronization helper service
After=network.target

[Service]
Type=simple
ExecStart=$helper_script
TimeoutStopSec=5
Restart=always
RestartSec=5s

[Install]
WantedBy=default.target
EOF
}

__syncInstallHelperService() {
  mkdir -p "$__syncSHARE"
  __syncInstallHttpHelperService
  local zones
  if zones=$(firewall-cmd --get-zones 2> /dev/null); then
  for zone in $zones; do
      firewall-cmd --zone="$zone" --add-port=2134/tcp
  done
  elif zones=$(firewall-offline-cmd --get-zones 2> /dev/null); then
  for zone in $zones; do
      firewall-offline-cmd --zone="$"zone --add-port=2134/tcp > /dev/null 2>&1
  done
  else
  rlLogInfo "could not update firewall settings"
  fi
  systemctl enable syncHelper
  systemctl restart syncHelper
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#   Public Functions - exported by the library
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

true <<'=cut'
=pod

=head1 FUNCTIONS

=head2 syncIsClient

Check if this host is CLIENT. If so, returns 0, otherwise 1.

=cut

syncIsClient() {
  [[ "${syncROLE^^}" == "CLIENT" ]] && return 0 || return 1
}

true <<'=cut'
=pod

=head2 syncIsServer

Check if this host is SERVER. If so, returns 0, otherwise 1.

=cut

syncIsServer() {
  [[ "${syncROLE^^}" == "SERVER" ]] && return 0 || return 1
}

true <<'=cut'
=pod

=head2 syncRun who what

Execute commands given in 'what' by rlRun on 'who' which can be
either CLIENT or SERVER. For instance, the following three commands
are equivalent:

 * syncRun "CLIENT" -s "date" 0 "Printing date on CLIENT"

 * syncIsClient && rlRun -s "date" 0 "Printing date on CLIENT"

 * if [ "$syncROLE" == "CLIENT" ]; then
     rlRun -s "date" 0 "Printing date on CLIENT"
     fi

Return an exit code of rlRun and 255 in case of error.

=cut

syncRun() {
  if [ "$1" == "$syncROLE" ]; then
    shift 1
    rlRun "$@"
    return $?
  fi
  return 0
}

true <<'=cut'
=pod

=head2 syncCleanup

Removes all test synchronization data created by the other side of
the connection. This function should be called only in clean-up 
phase as the last sync function.

=cut

syncCleanup() {
  rlLogInfo "${__syncLogPrefix}: $syncROLE clears all its data"
  rm -rf ${__syncSHARE:?}/* /tmp/syncBreak /tmp/syncSet
  touch ${__syncSHARE:?}/flags.txt
}

true <<'=cut'
=pod

=head2 syncSynchronize

Synchronize both sides of the connection Both sides waits for each
other so that time on CLIENT and SERVER right after the return from
the function is within 2*$syncSLEEP. Returns 0.

=cut

syncSynchronize() {
  local res=0
  syncCOUNT=$[$syncCOUNT + 1]

  rlLogInfo "$__syncLogPrefix: Synchronizing all hosts"
  # each side raises its own flag
  syncSet "SYNC_${syncCOUNT}" || let res++
  local host
  # wait for all others to raise their flags as well
  for host in "${syncOTHER[@]}"; do
    syncExp "SYNC_${syncCOUNT}" "${host}" || let res++
  done
  rlLogInfo "$__syncLogPrefix: all hosts synchronized synchronized"

  return $res
}

true <<'=cut'
=pod

=head2 syncSet flag [value]

Raise a flag represented by a file in the shared synchronization
storage. If an optional second parameter is given, it is written
into the flag file. If the second parameter is '-', a stdin is 
written into the flag file. Return 0 if the flag is successfully
created and a non-zero otherwise.

=cut

syncSet() {
  local rc=0

  if [ -z "$1" ]; then
    rlLogError "${__syncLogPrefix}: Missing flag!"
    return 1
  fi

  if ! [[ "$1" =~ $syncFLAG_PATTERN ]]; then
    rlLogError "${__syncLogPrefix}: Incorrect flag (must match ${syncFLAG_PATTERN})!"
    return 2
  fi

  if [[ "$2" == "-" ]]; then
    (
      echo -n "S_T_D_I_N:"
      cat -
    ) | __syncSet "$1"
    if [ $? -ne 0 ]; then
      rlLogError "${__syncLogPrefix}: Cannot write flag!"
      rc=3
    else
      rlLogInfo "${__syncLogPrefix}: $syncROLE set flag $1 with a content"
    fi
  elif [ -n "$2" ]; then
    echo "$2" | __syncSet "$1"
    if [ $? -ne 0 ]; then
      rlLogError "${__syncLogPrefix}: Cannot write flag!"
      rc=3
    else
      rlLogInfo "${__syncLogPrefix}: $syncROLE set flag $1 with message \"$2\""
    fi
  else
    rlLogInfo "${__syncLogPrefix}: $syncROLE set flag $1"
    echo '' | __syncSet "$1"
  fi

  return $rc
}

true <<'=cut'
=pod

=head2 syncExp flag [host ..]

Waiting for a flag raised by another host(s). If no host is specified
all the other hosts are checked. If it contains some content, it is printed
to the standard output. The raised flag is removed afterwards. 
Waiting is termined when synchronization timeout (syncTIMEOUT) is
reached.

Waiting may be also unblocked by a user intervention in two ways:
  1. using /tmp/syncSet - this behaves the same as it would be set
     by syncSet() function including the value processing (touch or
     put a value in the file),
  2. using /tmp/syncBreak - this is a premanent setting which will
     unblock all future syncExp() function calls untils the test is
     executed again (just touch the file).

Return 0 when the flag is raised, 1 in case of timeout, 3 in case
of user's permanent unblock, and 2 in case of other errors.

=cut
#'

syncExp() {
  local rc=0
  local flag="$1"
  shift

  if [[ -z "$flag" ]]; then
    rlLogError "${__syncLogPrefix}: Missing flag!"
    return 2
  fi

  if ! [[ "$flag" =~ $syncFLAG_PATTERN ]]; then
    rlLogError "${__syncLogPrefix}: Incorrect flag (must match ${syncFLAG_PATTERN})!"
    return 2
  fi

  if [[ $# -eq 0 ]]; then
    rlLogInfo "${__syncLogPrefix}: $syncROLE is waiting for flag $flag to appear on any other host"
  else
    rlLogInfo "${__syncLogPrefix}: $syncROLE is waiting for flag $flag to appear on host(s): $*"
  fi
  local file
  file="$(mktemp)"
  matchedfile=''
  local timer=0
  while :; do
    [[ -e /tmp/syncBreak ]] && {
      matchedfile="/tmp/syncBreak"
      rlLogError "detected user's permanent break"
      return 3
    }
    ls "/tmp/syncSet" >/dev/null 2>&1 && {
      matchedfile='/tmp/syncSet'
      break
    }
    __syncGet "$flag" "$@" > "$file" && {
      matchedfile="$file"
      rlLogDebug "${FUNCNAME[0]}(): got flag $flag"
      break
    }
    sleep "$syncSLEEP"
    timer=$((timer+syncSLEEP))
    if [[ $timer -gt $syncTIMEOUT ]]; then
      rlLogError "${__syncLogPrefix}: Waiting terminated (timeout expired)!"
      rc=1
      break
    fi
    rlLogDebug "${FUNCNAME[0]}(): did not get flag $flag, trying again"
  done
  if [ $rc -eq 0 ]; then
    rlLogInfo "${__syncLogPrefix}: $syncROLE found flag $flag on host $__syncFoundOnHost"
    if [[ -s "$matchedfile" ]]; then
      local message
      message=$(head -c 10 "$matchedfile")
      if [[ "$message" == "S_T_D_I_N:" ]]; then
        rlLogInfo "${__syncLogPrefix}: $syncROLE got flag $flag with a content"
        tail -c +11 "$matchedfile"
      else
        message=$(cat "$matchedfile")
        if [[ -z "$message" ]]; then
          rlLogInfo "${__syncLogPrefix}: $syncROLE got pure flag $flag"
        else
          rlLogInfo "${__syncLogPrefix}: $syncROLE got flag $flag with message \"$message\""
        fi
        echo "$message"
      fi
    else
      rlLogInfo "${__syncLogPrefix}: $syncROLE got flag $flag"
    fi
  fi
  rm -f "/tmp/syncSet" "$file"

  return $rc
}

true <<'=cut'
=pod

=head2 syncCheck flag

Check if a flag represented by a file in the shared synchronization
storage is raised. If so, 0 is returned and flag message (if any) is
printed to the standard output. If a flag is not yet raised 1 is 
returned or 2 in case of errors.

=cut

syncCheck() {
  local rc=0

  if [ -z "$1" ]; then
    rlLogError "${__syncLogPrefix}: Missing flag!"
    return 2
  fi

  if ! [[ "$1" =~ $syncFLAG_PATTERN ]]; then
    rlLogError "${__syncLogPrefix}: Incorrect flag (must match ${syncFLAG_PATTERN})!"
    return 2
  fi

  local file
  file="/tmp/syncSet"
  rlLogInfo "${__syncLogPrefix}: $syncROLE is checking flag $1"
  if __syncGet "$1" > "file"; then
    if [[ -s "$file" ]]; then
      local message
      message=$(head -c 10 "$file")
      if [[ "$message" == "S_T_D_I_N:" ]]; then
        rlLogInfo "${__syncLogPrefix}: $syncROLE got flag $1 with a content"
        tail -c +11 "$file"
      else
        message=$(cat "$file")
        rlLogInfo "${__syncLogPrefix}: $syncROLE got flag $1 with message \"$message\""
        echo "$message"
      fi
    else
      rlLogInfo "${__syncLogPrefix}: $syncROLE got flag $1"
    fi
  else
    rlLogInfo "${__syncLogPrefix}: $syncROLE did not get flag $1"
    rc=1
  fi
  rm -f "$file"

  return $rc
}

true <<'=cut'
=pod

=head2 syncResults

Set the current test state into a flag and check other sides current states.
The purpose is to make all the sides to fail mutually.

Returns 0 if all the other sides passed.

=cut

syncResults() {
  local resultFlag="__syncMutualResults__"
  syncSet "$resultFlag" "$(rlGetTestState; echo $?)" || let res++
  local host
  # wait for all others to raise their flags as well
  for host in "${syncOTHER[@]}"; do
    [[ "$(syncExp "$resultFlag" "${host}")" == "0" ]] || let res++
  done
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#   Initialization & Verification
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   This is an initialization and verification callback which will
#   be called by rlImport after sourcing the library. The function
#   returns 0 only when the library is ready to serve.

syncLibraryLoaded() {
  # Setting defaults for optional global variables.
  [[ -z "$syncSLEEP" ]] && syncSLEEP=5
  rlLogInfo "$__syncLogPrefix: Setting syncSLEEP to $syncSLEEP seconds"

  [[ -z "$syncTIMEOUT" ]] && syncTIMEOUT=7200
  rlLogInfo "$__syncLogPrefix: Setting syncTIMEOUT to $syncTIMEOUT seconds"

  if [[ -z "$syncTEST" ]]; then
    [[ -n "$TMT_TEST_NAME" ]] && TEST=$( echo "$TMT_TEST_NAME" | tr '/' '_' | tr ' ' '_' )
    if [[ -z "$TEST" ]]; then
      # If TEST is not set via Makefile, use directory name.
      TEST=$(pwd | awk -F '/' '{print $NF}')
    fi
    syncTEST=$( echo "$TEST" | tr '/' '_' | tr ' ' '_' )
    rlLogInfo "$__syncLogPrefix: Setting syncTEST to $syncTEST"
  fi

  # Checking that the following global variables are not set,
  # They need to be set by the library!
  if [ -n "$syncME" ]; then
    rlLogError "$__syncLogPrefix: Setting syncME is not allowed!"
    return 1
  fi
  if [ -n "$syncOTHER" ]; then
    rlLogError "$__syncLogPrefix: Setting syncOTHER is not allowed!"
    return 1
  fi
  if [ -n "$syncIF" ]; then
    rlLogError "$__syncLogPrefix: Setting syncIF is not allowed!"
    return 1
  fi
  if [ -n "$syncCLIENT" ]; then
    rlLogError "$__syncLogPrefix: Setting syncCLIENT is not allowed!"
    return 1
  fi
  if [ -n "$syncSERVER" ]; then
    rlLogError "$__syncLogPrefix: Setting syncSERVER is not allowed!"
    return 1
  fi

  # gather TMT information about roles
  syncHostRole=()
  while IFS= read -r line; do
    syncHostRole+=( "$line" )
  done < <(declare -p | grep -Eo ' TMT_ROLE_[^=]+=' | sed -r 's/^.{10}//;s/.$//')
  syncHostHostname=()
  syncHostIP=()
  syncHostIPv6=()
  local role host syncHostServerRoleIndex syncHostServerRoleIndex i
  [[ ${#syncHostRole[@]} -eq 1 ]] && {
    # if no TMT roles found use the legacy CLIENTS and SERVERS variables to populate them
    for host in $CLIENTS; do
      syncHostRole+=( "CLIENT" )
      syncHostHostname+=( "$host" )
    done
    for host in $SERVERS; do
      syncHostRole+=( "SERVER" )
      syncHostHostname+=( "$host" )
    done
  }
  for (( i=0; i<${#syncHostRole[@]}; i++)) do
    # find client and server in the roles
    case ${syncHostRole[i]^^} in
      SERVER)
        syncHostServerRoleIndex=$i
      ;;
      CLIENT)
        syncHostClientRoleIndex=$i
      ;;
    esac
    [[ -z "${syncHostHostname[i]}" ]] && {
      # if the hostnames are not know yet, set them from TMT data
      role="TMT_ROLE_${syncHostRole[i]}"
      syncHostHostname[i]="${!role}"
    }
    host="${syncHostHostname[i]}"

    # collect host specific data for each host

    if [[ "${host}" =~ ^[0-9.]+$ ]]; then
      syncHostIP[i]="${host}"
      syncHostIPv6[i]=""
    elif [[ "${host}" =~ ^[0-9A-Fa-f.:]+$ ]]; then
      syncHostIP[i]="${host}"
      syncHostIPv6[i]="${host}"
    else
      # try to resolve hostnames to IPs
      if getent hosts -s files "${host}"; then
        syncHostIP[i]=$( getent hosts -s files "${host}" | awk '{print $1}' | head -1 )
      else
        syncHostIP[i]=$( host "${host}" | sed 's/^.*address\s\+//' | head -1 )
      fi

      # add IPv6 if possible
      if [[ ${syncHostIP[i]} =~ ^[0-9A-Fa-f.:]+$ ]]; then
        # copy to IPv6 if already IPv6
        syncHostIPv6[i]=${syncHostIP[i]}
      else
        # get IPv6 as well
        syncHostIPv6[i]=$( host "${host}" | grep "IPv6" | sed 's/^.*IPv6 address\s\+//' | head -1 )
      fi
    fi
  done

  # reset compatibility variables
  [[ -n "$syncHostServerRoleIndex" ]] && {
    export SERVERS="${syncHostHostname[$syncHostServerRoleIndex]}"
    export syncSERVER="${syncHostIP[$syncHostServerRoleIndex]}"
    export syncSERVER_IP="${syncSERVER}"
    export syncSERVERv6="${syncHostIPv6[$syncHostServerRoleIndex]}"
    export syncSERVER_IPv6="${syncSERVERv6}"
    export syncSERVER_HOSTNAME="${syncHostHostname[$syncHostServerRoleIndex]}"
  }
  [[ -n "$syncHostClientRoleIndex" ]] && {
    export CLIENTS="${syncHostHostname[$syncHostClientRoleIndex]}"
    export syncCLIENT="${syncHostIP[$syncHostClientRoleIndex]}"
    export syncCLIENT_IP="${syncCLIENT}"
    export syncCLIENTv6="${syncHostIPv6[$syncHostClientRoleIndex]}"
    export syncCLIENT_IPv6="${syncCLIENTv6}"
    export syncCLIENT_HOSTNAME="${syncHostHostname[$syncHostClientRoleIndex]}"
  }

  # get default GW interface
  syncIF="$(ip -4 -o route list | grep 'default' | head -1 | sed 's/^.* dev \([^ ]\+\) .*$/\1/')"
  syncIFv6="$(ip -6 -o route list | grep 'default' | head -1 | sed 's/^.* dev \([^ ]\+\) .*$/\1/')"
  if [ -z "$syncIF" ]; then
    rlLogError "${__syncLogPrefix}: Cannot determine NIC for default route!"
    return 1
  else
    rlLogInfo "${__syncLogPrefix}: Setting syncIF to \"${syncIF}\""
    rlLogInfo "${__syncLogPrefix}: Setting syncIFv6 to \"${syncIFv6}\""
  fi

  # Resolving which end of a communication is this host.
  local me4 me6
  me4="$(ip -f inet a s dev "${syncIF}" | grep inet | awk '{ print $2; }' | sed 's/\/.*$//')"
  me6="$(ip -f inet6 a s dev "${syncIFv6}" | grep 'inet6' | grep -v 'scope link' | awk '{ print $2; }' | sed 's/\/.*$//')"
  local meIndex

  for (( i=0; i<${#syncHostRole[@]}; i++ )); do
    [[ "$me4" = "${syncHostIP[i]}" || "$me6" = "${syncHostIPv6[i]}" ]] && {
      meIndex=$i
      break
    }
  done

  if [[ -n "$meIndex" ]]; then
    export syncROLE="${syncHostRole[$meIndex]}"
    export syncME_HOSTNAME="${syncHostHostname[$meIndex]}"
    export syncME="${syncHostIP[$meIndex]}"
    export syncME_IP="${syncME}"
    export syncMEv6="${syncHostIPv6[$meIndex]}"
    export syncME_IPv6="${syncMEv6}"
    syncOTHER=()
    syncOTHER_IP=()
    syncOTHERv6=()
    syncOTHER_IPv6=()
    for (( i=0; i<${#syncHostRole[@]}; i++ )); do
      [[ "$meIndex" != "$i" ]] && {
        syncOTHER_Role+=( "${syncHostRole[i]}" )
        syncOTHER_HOSTNAME+=( "${syncHostHostname[i]}" )
        syncOTHER+=( "${syncHostIP[i]}" )
        syncOTHER_IP+=( "${syncHostIP[i]}" )
        syncOTHERv6+=( "${syncHostIPv6[i]}" )
        syncOTHER_IPv6+=( "${syncHostIPv6[i]}" )
      }
    done
  else
    rlLogError "${__syncLogPrefix}: Cannot determined communication sides!"
    return 1
  fi

  # Ready to go.
  rlLogInfo "${__syncLogPrefix}: Setting syncROLE to \"${syncROLE}\""
  rlLogInfo "${__syncLogPrefix}: Setting syncME to \"${syncME}\""
  rlLogInfo "${__syncLogPrefix}: Setting syncMEv6 to \"${syncMEv6}\""
  rlLogInfo "${__syncLogPrefix}: Setting syncME_HOSTNAME to \"${syncME_HOSTNAME}\""
  rlLogInfo "${__syncLogPrefix}: Setting syncOTHER to ( ${syncOTHER[*]} )"
  rlLogInfo "${__syncLogPrefix}: Setting syncOTHERv6 to ( ${syncOTHERv6[*]} )"
  rlLogInfo "${__syncLogPrefix}: Setting syncOTHER_HOSTNAME to ( ${syncOTHER_HOSTNAME[*]} )"

  # Initial storage clean-up (data related to this execution).
  syncCleanup
  
  rlLogInfo ""
  rlLogInfo "$__syncLogPrefix: CLIENT is $CLIENTS"
  rlLogInfo "$__syncLogPrefix: SERVER is $SERVERS"
  rlLogInfo ""
  rlLogInfo "$__syncLogPrefix: I play role: $syncROLE"

  # ping test
  __syncAvailabilityCheck() {
    local host="$1"
    local prefix="$2"
    if [[ -n "$host" ]]; then
      if ping -c 1 "$host" > /dev/null; then
        rlLogInfo        "$__syncLogPrefix:     ${prefix}... OK"
      else
        rlLogWarning     "$__syncLogPrefix:     ${prefix}... FAIL"
      fi
    else
      rlLogWarning       "$__syncLogPrefix:     ${prefix}... SKIP"
    fi
  }
  rlLogInfo              "$__syncLogPrefix: availability check"
  for (( i=0; i<${#syncOTHER[@]}; i++ )); do
    rlLogInfo            "$__syncLogPrefix:   check host ${syncOTHER[i]} (role: ${syncOTHER_Role[i]})"
    __syncAvailabilityCheck "${syncOTHER[i]}"          "IPv4 ........."
    __syncAvailabilityCheck "${syncOTHERv6[i]}"        "IPv6 ........."
    __syncAvailabilityCheck "${syncOTHER_HOSTNAME[i]}" "hostname ....."
  done

  __syncInstallHelperService || {
    rlLogError "$__syncLogPrefix: count not install the systemd shelper service"
  }

  return 0
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#   Authors
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

true <<'=cut'
=pod

=head1 AUTHORS

=over

=item *

Dalibor Pospisil <dapospis@redhat.com>

=back

=cut
