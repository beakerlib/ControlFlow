# NAME

**library(ses/basic)**

# DESCRIPTION

A library providing functions to support multiple sessions control.

# VARIABLES

- **sesID**

    An array holding currently open session IDs. Sessions are strored from index 1,
    index 0 is always used for the "default" **ID**. The default **ID** is always reset
    to the last used _ID_.

- **sesRunTIMEOUT**

    A default timeout for `sesRun`, if defined.

- **sesExpectTIMEOUT**

    A default timeout for `sesExpect`, if defined.

# FUNCTIONS

## sesOpen

Open new session.

    sesOpen [options]

### options

- **--id** _ID_

    If provided the user-specified _ID_ will be used. Othersiwe a numeric _ID_ will be
    assigned.

Returns **0** if successful. See section ["COMMON RESULT CODE"](#common-result-code) for more details.

## sesRun

Run a command in the **sesID\[0\]** session.

    sesRun [options] COMMAND

### options

- **--id** _ID_

    If provided the **sesID\[0\]** will be set to _ID_.

- **--timeout** _TIMEOUT_

    The command execution time will be limitted to _TIMEOUT_ second(s).

    Defaults to _infinity_ (**-1**) or **sesRunTIMEOUT**, if set.

- _COMMAND_

    The `COMMAND` to be executed in the **sesID\[0\]**.

    Both _STDOUT_ and _STDERR_ of the command will be merged and passed to
    _STDOUT_ continuously.

Returns **0** if successful. See section ["COMMON RESULT CODE"](#common-result-code) for more details.

## sesExpect

Similarly to an `expect` script, wait for a _REG\_EXP_ pattern appearence
in the **sesID\[0\]** session.

    sesExpect [options] REG_EXP

### options

- **--id** _ID_

    If provided the **sesID\[0\]** will be set to _ID_.

- **--timeout** _TIMEOUT_

    The command execution time will be limitted to _TIMEOUT_ second(s).

    Defaults to **120** seconds or **sesExpectTIMEOUT**, if set.

- _REG\_EXP_

    The pattern to be awaited in the session output.

Both _STDOUT_ and _STDERR_ of the session will be merged and passed to
_STDOUT_ continuously.

Returns **0** if successful. See section ["COMMON RESULT CODE"](#common-result-code) for more details.

## sesSend

Similarly to an `expect` script, send an _INPUT_ to the **sesID\[0\]** session.

    sesSend [options] INPUT

### options

- **--id** _ID_

    If provided the **sesID\[0\]** will be set to _ID_.

- _INPUT_

    The input to be send to the session. It may contain also control characters,
    e.g. **\\003** to send break (^C).

    Note, to execute a command using `sesSend` you need to append **\\r** to confirm
    it on the prompt.

Returns **0** if successful.

## sesRaw

Send raw expect code the session handling daemon.

    sesRaw [options] CODE

### options

- **--id** _ID_

    If provided the **sesID\[0\]** will be set to _ID_.

- _CODE_

    The code to be executed in the session handling expect daemon.

    If `-` is passed, the code will be read from _STDIN_.

Returns **0** if successful. See section ["COMMON RESULT CODE"](#common-result-code) for more details.

## sesClose

Close the opened session **sesID\[0\]**.

    sesClose [options]

### options

- **--id** _ID_

    If provided the **sesID\[0\]** will be set to _ID_.

Returns **0** if successful. See section ["COMMON RESULT CODE"](#common-result-code) for more details.

## sesCleanup

Close all the remaining open sessions.

    sesCleanup

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

    sesOpen
    sesRun "id"
    sesClose

Run commands in two sessions

    sesOpen
    sesOpen
    sesRun --id ${sesID[1]} "whoami"
    sesRun --id ${sesID[2]} "whoami"
    sesRun "whoami"                   # run in sesID[2] as it was the last one used
    sesClose --id ${sesID[1]}
    sesClose --id ${sesID[2]}

    sesOpen --id A
    sesOpen --id B
    sesRun --id A "whoami"
    sesRun --id B "whoami"
    sesRun "whoami"                   # run in B as it was the last one used
    sesID=A                           # equal to sesID[0]=A
    sesRun "whoami"                   # run in A
    sesClose --id A
    sesClose --id B

Run command on remote machines

      sesOpen --id server
      sesOpen --id client
    # note, we need to let ssh execution to timeout as the ssh command actually
    # does not finish, it will stay waiting for the password and the remote prompt
      sesRun --id server --timeout 1 "ssh UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no root@server.example.com"
      sesExpect "[Pp]assword"
      sesSend "PASSWORD"$'\r'
      sesRun --id client --timeout 1 "ssh UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no root@client.example.com"
      sesExpect "[Pp]assword"
      sesSend "PASSWORD"$'\r'
    # check we are on the remote
      rlRun -s 'sesRun --id server "hostname -f"'
      rlAssertGrep 'server.example.com' $rlRun_LOG
      rm -f $rlRun_LOG
      rlRun -s 'sesRun --id client "hostname -f"'
      rlAssertGrep 'client.example.com' $rlRun_LOG
      rm -f $rlRun_LOG
    # optionally exit from ssh connections
    # note, we need to let this execution to timeout as well as we are basically
    # returning from the remote prompt to the local prompt - the one from
    # the previousely timed out ssh execution
    # alternatively one could do this by issuing sesSend "exit"$'\r'
      sesRun --id server --timeout 1 "exit"
      sesRun --id client --timeout 1 "exit"
      sesClose --id server
      sesClose --id client

# FILES

- `ses.tcl`

    The daemon forked to handle each session.

# AUTHORS

- Dalibor Pospisil <dapospis@redhat.com>
