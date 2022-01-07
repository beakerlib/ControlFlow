# NAME

**library(SessionControl/basic)**

# DESCRIPTION

A library providing functions to support multiple sessions control.

# VARIABLES

- **sessionID**

    An array holding currently open session IDs. Sessions are strored from index 1,
    index 0 is always used for the "default" **ID**. The default **ID** is always reset
    to the last used _ID_.

- **sessionRunTIMEOUT**

    A default timeout for `sessionRun`, if defined.

- **sessionExpectTIMEOUT**

    A default timeout for `sessionExpect`, if defined.

# FUNCTIONS

## sessionOpen

Open new session.

    sessionOpen [options]

### options

- **--id** _ID_

    If provided the user-specified _ID_ will be used. Othersiwe a numeric _ID_ will be
    assigned.

Returns **0** if successful. See section ["COMMON RESULT CODE"](#common-result-code) for more details.

## sessionRun

Run a command in the **sessionID\[0\]** session.

    sessionRun [options] [--] COMMAND

### options

- **--id** _ID_

    If provided the **sessionID\[0\]** will be set to _ID_.

- **--timeout** _TIMEOUT_

    The command execution time will be limitted to _TIMEOUT_ second(s).

    Defaults to _infinity_ (**-1**) or **sessionRunTIMEOUT**, if set.

- --

    Optional explicit end of options. This is useful if the command starts with dashes (-).

- _COMMAND_

    The `COMMAND` to be executed in the **sessionID\[0\]**.

    Both _STDOUT_ and _STDERR_ of the command will be merged and passed to
    _STDOUT_ continuously.

Returns **0** if successful. See section ["COMMON RESULT CODE"](#common-result-code) for more details.

## sessionExpect

Similarly to an `expect` script, wait for a _REG\_EXP_ pattern appearence
in the **sessionID\[0\]** session.

    sessionExpect [options] [regexp_switches] [--] REG_EXP

### options

- **--id** _ID_

    If provided the **sessionID\[0\]** will be set to _ID_.

- **--timeout** _TIMEOUT_

    The command execution time will be limitted to _TIMEOUT_ second(s).

    Defaults to **120** seconds or **sessionExpectTIMEOUT**, if set.

#### regexp\_switches

- -_switch_

    An option starting with single dash (-) is considered to be a switch to tcl's
    regexp. See [https://www.tcl.tk/man/tcl8.5/TclCmd/regexp.html#M4](https://www.tcl.tk/man/tcl8.5/TclCmd/regexp.html#M4).

- --

    Optional explicit end of options. This is useful if the regexp starts with dashes (-).

- _REG\_EXP_

    The pattern to be awaited in the session output.

Both _STDOUT_ and _STDERR_ of the session will be merged and passed to
_STDOUT_ continuously.

Returns **0** if successful. See section ["COMMON RESULT CODE"](#common-result-code) for more details.

## sessionSend

Similarly to an `expect` script, send an _INPUT_ to the **sessionID\[0\]** session.

    sessionSend [options] [--] INPUT

### options

- **--id** _ID_

    If provided the **sessionID\[0\]** will be set to _ID_.

- _INPUT_

    The input to be send to the session. It may contain also control characters,
    e.g. **\\003** to send break (^C).

    Note, to execute a command using `sessionSend` you need to append **\\r** to confirm
    it on the prompt.

- --

    Optional explicit end of options. This is useful if the input starts with dashes (-).

Returns **0** if successful.

## sessionWaitAPrompt

Wait a prompt to appear in the **sessionID\[0\]** session.

    sessionWaitAPrompt [options]

### options

- **--id** _ID_

    If provided the **sessionID\[0\]** will be set to _ID_.

- **--timeout** _TIMEOUT_

    The command execution time will be limitted to _TIMEOUT_ second(s).

    Defaults to **120** seconds or **sessionExpectTIMEOUT**, if set.

Note, it may be necessary to send an _enter_ (e.g. sessionSend $'\\r') first.

Returns **0** if successful.

## sessionRaw

Send raw expect code the session handling daemon.

    sessionRaw [options] [--] CODE

### options

- **--id** _ID_

    If provided the **sessionID\[0\]** will be set to _ID_.

- _CODE_

    The code to be executed in the session handling expect daemon.

    If `-` is passed, the code will be read from _STDIN_.

- --

    Optional explicit end of options. This is useful if the _CODE_ starts with dashes (-).

Returns **0** if successful. See section ["COMMON RESULT CODE"](#common-result-code) for more details.

## sessionClose

Close the opened session **sessionID\[0\]**.

    sessionClose [options]

### options

- **--id** _ID_

    If provided the **sessionID\[0\]** will be set to _ID_.

Returns **0** if successful. See section ["COMMON RESULT CODE"](#common-result-code) for more details.

## sessionCleanup

Close all the remaining open sessions.

    sessionCleanup

Returns **0** if successful. See section ["COMMON RESULT CODE"](#common-result-code) for more details.

# COMMON RESULT CODE

There are special _RETURN CODES_ coming from the library's functions.

- **255**

    The session ended unexpectedly. Any further interactions with the session will
    end with an error.

- **254**

    The session call timed out. There may be a _command_ hanging or a _pattern_ was
    not found in time.

- **<254**

    These return codes are typically coming from the executed command.

- **0**

    Success!

# EXAMPLES

Simply run `whoami` command in a session

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

# FILES

- `session.tcl`

    The daemon forked to handle each session.

# AUTHORS

- Dalibor Pospisil <dapospis@redhat.com>
