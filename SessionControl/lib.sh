#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Author: Dalibor Pospisil <dapospis@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2021 Red Hat, Inc.
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
#   library-prefix = session
#   library-version = 6
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
__INTERNAL_session_LIB_NAME="SessionControl"
__INTERNAL_session_LIB_VERSION=6

: <<'=cut'
=pod

=head1 NAME

B<library(SessionControl/basic)>

=head1 DESCRIPTION

A library providing functions to support multiple sessions control.

=head1 VARIABLES

=over

=item B<sessionID>

An array holding currently open session IDs. Sessions are strored from index 1,
index 0 is always used for the "default" B<ID>. The default B<ID> is always reset
to the last used I<ID>.

=item B<sessionRunTIMEOUT>

A default timeout for C<sessionRun>, if defined.

=item B<sessionExpectTIMEOUT>

A default timeout for C<sessionExpect>, if defined.

=back

=head1 FUNCTIONS

=cut

echo -n "loading library $__INTERNAL_session_LIB_NAME v$__INTERNAL_session_LIB_VERSION... "


sessionID=()

: <<'=cut'
=pod

=head2 sessionOpen

Open new session.

    sessionOpen [options]

=head3 options

=over

=item B<--id> I<ID>

If provided the user-specified I<ID> will be used. Othersiwe a numeric I<ID> will be
assigned.

=back

Returns B<0> if successful. See section L</COMMON RESULT CODE> for more details.

=cut

sessionOpen() {
  local ID=0
  while [[ -d "$__INTERNAL_sessionDir/$ID" ]]; do let ID++; done
  while [[ "${1:0:2}" == '--' ]]; do
    case "$1" in
      "--id")
        ID="$2"
        shift 2
        ;;
    esac
  done

  local sessionDir
  sessionDir="$__INTERNAL_sessionDir/$ID"
  # set sessionID index 0 and append to the list
  sessionID="$ID"
  sessionID+=( "$ID" )
  rlLogInfo "opening session $sessionID"
  mkdir -p "$sessionDir"
  mkfifo "$sessionDir/input"
  mkfifo "$sessionDir/output"
  # open session
  $sessionLibraryDir/session.tcl bash "$sessionDir/input" "$sessionDir/output" 2>/dev/null &
  local sessionPID=$!
  disown $sessionPID
  echo $sessionPID > "$sessionDir/pid"
  rlLogInfo "sessionID=$sessionID"
  sessionRun "true"
}


: <<'=cut'
=pod

=head2 sessionRun

Run a command in the B<sessionID[0]> session.

    sessionRun [options] COMMAND

=head3 options

=over

=item B<--id> I<ID>

If provided the B<sessionID[0]> will be set to I<ID>.

=item B<--timeout> I<TIMEOUT>

The command execution time will be limitted to I<TIMEOUT> second(s).

Defaults to I<infinity> (B<-1>) or B<sessionRunTIMEOUT>, if set.


=item I<COMMAND>

The C<COMMAND> to be executed in the B<sessionID[0]>.

Both I<STDOUT> and I<STDERR> of the command will be merged and passed to
I<STDOUT> continuously.

=back

Returns B<0> if successful. See section L</COMMON RESULT CODE> for more details.

=cut

