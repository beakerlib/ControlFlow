#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   lib.sh of session
#   Description: What the test does
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
#   library-prefix = ses
#   library-version = 1
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
__INTERNAL_ses_LIB_NAME="SessionControl"
__INTERNAL_ses_LIB_VERSION=1

: <<'=cut'
=pod

=head1 NAME

ses/basic

=head1 DESCRIPTION

A library providing functions to support multiple sessions control.

=head1 VARIABLES

=over

=item B<sesID>

An array holding currently open session IDs. Sessions are strored from index 1,
index 0 is always used for the "default" B<ID>. The default B<ID> always the last
used I<ID>.

=back

=head1 FUNCTIONS

=cut

echo -n "loading library $__INTERNAL_ses_LIB_NAME v$__INTERNAL_ses_LIB_VERSION... "


sesID=()

: <<'=cut'
=pod

=head2 sesOpen

Open new session.

    sesOpen [options]

=head3 options

=over

=item B<--id> I<ID>

If provided the user-specified I<ID> will be used. Othersiwe a numeric I<ID> will be
assigned.

=back

Returns I<0> if successful. See section L<COMMON RESULT CODE|/"COMMON RESULT CODE"> for more details.

=cut

sesOpen() {
  local ID=0
  while [[ -d "$__INTERNAL_sesDir/$ID" ]]; do let ID++; done
  while [[ "${1:0:2}" == '--' ]]; do
    case "$1" in
      "--id")
        ID="$2"
        shift 2
        ;;
    esac
  done

  local sesDir
  sesDir="$__INTERNAL_sesDir/$ID"
  # set sesID index 0 and append to the list
  sesID="$ID"
  sesID+=( "$ID" )
  rlLogInfo "opening session $sesID"
  mkdir -p "$sesDir"
  mkfifo "$sesDir/input"
  mkfifo "$sesDir/output"
  # open session
  $sesLibraryDir/ses.tcl bash "$sesDir/input" "$sesDir/output" 2>/dev/null &
  local sesPID=$!
  disown $sesPID
  echo $sesPID > "$sesDir/pid"
  rlLogInfo "sesID=$sesID"
  sesRaw - << EOF
    set buf {}
    set printed_length 0
EOF
}


: <<'=cut'
=pod

=head2 sesRun

Run a command in the B<sesID[0]> session.

    sesRun [options] COMMAND

=head3 options

=over

=item B<--id> I<ID>

If provided the B<sesID[0]> will be set to I<ID>.

=item B<--timeout> I<TIMEOUT>

The command execution time will be limitted to I<TIMEOUT> second(s).
Defaults to I<infinity>.

=item I<COMMAND>

The C<COMMAND> to be executed in the B<sesID[0]>.

Both I<STDOUT> and I<STDERR> of the command will be merged and passed to
I<STDOUT> continuously.

=back

Returns I<0> if successful. See section L<COMMON RESULT CODE|/"COMMON RESULT CODE"> for more details.

=cut

