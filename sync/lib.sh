#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   lib.sh of /distribution/Library/sync
#   Description: A multihost synchronization library
#   Authors: Dalibor Pospisil <dapospis@redhat.com>
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
#   library-version = 4
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Synchronization counter.
syncCOUNT=0

# Pattern for valid filename representing flag.
syncFLAG_PATTERN="a-zA-Z0-9._-"

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

=item syncNAME (set automatically)

A name in a mutual communication played by the actual machine, e.g.
CLIENT or SERVER.

=item syncROLE (set automatically)

A role in a mutual communication played by the actual machine, e.g.
CLIENT or SERVER.

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
[[ -n "$TMT_PLAN_DATA" ]] && {
  __syncSHARE="$TMT_PLAN_DATA/../execute/data/syncMultihost"
}

__syncDownload() {
  [[ "$1" =~ ([^ ]+)\ (([^/]*)/.*) ]] || return 1
  __syncFoundOnHost="${BASH_REMATCH[1]}"
  __syncFoundRaisedByHost="${BASH_REMATCH[3]}"
  local flag
  flag="${BASH_REMATCH[2]}"
  rlLogDebug "${FUNCNAME[0]}(): downloading flag $flag raised by $__syncFoundRaisedByHost from host $__syncFoundOnHost"
  if [[ -n "$DEBUG" ]]; then
    echo -e "get\n$flag" | nc --no-shutdown "$__syncFoundOnHost" "$syncPort" | tee /dev/stderr
  else
    echo -e "get\n$flag" | nc --no-shutdown "$__syncFoundOnHost" "$syncPort" 2> /dev/null
  fi
}

__syncList() {
  local host hosts
  [[ -n "$syncServerHost" ]] && {
    hosts=( "${syncServerHost}" )
  } || {
    hosts=( "${syncHostIP[@]}" )
  }

  for host in "${hosts[@]}"; do
    rlLogDebug "${FUNCNAME[0]}(): listing flags published on host $host"
    if [[ -n "$DEBUG" ]]; then
      echo "list" | nc --no-shutdown "$host" "$syncPort" | sed -r "s/^/$host /" | tee /dev/stderr
    else
      echo "list" | nc --no-shutdown "$host" "$syncPort" | sed -r "s/^/$host /" 2> /dev/null
    fi
  done
}

__syncGet() {
  if [[ -z "$1" ]]; then
    rlLogError "${__syncLogPrefix}: Missing flag specification!"
    return 2
  fi
  local flag host i
  flag="$1"
  shift
  host=''
  while [[ -n "$1" ]]; do
    host+="|$1"
    shift
  done
  [[ -z "$host" ]] && for i in "${syncOTHER[@]}"; do
    host+="|$i"
  done
  host="(${host:1})"

  rlLogDebug "${FUNCNAME[0]}(): $syncNAME is checking the flag $flag on hosts $host"
  local rc=0 found
  found=$(__syncList | grep -Em1 " ${host}/${syncXTRA}_${syncTEST}/${flag}$" ) \
    && __syncDownload "${found}" \
      || rc=1

  return $rc
}

__syncSet() {
  local flag_name flag_file res flag_file
  res=0
  flag_name="$1"
  flag_file="${syncME}/${syncXTRA}_${syncTEST}/${flag_name}"
  flag_path="${__syncSHARE}/${flag_file}"

  if [[ -z "$syncServerHost" ]]; then
    # distributed flags publishing
    rlLogDebug "${FUNCNAME[0]}(): make sure the path is available"
    mkdir -p "$(dirname "$flag_path")" || ((res++))

    rlLogDebug "${FUNCNAME[0]}(): create the flag file temporary file"
    cat - > "${flag_path}.partial" || ((res++))

    rlLogDebug "${FUNCNAME[0]}(): move to the final flag file"
    mv -f "${flag_path}.partial" "${flag_path}" || ((res++))
  else
    # centralized flags publishing on syncServerHost
    (
      echo -e "put\n${flag_file}"
      cat -
    ) | nc "$syncServerHost" "$syncPort"
  fi

  return $res
}