sessionRun() {
  local timeout=${sessionRunTIMEOUT:--1}
  while [[ "${1:0:2}" == '--' ]]; do
    case "$1" in
      "--id")
        sessionID="$2"
        shift 2
        ;;
      "--timeout")
        timeout="$2"
        shift 2
        ;;
    esac
  done
  local sessionDir="$__INTERNAL_sessionDir/$sessionID"
  local rand=$((++__INTERNAL_sessionCount))
  local command="$1"
  sessionRaw - << EOF
    set timeout 10
    set fd_res [open "$sessionDir/result" w]
    set fd_out [open "$sessionDir/output" w]
    send "\\r"
    send {__INTERNAL_session_lastEC=\$?; export PS1="(\\\$?:$rand)> [\\u@\\h]\\\$([[ \\\$UID -eq 0 ]] && echo '#' || echo '\$') "; unset PROMPT_COMMAND; bind 'set enable-bracketed-paste off'; (exit \$__INTERNAL_session_lastEC)}; send "\\r"
    expect -re {\\([0-9]+:${rand}\\)> }
    send "\\r"
    expect -re {\\([0-9]+:${rand}\\)> }
    send {$command}; send "\\r"
    expect -re {\\n}
    set timeout $timeout
    set buf {}
    set printed_length 0
    expect {
      timeout { puts TIMEOUT; set EC 254; }
      eof { puts EOF; close \$fd_out; puts \$fd_res 255; close \$fd_res; exit 255; }
      -re {.+\$} {
        append buf "\${expect_out(buffer)}"
        if { [regexp {(.*?)(\\(([0-9]+):${rand}\\)> )} [string range "\$buf" [expr [string length "\$buf"] - 4096] end] {} prev prmpt EC] } {
          puts -nonewline \$fd_out "[string map {\\r\\n \\n} [string range "\$prev" \$printed_length end]]"
          flush \$fd_out
          set buf "[string range "\$buf" [expr [string length "\$prev"] + [string length "\$prmpt"]] end]"
          set printed_length 0
        } else {
          puts -nonewline \$fd_out "[string map {\\r\\n \\n} \${expect_out(buffer)}]"
          flush \$fd_out
          incr printed_length [string length "\${expect_out(buffer)}"]
          exp_continue -continue_timer
        }
      }
    }
    close \$fd_out
    puts \$fd_res "\$EC"
    close \$fd_res
EOF
  [[ $? -ne 0 ]] && return 255
  cat $sessionDir/output
  return "$(cat $sessionDir/result)"
}


: <<'=cut'
=pod

=head2 sessionExpect

Similarly to an C<expect> script, wait for a I<REG_EXP> pattern appearence
in the B<sessionID[0]> session.

    sessionExpect [options] [regexp_switches] REG_EXP

=head3 options

=over

=item B<--id> I<ID>

If provided the B<sessionID[0]> will be set to I<ID>.

=item B<--timeout> I<TIMEOUT>

The command execution time will be limitted to I<TIMEOUT> second(s).

Defaults to B<120> seconds or B<sessionExpectTIMEOUT>, if set.

=back

=head4 regexp_switches

=over

=item -I<switch>

An option starting with single dash (-) is considered to be a switch to tcl's
regexp. See L<https://www.tcl.tk/man/tcl8.5/TclCmd/regexp.html#M4>.

=item I<REG_EXP>

The pattern to be awaited in the session output.

=back

Both I<STDOUT> and I<STDERR> of the session will be merged and passed to
I<STDOUT> continuously.

Returns B<0> if successful. See section L</COMMON RESULT CODE> for more details.

=cut
#'

sessionExpect() {
  local timeout=${sessionExpectTIMEOUT:-120} regexp_switches
  while [[ "${1:0:1}" == '-' ]]; do
    case "$1" in
      "--id")
        sessionID="$2"
        shift
        ;;
      "--timeout")
        timeout="$2"
        shift
        ;;
      -start)
        regexp_switches+=" $1 $2"
        shift
        ;;
      -*)
        regexp_switches+=" $1"
        ;;
    esac
    shift
  done
  local sessionDir="$__INTERNAL_sessionDir/$sessionID"
  local pattern="$1"
  sessionRaw - << EOF
    set EC 0
    set fd_res [open "$sessionDir/result" w]
    set fd_out [open "$sessionDir/output" w]
    set timeout $timeout

    # process buffer by regexp matching
    proc process {{el ""}} {
      set res 1
      if { [uplevel {regexp $regexp_switches -- {(^.*?$pattern)} [string range "\$buf" [expr [string length "\$buf"] - 4096] end] {} prev}] } {
        uplevel {
          puts -nonewline \$fd_out "[string map {\\r\\n \\n} [string range "\$prev" \$printed_length end]]"
          flush \$fd_out
          set buf "[string range "\$buf" [string length "\$prev"] end]"
          set printed_length 0
        }
        set res 0
      } else {uplevel \$el}
      return \$res
    }
    # if the buffer did not contains the required data already we need to wait for it
    if { [process] } {
      expect {
        timeout { puts TIMEOUT; set EC 254; }
        eof { puts EOF; close \$fd_out; puts \$fd_res 255; close \$fd_res; exit 255; }
        -re {.+\$} {
          append buf "\${expect_out(buffer)}"
          process {
            puts -nonewline \$fd_out "[string map {\\r\\n \\n} \${expect_out(buffer)}]"
            flush \$fd_out
            incr printed_length [string length "\${expect_out(buffer)}"]
            after 250
            exp_continue -continue_timer
          }
        }
      }
    }
    close \$fd_out
    puts \$fd_res "\$EC"
    close \$fd_res