sesRun() {
  local timeout=-1
  while [[ "${1:0:2}" == '--' ]]; do
    case "$1" in
      "--id")
        sesID="$2"
        shift 2
        ;;
      "--timeout")
        timeout="$2"
        shift 2
        ;;
    esac
  done
  local sesDir="$__INTERNAL_sesDir/$sesID"
  local rand=$((++__INTERNAL_sesCount))
  local command="$1"
  sesRaw - << EOF
    set timeout 10
    set fd_res [open "$sesDir/result" w]
    set fd_out [open "$sesDir/output" w]
    send "\\r"
    send {PS1="(\\\$?:$rand)> [\\u@\\h]\\\$([[ \\\$UID -eq 0 ]] && echo '#' || echo '\$') "}; send "\\r"
    expect -re {\\([0-9]+:${rand}\\)> }
    send "\\r"
    expect -re {\\([0-9]+:${rand}\\)> }
    send {$command}; send "\\r"
    expect -re {\\n}
    set timeout $timeout
    set buf {}
    expect {
      timeout { puts TIMEOUT; set EC 254; }
      eof { puts EOF; close \$fd_out; puts \$fd_res 255; close \$fd_res; exit 255; }
      -re {.+\$} {
        append buf "\${expect_out(buffer)}"
        if { [regexp {(.*?)\\(([0-9]+):${rand}\\)> } "\$buf" {} prev EC] } {
          puts -nonewline \$fd_out "[string range "\$prev" \$printed_length end]"
          flush \$fd_out
          set buf "[string range "\$buf" [string length "\$prev"] end]"
          set printed_length 0
        } else {
          puts -nonewline \$fd_out "\${expect_out(buffer)}"
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
  cat $sesDir/output
  return "$(cat $sesDir/result)"
}


: <<'=cut'
=pod

=head2 sesExpect

Similarly to an C<expect> script, wait for a I<REG_EXP> pattern appearence
in the B<sesID[0]> session.

    sesExpect [options] REG_EXP

=head3 options

=over

=item B<--id> I<ID>

If provided the B<sesID[0]> will be set to I<ID>.

=item B<--timeout> I<TIMEOUT>

The command execution time will be limitted to I<TIMEOUT> second(s).
Defaults to 120 seconds.

=item I<REG_EXP>

The pattern to be awaited in the session output.

=back

Both I<STDOUT> and I<STDERR> of the session will be merged and passed to
I<STDOUT> continuously.

Returns I<0> if successful. See section L<COMMON RESULT CODE|/"COMMON RESULT CODE"> for more details.

=cut

sesExpect() {
  local timeout=120
  while [[ "${1:0:2}" == '--' ]]; do
    case "$1" in
      "--id")
        sesID="$2"
        shift 2
        ;;
      "--timeout")
        timeout="$2"
        shift 2
        ;;
    esac
  done
  local sesDir="$__INTERNAL_sesDir/$sesID"
  local pattern="$1"
  sesRaw - << EOF
    set EC 0
    set fd_res [open "$sesDir/result" w]
    set fd_out [open "$sesDir/output" w]
    set timeout $timeout

    # process buffer by regexp matching
    proc process {{el ""}} {
      set res 1
      if { [uplevel {regexp {(^.*?$pattern)} "\$buf" {} prev}] } {
        uplevel {
          puts -nonewline \$fd_out "[string range "\$prev" \$printed_length end]"
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
            puts -nonewline \$fd_out "\${expect_out(buffer)}"
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
  cat $sesDir/output
  return "$(cat $sesDir/result)"
}


: <<'=cut'
=pod

=head2 sesSend

Similarly to an C<expect> script, send an I<INPUT> to the B<sesID[0]> session.

    sesSend [options] INPUT

=head3 options

=over

=item B<--id> I<ID>

If provided the B<sesID[0]> will be set to I<ID>.

=item I<INPUT>

The input to be send to the session. It may contain also control characters,
e.g. B<\003> to send break (^C).

Note, to execute a command using C<sesSend> you need to append B<\r> to confirm
it on the prompt.

=back

Returns I<0> if successful.

=cut

sesSend() {
  while [[ "${1:0:2}" == '--' ]]; do
    case "$1" in
      "--id")
        sesID="$2"
        shift 2
        ;;
    esac
  done
  local sesDir="$__INTERNAL_sesDir/$sesID"
  local command="$1"
  sesRaw - << EOF
    send {$command}
EOF
  #[[ $? -ne 0 ]] && return 1
}


: <<'=cut'
=pod

=head2 sesSend

Send raw expect code the session handling daemon.

    sesRaw [options] CODE

=head3 options

=over

=item B<--id> I<ID>

If provided the B<sesID[0]> will be set to I<ID>.

=item I<CODE>

The code to be executed in the session handling expect daemon.

If C<-> is passed, the code will be read from I<STDIN>.

=back

Returns I<0> if successful. See section L<COMMON RESULT CODE|/"COMMON RESULT CODE"> for more details.

=cut

sesRaw() {
  [[ "$1" == "--id" ]] && {
    sesID="$2"
    shift 2
  }
  local command="$1"
  local sesDir="$__INTERNAL_sesDir/$sesID"
  kill -n 0 "$(<$sesDir/pid)" > /dev/null 2>&1 || {
    rlLogError "session $ID is not open"
    return 255
  }
  if [[ "$command" == "-" ]]; then
    command="$(cat -)"
  fi
  [[ -n "$DEBUG" ]] && { rlLogDebug "ID=$sesID, command="; echo "$command"; }
  [[ -z "$DEBUG" ]] && command='log_user 0'$'\n'"$command"$'\n'"log_user 1"
  cat > $sesDir/input <<< "$command"
}


: <<'=cut'
=pod

=head2 sesClose

Close the opened session B<sesID[0]>.

    sesClose [options]

=head3 options

=over

=item B<--id> I<ID>

If provided the B<sesID[0]> will be set to I<ID>.

=back

Returns I<0> if successful. See section L<COMMON RESULT CODE|/"COMMON RESULT CODE"> for more details.

=cut

sesClose() {
  local id
  [[ "$1" == "--id" ]] && {
    sesID="$2"
    shift 2
  }
  local command="$1"
  local sesDir="$__INTERNAL_sesDir/$sesID"
  kill -n 0 "$(<$sesDir/pid)" > /dev/null 2>&1 || {
    rlLogInfo "session $ID is not open"
    return 0
  }
  rlLogInfo "closing session $sesID"
  sesRaw 'exit'
  kill "$(<$sesDir/pid)" > /dev/null 2>&1
  sleep 0.25
  kill -s 0 "$(<$sesDir/pid)" > /dev/null 2>&1 || {
    rm -rf "$sesDir"
  }
}


: <<'=cut'
=pod

=head2 sesCleanup

Close all the remaining open sessions.

    sesCleanup

Returns I<0> if successful. See section L<COMMON RESULT CODE|/"COMMON RESULT CODE"> for more details.

=cut

sesCleanup() {
  local id
  [[ -z "$__INTERNAL_sesDir" ]] && {
    rlLogError 'Sessions dir is not set'
    retrun 1
  }
  for id in $__INTERNAL_sesDir/*; do
    sesClose --id "$(basename $id)"
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

sesLibraryLoaded() {

  echo -n "initiating library $__INTERNAL_ses_LIB_NAME v$__INTERNAL_ses_LIB_VERSION... "
  if ! egrep -qi '(vmx|svm|PowerNV)' /proc/cpuinfo; then
    rlLogError "Your CPU doesn't support VMX/SVM/PowerNV"
  fi

  if ! command -v expect >/dev/null 2>&1; then
    rlLogError "expect command is required!"
    res=1
  fi

  __INTERNAL_sesDir="$BEAKERLIB_DIR/sessions"
  mkdir -p "$__INTERNAL_sesDir"
  rm -rf "${__INTERNAL_sesDir:?}/*"
  echo "done."
  return $res
}


# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#   Authors
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

: <<'=cut'
=pod

=head1 COMMON RESULT CODE

There are specail I<RETURN CODES> commning from the library's cunctions.

=over

=item B<255>

The session ended unexpectedly. Any further interactions with the session will
end with an error.

=item B<254>

The session call timed out. There may be a I<command> hanging or a I<pattern> was
not found in time.

=item B<<254>

These return codes are typically comming from the executed command.

=item B<0>

Success!

=back

=head1 FILES

=over

=item F<ses.tcl>

The daemon forked to handle each session.

=back

=head1 AUTHORS

=over

=item *

Dalibor Pospisil <dapospis@redhat.com>

=back

=cut

echo "done."