__syncInstallNcatHelperService() {
  cat > /etc/systemd/system/syncHelper.service <<EOF
[Unit]
Description=a multihost ncat synchronization helper service
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/nc -k -l $syncPort -c '\
  read -r line; \
  if [[ "\$line" == "list" ]]; then \
    find "$__syncSHARE" -mindepth 2 -type f | sed -r "s#$__syncSHARE/##"; \
  elif [[ "\$line" == "get" ]]; then \
    read -r flag \
    && cat "$__syncSHARE/\$flag"; \
  elif [[ "\$line" == "put" ]]; then \
    read -r flag \
    && mkdir -p "$__syncSHARE/\$(dirname "\$flag")" \
    && cat - > "$__syncSHARE/\$flag.partial" \
    && mv -f "$__syncSHARE/\$flag.partial" "$__syncSHARE/\$flag"; \
  else \
    echo "unknown request"; \
  fi \
'

Restart=always
RestartSec=5s

[Install]
WantedBy=default.target
EOF
}

__syncInstallHelperService() {
  rlLogDebug "$FUNCNAME(): installing syncHelper service"
  mkdir -p "$__syncSHARE"
  __syncInstallNcatHelperService
  local zones
  if zones=$(firewall-cmd --get-zones 2> /dev/null); then
    for zone in $zones; do
      firewall-cmd --zone="$zone" --add-port=2134/tcp
    done
  elif zones=$(firewall-offline-cmd --get-zones 2> /dev/null); then
    for zone in $zones; do
      firewall-offline-cmd --zone="$zone" --add-port=2134/tcp > /dev/null 2>&1
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
  [[ -n "${__syncSHARE}" && -e "${__syncSHARE}" ]] && {
    rlLogInfo "${__syncLogPrefix}: $syncNAME clears all its data older than 2 days"
    find "${__syncSHARE}" -mindepth 1 -ctime +1 -delete
  }
  rm -rf /tmp/syncBreak /tmp/syncSet
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
  syncSet "__SYNC_${syncCOUNT}__" || let res++
  local host
  # wait for all others to raise their flags as well
  rlLogDebug "$FUNCNAME(): check hosts ${syncOTHER[*]}"
  for host in "${syncOTHER[@]}"; do
    syncExp "__SYNC_${syncCOUNT}__" "${host}" || let res++
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

  if ! [[ "$1" =~ ^[${syncFLAG_PATTERN}]*$ ]]; then
    rlLogError "${__syncLogPrefix}: Incorrect flag (must match ^[${syncFLAG_PATTERN}]*$)!"
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
      rlLogInfo "${__syncLogPrefix}: $syncNAME set flag $1 with a content"
    fi
  elif [ -n "$2" ]; then
    echo -n "$2" | __syncSet "$1"
    if [ $? -ne 0 ]; then
      rlLogError "${__syncLogPrefix}: Cannot write flag!"
      rc=3
    else
      rlLogInfo "${__syncLogPrefix}: $syncNAME set flag $1 with message \"$2\""
    fi
  else
    rlLogInfo "${__syncLogPrefix}: $syncNAME set flag $1"
    echo -n '' | __syncSet "$1"
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
  local rc=0 __syncFoundOnHost
  local flag="$1"
  shift

  if [[ -z "$flag" ]]; then
    rlLogError "${__syncLogPrefix}: Missing flag!"
    return 2
  fi

  if ! [[ "$flag" =~ ^[${syncFLAG_PATTERN}]*$ ]]; then
    rlLogError "${__syncLogPrefix}: Incorrect flag (must match ^[${syncFLAG_PATTERN}]*$)!"
    return 2
  fi

  if [[ $# -eq 0 ]]; then
    rlLogInfo "${__syncLogPrefix}: $syncNAME is waiting for flag $flag raised by any other host"
  else
    rlLogInfo "${__syncLogPrefix}: $syncNAME is waiting for flag $flag raised by host(s): $*"
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
    rlLogInfo "${__syncLogPrefix}: $syncNAME found flag $flag raised by host $__syncFoundRaisedByHost on host $__syncFoundOnHost"
    if [[ -s "$matchedfile" ]]; then
      local message
      message=$(head -c 10 "$matchedfile")
      if [[ "$message" == "S_T_D_I_N:" ]]; then
        rlLogInfo "${__syncLogPrefix}: $syncNAME got flag $flag with a content"
        tail -c +11 "$matchedfile"
      else
        message=$(cat "$matchedfile")
        if [[ -z "$message" ]]; then
          rlLogInfo "${__syncLogPrefix}: $syncNAME got pure flag $flag"
        else
          rlLogInfo "${__syncLogPrefix}: $syncNAME got flag $flag with message \"$message\""
        fi
        echo "$message"
      fi
    else
      rlLogInfo "${__syncLogPrefix}: $syncNAME got flag $flag"
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

  if ! [[ "$1" =~ ^[${syncFLAG_PATTERN}]*$ ]]; then
    rlLogError "${__syncLogPrefix}: Incorrect flag (must match ^[${syncFLAG_PATTERN}]*$)!"
    return 2
  fi

  local file
  file="/tmp/syncSet"
  rlLogInfo "${__syncLogPrefix}: $syncNAME is checking flag $1"
  if __syncGet "$1" > "$file"; then
    if [[ -s "$file" ]]; then
      local message
      message=$(head -c 10 "$file")
      if [[ "$message" == "S_T_D_I_N:" ]]; then
        rlLogInfo "${__syncLogPrefix}: $syncNAME got flag $1 with a content"
        tail -c +11 "$file"
      else
        message=$(cat "$file")
        rlLogInfo "${__syncLogPrefix}: $syncNAME got flag $1 with message \"$message\""
        echo "$message"
      fi
    else
      rlLogInfo "${__syncLogPrefix}: $syncNAME got flag $1"
    fi
  else
    rlLogInfo "${__syncLogPrefix}: $syncNAME did not get flag $1"
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
  local host res
  # wait for all others to raise their flags as well
  for host in "${syncOTHER[@]}"; do
    [[ "$(syncExp "$resultFlag" "${host}")" == "0" ]] || { let res++; break; }
  done
  return $res
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#   Initialization & Verification
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   This is an initialization and verification callback which will
#   be called by rlImport after sourcing the library. The function
#   returns 0 only when the library is ready to serve.

syncLibraryLoaded() {
  rlLogDebug "$__syncLogPrefix: Using $__syncSHARE folder for the sync data"

  # Setting defaults for optional global variables.
  [[ -z "$syncSLEEP" ]] && syncSLEEP=5
  rlLogInfo "$__syncLogPrefix: Setting syncSLEEP to $syncSLEEP seconds"

  [[ -z "$syncTIMEOUT" ]] && syncTIMEOUT=7200
  rlLogInfo "$__syncLogPrefix: Setting syncTIMEOUT to $syncTIMEOUT seconds"

  if [[ -z "$syncTEST" ]]; then
    [[ -n "$TMT_TEST_NAME" ]] && TEST="$TMT_TEST_NAME"
    if [[ -z "$TEST" ]]; then
      # If TEST is not set via Makefile, use directory name.
      TEST=$(pwd | awk -F '/' '{print $NF}')
    fi
    syncTEST=$( echo "$TEST" | sed -r "s/[^$syncFLAG_PATTERN]/_/g;s/_+/_/g" )
    rlLogInfo "$__syncLogPrefix: Setting syncTEST to $syncTEST"
  fi

  syncXTRA=$XTRA
  if [ -z "$syncXTRA" ] && [ -n "$TMT_TREE" ] && [ -n "$TMT_TEST_SERIAL_NUMBER" ]; then
    syncXTRA="$(echo $TMT_TREE | sed 's#^.*/run-\([0-9]*\)/.*#\1#')-$TMT_TEST_SERIAL_NUMBER"
  fi

  rlLogInfo "$__syncLogPrefix: Setting syncXTRA to $syncXTRA"

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
  [[ -n "$TMT_TOPOLOGY_BASH" && -s "$TMT_TOPOLOGY_BASH" ]] && . "$TMT_TOPOLOGY_BASH"
  syncHostName=( $TMT_GUEST_NAMES )
  syncHostRole=()
  syncHostHostname=()
  syncHost=()
  syncHostIP=()
  syncHostIPv6=()
  local name role host syncHostServerRoleIndex syncHostServerRoleIndex i
  [[ ${#syncHostName[@]} -eq 0 ]] && {
    # if no TMT roles found use the legacy CLIENTS and SERVERS variables to populate them
    for host in $CLIENTS; do
      syncHostRole+=( "CLIENT" )
      syncHostName+=( "client" )
      syncHostHostname+=( "$host" )
    done
    for host in $SERVERS; do
      syncHostRole+=( "SERVER" )
      syncHostName+=( "server" )
      syncHostHostname+=( "$host" )
    done
  }
  for (( i=0; i<${#syncHostName[@]}; i++)) do
    [[ -z "${syncHostHostname[i]}" ]] && {
      # if the hostnames are not know yet, set them from TMT data
      # TMT_ROLES[server]="default-0"
      # TMT_GUESTS[default-0.hostname]
      syncHostHostname[i]="${TMT_GUESTS[${syncHostName[i]}.hostname]}"
      syncHostRole[i]="${TMT_GUESTS[${syncHostName[i]}.role]}"
    }
    name="${syncHostName[i]}"
    role="${syncHostRole[i]}"
    host="${syncHostHostname[i]}"
    # find client and server in the roles
    case ,${role^^},${name^^}, in
      *,SERVER,*)
        syncHostServerRoleIndex=$i
      ;;
      *,CLIENT,*)
        syncHostClientRoleIndex=$i
      ;;
    esac

    # collect host specific data for each host

    if [[ "${host}" =~ ^[0-9.]+$ ]]; then
      syncHost[i]="${host}"
      syncHostIP[i]="${host}"
      syncHostIPv6[i]=""
    elif [[ "${host}" =~ ^[0-9A-Fa-f:]+$ ]]; then
      syncHost[i]="${host}"
      syncHostIP[i]=""
      syncHostIPv6[i]="${host}"
    else
      # try to resolve hostnames to IPs
      if getent hosts -s files "${host}"; then
        syncHost[i]=$( getent hosts -s files "${host}" | awk '{print $1}' | head -1 )
      else
        syncHost[i]=$( host "${host}" | sed 's/^.*address\s\+//' | head -1 )
      fi

      # add IPv4 if possible
      if [[ "${syncHost[i]}" =~ ^[0-9.]+$ ]]; then
        syncHostIP[i]="${syncHost[i]}"
      # add IPv6 if possible
      elif [[ "${syncHostIP[i]}" =~ ^[0-9A-Fa-f:]+$ ]]; then
        # copy to IPv6 if already IPv6
        syncHostIPv6[i]="${syncHost[i]}"
      else
        # get IPv6 as well
        syncHostIPv6[i]=$( host "${host}" | grep "IPv6" | sed 's/^.*IPv6 address\s\+//' | head -1 )
      fi
    fi
    [[ "$syncServerName" == "${name}" ]] && syncServerHost=${syncHost[i]}
  done

  # reset compatibility variables
  [[ -n "$syncHostServerRoleIndex" ]] && {
    export SERVERS="${syncHostHostname[$syncHostServerRoleIndex]}"
    export syncSERVER="${syncHost[$syncHostServerRoleIndex]}"
    export syncSERVER_IP="${syncHostIP[$syncHostServerRoleIndex]}"
    export syncSERVERv6="${syncHostIPv6[$syncHostServerRoleIndex]}"
    export syncSERVER_IPv6="${syncSERVERv6}"
    export syncSERVER_HOSTNAME="${syncHostHostname[$syncHostServerRoleIndex]}"
  }
  [[ -n "$syncHostClientRoleIndex" ]] && {
    export CLIENTS="${syncHostHostname[$syncHostClientRoleIndex]}"
    export syncCLIENT="${syncHost[$syncHostClientRoleIndex]}"
    export syncCLIENT_IP="${syncHostIP[$syncHostClientRoleIndex]}"
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

  for (( i=0; i<${#syncHostName[@]}; i++ )); do
    [[ "$me4" = "${syncHostIP[i]}" || "$me6" = "${syncHostIPv6[i]}" ]] && {
      meIndex=$i
      break
    }
  done

  if [[ -n "$meIndex" ]]; then
    export syncNAME="${syncHostName[$meIndex]}"
    export syncROLE="${syncHostRole[$meIndex]}"
    export syncME_HOSTNAME="${syncHostHostname[$meIndex]}"
    export syncME="${syncHost[$meIndex]}"
    export syncME_IP="${syncHostIP[$meIndex]}"
    export syncMEv6="${syncHostIPv6[$meIndex]}"
    export syncME_IPv6="${syncMEv6}"
    syncOTHER=()
    syncOTHER_IP=()
    syncOTHERv6=()
    syncOTHER_IPv6=()
    for (( i=0; i<${#syncHostName[@]}; i++ )); do
      [[ "$meIndex" != "$i" ]] && {
        syncOTHER_NAME+=( "${syncHostName[i]}" )
        syncOTHER_ROLE+=( "${syncHostRole[i]}" )
        syncOTHER_HOSTNAME+=( "${syncHostHostname[i]}" )
        syncOTHER+=( "${syncHost[i]}" )
        syncOTHER_IP+=( "${syncHostIP[i]}" )
        syncOTHERv6+=( "${syncHostIPv6[i]}" )
        syncOTHER_IPv6+=( "${syncHostIPv6[i]}" )
      }
    done
  else
    rlLogError "${__syncLogPrefix}: Cannot determined communication sides!"
    declare -p syncHostRole syncHostHostname syncHostIP syncHostIPv6
    cat "$TMT_TOPOLOGY_BASH"
    return 1
  fi

  # Ready to go.
  rlLogInfo "${__syncLogPrefix}: Setting syncNAME to \"${syncROLE}\""
  rlLogInfo "${__syncLogPrefix}: Setting syncROLE to \"${syncROLE}\""
  rlLogInfo "${__syncLogPrefix}: Setting syncME to \"${syncME}\""
  rlLogInfo "${__syncLogPrefix}: Setting syncME_IP to \"${syncME_IP}\""
  rlLogInfo "${__syncLogPrefix}: Setting syncMEv6 to \"${syncMEv6}\""
  rlLogInfo "${__syncLogPrefix}: Setting syncME_IPv6 to \"${syncME_IPv6}\""
  rlLogInfo "${__syncLogPrefix}: Setting syncME_HOSTNAME to \"${syncME_HOSTNAME}\""
  rlLogInfo "${__syncLogPrefix}: Setting syncOTHER_NAME to ( $( for i in "${syncOTHER_NAME[@]}"; do echo -n "\"$i\" "; done ))"
  rlLogInfo "${__syncLogPrefix}: Setting syncOTHER_ROLE to ( $( for i in "${syncOTHER_ROLE[@]}"; do echo -n "\"$i\" "; done ))"
  rlLogInfo "${__syncLogPrefix}: Setting syncOTHER to ( $( for i in "${syncOTHER[@]}"; do echo -n "\"$i\" "; done ))"
  rlLogInfo "${__syncLogPrefix}: Setting syncOTHER_IP to ( $( for i in "${syncOTHER_IP[@]}"; do echo -n "\"$i\" "; done ))"
  rlLogInfo "${__syncLogPrefix}: Setting syncOTHERv6 to ( $( for i in "${syncOTHERv6[@]}"; do echo -n "\"$i\" "; done ))"
  rlLogInfo "${__syncLogPrefix}: Setting syncOTHER_IPv6 to ( $( for i in "${syncOTHER_IPv6[@]}"; do echo -n "\"$i\" "; done ))"
  rlLogInfo "${__syncLogPrefix}: Setting syncOTHER_HOSTNAME to ( $( for i in "${syncOTHER_HOSTNAME[@]}"; do echo -n "\"$i\" "; done ))"
  [[ -n "$syncServerHost" ]] && {
    rlLogInfo "${__syncLogPrefix}: Running in centralized mode, all flags are published on a sync server \"${syncServerHost}\""
  } || {
    rlLogInfo "${__syncLogPrefix}: Running in distributed mode, each host publishes its own flags"
  }


  # Initial storage clean-up (data related to this execution).
  syncCleanup
  
  rlLogInfo ""
  rlLogInfo "$__syncLogPrefix: CLIENT is $CLIENTS"
  rlLogInfo "$__syncLogPrefix: SERVER is $SERVERS"
  rlLogInfo ""
  rlLogInfo "$__syncLogPrefix: I '$syncNAME' am playing a role $syncROLE"

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
    rlLogInfo            "$__syncLogPrefix:   check host ${syncOTHER[i]} (name: ${syncOTHER_NAME[i]}, role: ${syncOTHER_ROLE[i]})"
    __syncAvailabilityCheck "${syncOTHER[i]}"          "IPv4 ........."
    __syncAvailabilityCheck "${syncOTHERv6[i]}"        "IPv6 ........."
    __syncAvailabilityCheck "${syncOTHER_HOSTNAME[i]}" "hostname ....."
  done

  [[ -z "$syncServerHost" || "$syncServerHost" == "$syncME" ]] && {
    __syncInstallHelperService \
    || rlLogError "$__syncLogPrefix: count not install the systemd shelper service"
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