EOF
  [[ $? -ne 0 ]] && return 1
  cat $sessionDir/output
  return "$(cat $sessionDir/result)"
}


: <<'=cut'
=pod

=head2 sessionSend

Similarly to an C<expect> script, send an I<INPUT> to the B<sessionID[0]> session.

    sessionSend [options] INPUT

=head3 options

=over

=item B<--id> I<ID>

If provided the B<sessionID[0]> will be set to I<ID>.

=item I<INPUT>

The input to be send to the session. It may contain also control characters,
e.g. B<\003> to send break (^C).

Note, to execute a command using C<sessionSend> you need to append B<\r> to confirm
it on the prompt.

=back

Returns B<0> if successful.

=cut

sessionSend() {
  while [[ "${1:0:2}" == '--' ]]; do
    case "$1" in
      "--id")
        sessionID="$2"
        shift 2
        ;;
    esac
  done
  local sessionDir="$__INTERNAL_sessionDir/$sessionID"
  local command="$1"
  sessionRaw - << EOF
    send {$command}
EOF
  #[[ $? -ne 0 ]] && return 1
}


: <<'=cut'
=pod

=head2 sessionWaitAPrompt

Wait a prompt to appear in the B<sessionID[0]> session.

    sessionWaitAPrompt [options]

=head3 options

=over

=item B<--id> I<ID>

If provided the B<sessionID[0]> will be set to I<ID>.

=back

Returns B<0> if successful.

=cut

sessionWaitAPrompt() {
  sessionExpect "$@" '\([0-9]+:[0-9]+\)> '
}


: <<'=cut'
=pod

=head2 sessionRaw

Send raw expect code the session handling daemon.

    sessionRaw [options] CODE

=head3 options

=over

=item B<--id> I<ID>

If provided the B<sessionID[0]> will be set to I<ID>.

=item I<CODE>

The code to be executed in the session handling expect daemon.

If C<-> is passed, the code will be read from I<STDIN>.

=back

Returns B<0> if successful. See section L</COMMON RESULT CODE> for more details.

=cut

sessionRaw() {
  [[ "$1" == "--id" ]] && {
    sessionID="$2"
    shift 2
  }
  local command="$1"
  local sessionDir="$__INTERNAL_sessionDir/$sessionID"
  kill -n 0 "$(<$sessionDir/pid)" > /dev/null 2>&1 || {
    rlLogError "session $ID is not open"
    return 255
  }
  if [[ "$command" == "-" ]]; then
    command="$(cat -)"
  fi
  [[ -n "$DEBUG" ]] && { rlLogDebug "ID=$sessionID, command="; echo "$command"; }
  [[ -z "$DEBUG" ]] && command='log_user 0'$'\n'"$command"$'\n'"log_user 1"
  cat > $sessionDir/input <<< "$command"
}


: <<'=cut'
=pod

=head2 sessionClose

Close the opened session B<sessionID[0]>.

    sessionClose [options]

=head3 options

=over

=item B<--id> I<ID>

If provided the B<sessionID[0]> will be set to I<ID>.

=back

Returns B<0> if successful. See section L</COMMON RESULT CODE> for more details.

=cut

sessionClose() {
  local id
  [[ "$1" == "--id" ]] && {
    sessionID="$2"
    shift 2
  }
  local command="$1"
  local sessionDir="$__INTERNAL_sessionDir/$sessionID"
  kill -n 0 "$(<$sessionDir/pid)" > /dev/null 2>&1 || {
    rlLogInfo "session $ID is not open"
    return 0
  }
  rlLogInfo "closing session $sessionID"
  sessionRaw 'exit'
  kill "$(<$sessionDir/pid)" > /dev/null 2>&1
  sleep 0.25
  kill -s 0 "$(<$sessionDir/pid)" > /dev/null 2>&1 || {
    rm -rf "$sessionDir"
  }
}


: <<'=cut'
=pod

=head2 sessionCleanup

Close all the remaining open sessions.

    sessionCleanup

Returns B<0> if successful. See section L</COMMON RESULT CODE> for more details.

=cut

sessionCleanup() {
  local id
  [[ -z "$__INTERNAL_sessionDir" ]] && {
    rlLogError 'Sessions dir is not set'
    retrun 1
  }
  for id in $__INTERNAL_sessionDir/*; do
    sessionClose --id "$(basename $id)"
  done
}


# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#   Verification
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   This is a verification callback which will be called by
#   rlImport after sourcing the library to make sure everything is
#   all right. It makes sense to perform a basic sanity test and
#   check that all required packages are installed. The function
#   should return 0 only when the library is ready to serve.

sessionLibraryLoaded() {

  echo -n "initiating library $__INTERNAL_session_LIB_NAME v$__INTERNAL_session_LIB_VERSION... "
  if ! egrep -qi '(vmx|svm|PowerNV)' /proc/cpuinfo; then
    rlLogError "Your CPU doesn't support VMX/SVM/PowerNV"
  fi

  if ! command -v expect >/dev/null 2>&1; then
    rlLogError "expect command is required!"
    res=1
  fi

  __INTERNAL_sessionDir="$BEAKERLIB_DIR/sessions"
  mkdir -p "$__INTERNAL_sessionDir"
  rm -rf "${__INTERNAL_sessionDir:?}/*"
  echo "done."
  return $res
}


# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#   Authors
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

: <<'=cut'
=pod

=head1 COMMON RESULT CODE

There are special I<RETURN CODES> coming from the library's functions.

=over

=item B<255>

The session ended unexpectedly. Any further interactions with the session will
end with an error.

=item B<254>

The session call timed out. There may be a I<command> hanging or a I<pattern> was
not found in time.

=item B<<254>

These return codes are typically coming from the executed command.

=item B<0>

Success!

=back

=head1 EXAMPLES

Simply run C<whoami> command in a session

    sessionOpen
    sessionRun "id"
    sessionClose

Run commands in two sessions

    sessionOpen
    sessionOpen
    sessionRun --id ${sessionID[1]} "whoami"
    sessionRun --id ${sessionID[2]} "whoami"
    sessionRun "whoami"                   # run in sessionID[2] as it was the last one used
    sessionClose --id ${sessionID[1]}
    sessionClose --id ${sessionID[2]}

    sessionOpen --id A
    sessionOpen --id B
    sessionRun --id A "whoami"
    sessionRun --id B "whoami"
    sessionRun "whoami"                   # run in B as it was the last one used
    sessionID=A                           # equal to sessionID[0]=A
    sessionRun "whoami"                   # run in A
    sessionClose --id A
    sessionClose --id B

Run command on remote machines

    sessionOpen --id server
    sessionOpen --id client
  # note, we need to let ssh execution to timeout as the ssh command actually
  # does not finish, it will stay waiting for the password and the remote prompt
    sessionRun --id server --timeout 1 "ssh UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no root@server.example.com"
    sessionExpect "[Pp]assword"
    sessionSend "PASSWORD"$'\r'
    sessionRun --id client --timeout 1 "ssh UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no root@client.example.com"
    sessionExpect "[Pp]assword"
    sessionSend "PASSWORD"$'\r'
  # check we are on the remote
    rlRun -s 'sessionRun --id server "hostname -f"'
    rlAssertGrep 'server.example.com' $rlRun_LOG
    rm -f $rlRun_LOG
    rlRun -s 'sessionRun --id client "hostname -f"'
    rlAssertGrep 'client.example.com' $rlRun_LOG
    rm -f $rlRun_LOG
  # optionally exit from ssh connections
  # note, we need to let this execution to timeout as well as we are basically
  # returning from the remote prompt to the local prompt - the one from
  # the previousely timed out ssh execution
  # alternatively one could do this by issuing sessionSend "exit"$'\r'
    sessionRun --id server --timeout 1 "exit"
    sessionRun --id client --timeout 1 "exit"
    sessionClose --id server
    sessionClose --id client


=head1 FILES

=over

=item F<session.tcl>

The daemon forked to handle each session.

=back

=head1 AUTHORS

=over

=item *

Dalibor Pospisil <dapospis@redhat.com>

=back

=cut

echo "done."
