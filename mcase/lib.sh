#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Description: Modal test code
#   Author: Alois Mahdal <amahdal@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2020 Red Hat, Inc.
#
#   This program is free software: you can redistribute it and/or
#   modify it under the terms of the GNU General Public License as
#   published by the Free Software Foundation, either version 2 of
#   the License, or (at your option) any later version.
#
#   This program is distributed in the hope that it will be
#   useful, but WITHOUT ANY WARRANTY; without even the implied
#   warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#   PURPOSE.  See the GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program. If not, see http://www.gnu.org/licenses/.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#   library-prefix = distribution_mcase__
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

#
# Modal test case
#
# This module brings modal approach to defining and running test
# code.
#
# Instead of writing your test case as a single body of code,
# you will define handlers for different modes: setup, test, diag
# and cleanup, and call a special function which will run all the
# handlers in particular order.
#
# The standard order is `setup`, `test`, `diag`, `cleanup` but the
# runner function can amend this order based on instructions from test
# scheduler, typically passed as environment variables.
#
# Typical example of this is an upgrade test that will run `setup` and
# `test` on first environment, then upgrade the system and run `test`
# on upgraded system again.
#
#
# =head1 HELP, MY TEST IS FAILING AND I DON'T UNDERSTAND THIS SORCERY!
#
# If you encounter mcase-based test and want to understand what's
# happening, usually the fastest way to get the grip is:
#
#  1. Look at early log text around 'selected workflow:'  This is
#     where the "workflow" is shown, ie. planned sequence of handlers
#
#  2. All the test really does is just call these handlers in that order,
#     wrapping them in phases.
#
#  4. Open the test code.
#
#     For every phase (setup, test, diag and cleanup), there is
#     one function ("handler") named `distribution_mcase__test`
#     etc. (Actually only 'test' is mandatory.)
#
#
# =head1 GETTING STARTED
#
# Here's what you need to do:
#
#  1. Implement handlers:
#
#         distribution_mcase__setup (optional)
#         distribution_mcase__test
#         distribution_mcase__diag (optional)
#         distribution_mcase__cleanup (optional)
#
#  2. Finally, run a single "magic" function, `distribution_mcase__run()`.
#     This will take care of the rest.
#
#
# =head1 EXAMPLE
#
#     distribution_mcase__setup() {
#         rlRun "mkdir /var/ftp"                    || return 1
#         rlRun "cp testfile /var/ftp"              || return 1
#         rlRun "useradd joe"                       || return 1
#         rlRun "rlServiceRestart hypothetical_ftp  || return 1
#         rlRun "rlServiceEnable hypothetical_ftp   || return 1
#     }
#
#     distribution_mcase__test() {
#         rlRun "su -c 'hypo_ftp localhost 25 <<<\"get testfile\"' - joe"
#         rlRun "diff /var/ftp/testfile /home/joe/testfile"
#     }
#
#     distribution_mcase__cleanup() {
#         rlRun "rm -rf /var/ftp"
#         rlRun "userdel joe"
#         rlRun "rlServiceRestart hypothetical_ftp
#     }
#
#
#     rlJournalStart
#
#         rlPhaseStartSetup
#             rlImport ControlFlow/mcase
#         rlPhaseEnd
#
#         distribution_mcase__run
#
#     rlJournalEnd
#     rlJournalPrint
#
# Notice:
#
#  *  The same test without ControlFLow/mcase would require lot of
#     rlPhase*() calls.
#
#  *  The setup is now responsive to situations when something is terribly
#     wrong: the setup will now stop (causing test to be skipped) if
#     any of the commands fail.
#
#
# =head1 WORKFLOWS
#
# By default, (`basic` workflow) handlers are called in this order:
#
#     setup
#     test
#     diag
#     cleanup
#
# In various circumstances, it may be useful to tweak the order.  With
# ControlFlow/mcase, you can have the runner function run handlers in
# any order without need touch the test code, using *workflows*.
#
# With ControlFlow/mcase, you can alter the order:
#
#  *  using one of built-in workflows,
#  *  providing your own workflow.
#
# Note that all handlers except `test` are optional and are silently
# skipped if missing.
#
#
# =head2 Built-in workflows
#
# To use a built-in workflow, set $distribution_mcase__workflow variable
# to one of following values:
#
#  *  `auto` - will let d/mcase choose workflow automatically.  This is
#      the default value.
#
#  *  `basic` - this is the default selection of `auto` workflow, if no
#      other known modes (eg. upgrade mode) are detected.
#
#     `basic` workflow runs handlers in natural order:
#
#         setup
#         test
#         diag
#         cleanup
#
#  *  `just_setup`, `just_test`, `just_diag`, `just_cleanup` - these
#     workflows run only single handler.
#
#  *  `dbg_start`, `dbg_test`, `dbg_stop` - these workflows are handy when
#     hacking on a test with an expensive setup and/or cleanup.
#
#      *  `dbg_start` runs `setup` and `diag` only,
#      *  `dbg_test` runs `test` and `diag` only.
#      *  `and dbg_stop` runs `diag` and `cleanup` only.
#
#     The idea is that you may want to run `dbg_start` once just to
#     your testing machine, then possibly many times run `dbg_test`
#     until you're happy with your test handler, then run `dbg_stop`
#     to "close the circle".
#
#  *  `tmt_upgrade` - if d/mcase detects that your test is running under
#     upgrade mode of the TMT framework (/upgrade executor plugin), it
#     will consult IN_PLACE_UPGRADE to decide which handlers to run.
#
#     Normally this will mean `setup`, `test`, `diag` if the value of
#     IN_PLACE_UPGRADE variable is `old`, and `test`, `diag` and `cleanup`
#     if the value is `new` (upgraded distro).
#
#  *  `morf_upg` - if d/mcase detects that your test is running under
#     upgrade mode of the MORF framework (upgrade test), it will consult
#     MORF to decide which handlers to run.
#
#     Normally this will mean `setup`, `test`, `diag` on source distro,
#     and `test`, `diag` and `cleanup` on destination (upgraded) distro.
#
#
# =head1 PERSISTENCE AND WORKING DIRECTORY
#
# Note that d/mcase will ensure that:
#
#  *  All handlers run in the same directory, dedicated for given
#     test case.
#
#  *  Files are preserved from previous handler.
#
# This means if one handler creates a file in its work directory ($PWD or
# `pwd` in Bash), next one can read it.
#
# The work directory is created by the distribution_mcase__run() function
# and is a sub-directory of $distribution_mcase__root named either `mcase`,
# or by name specified as CASE ID, specified as -I parameter of
# distribution_mcase__run().
#
# For example, following calls will work:
#
#     distribution_mcase__setup() {
#         echo "foo" >bar
#     }
#
#     distribution_mcase__test() {
#         rlAssert "grep foo bar"
#     }
#
#     distribution_mcase__run
#
# even in upgrade mode, where if `foo` was kept in a variable, it would
# be lost.  Without passing any additional variables, both handlers will
# run in */var/tmp/distribution_mcase/mcase*.
#
# If the test code is parametrized using its own environment variables,
# in order to avoid conflicts, it's recommended to create case id
# containing all of the variables and pass it using the `-I` option:
#
#     distribution_mcase__setup() {
#         echo "$TEST_MODE" >bar
#     }
#
#     distribution_mcase__test() {
#         rlAssert "grep $TEST_MODE bar"
#     }
#
#     distribution_mcase__run -I "$TEST_MODE"
#
# That way the test code can be run with different TEST_MODE sequentially
# without risk of "cross-contamination" between handlers.
#
#
# =head1 RELICS COLLECTION
#
# If your test code creates various test config and diagnostic files,
# d/mcase can automatically collect them for you.  (Ie. you won't have
# to rlFileSubmit() or rlBundleLogs() them.)
#
# Auto-collection is enabled by passing `-c` to distribution_mcase__run()
# and when enabled, files left over in the work directory after running
# handlers, are collected into a single tarball: `mcase-relics.tar.gz`.
#
# Exception from this are files created under `tmp` sub-directory (created
# automatically by d/mcase); this directory is ignored when creating the
# tarball.  If your test creates huge files, make sure to put them under
# the `tmp` subdir before enabling the auto-collection feature.
#
#
# =head1 THE WHY
#
# Compared to traditional "linear" style, where you have all your test code
# written command after command, tests implemented using d/mcase have multiple
# advantages:
#
#  *  far less code necessary,
#
#  *  more flexible (the workflow can be customized, eg. skip cleanup,
#     repeat test 100x, run in upgrade scenario..),
#
#  *  "don't run test if setup failed" logic is used, possibly saving
#     lot of resources,
#
#  *  no need for boring formalities such as `rlPhaseStart`,
#
#  *  moving code to functions enables you to short-cut by
#     `return` keyword (=> clarity AND resource saving),
#
#  *  the test is much easier to understand (if done well).
#
#

#
# Default workflow to use
#
distribution_mcase__workflow=${distribution_mcase__workflow:-auto}

#
# Test work dir root
#
# Root directory where working directories for handlers are created.
#
# See PERSISTENCE AND WORKING DIRECTORY for details.
#
distribution_mcase__root=${distribution_mcase__root:-/var/tmp/distribution_mcase__root}

distribution_mcase__id() {
    #
    # Print current case ID
    #
    # Usage:
    #
    #     distribution_mcase__id
    #
    # Inside handler, this function will output CASEID.
    #
    test -n "$__distribution_mcase__testhome" || {
        __distribution_mcase__error \
            "invalid call; cannot call this from outside handlers!"
        return 2
    }
    echo "$__distribution_mcase__id"
}

distribution_mcase__run() {
    #
    # Run all cases from distribution_mcase__enum()
    #
    # Usage:
    #
    #     distribution_mcase__run [-I CASEID] [-c] [-w WORKFLOW]
    #
    # This function is the main launcher for tests.  It will perform roughly
    # following steps:
    #
    #  1. Create run directory and chdir there.
    #
    #     (The directory path is composed of $distribution_mcase__root
    #     and CASEID).
    #
    #  2. Run all available handlers as defined by workflow.  With basic
    #     workflow this is:
    #
    #      1. setup
    #      2. test
    #      3. diag
    #      4. cleanup
    #
    #  3. chdir back
    #
    # See also "GETTING STARTED" and "WORKFLOWS" sections.
    #
    # The behavior can be altered using options:
    #
    #   '-I CASEID' - Use case ID CASEID instead of the default one,
    #       'mcase'.
    #
    #   '-P' - don't touch phases.  This means handlers must declare
    #       phases themselves, but can have multiple phases per handler
    #
    #       Due to how beakerlib works, this means d/mcase can't implement
    #       logic of skipping test if setup failed, ie. all handlers will
    #       be ran unconditionally.
    #
    #   '-S' - don't skip 'test' handler on setup failure.
    #
    #       It's often a good practice (leading to smaller, easier to"
    #       understand test code) to only run critical code in asserts.
    #       Before using this option, consider whether non-critical code
    #       in setup handler could be ran "plainly", outside rlRun.
    #
    #   '-c' - automatically create and submit of relics tarball. See
    #       RELICS COLLECTION.
    #
    #   '-w WORKFLOW' - Force non-default workflow WORKFLOW. See "WORKFLOWS"
    #       section of this manual.
    #
    local __distribution_mcase__tmp            # results cache directory
    local __distribution_mcase__rball=false    # collect relics tarball?
    local __distribution_mcase__dophases=true  # open/end phases?
    local __distribution_mcase__workflow       # workflow to use
    local __distribution_mcase__id=mcase       # case ID
    local __distribution_mcase__testhome=$PWD  # test home
    local __distribution_mcase__spolicy=abort  # policy on setup failures
    __distribution_mcase__workflow=$distribution_mcase__workflow
    while true; do case $1 in
        -I)
            __distribution_mcase__id="$2"
            shift 2 || {
                __distribution_mcase__error "missing value to -I parameter"
                return 2
            }
            ;;
        -P)
            __distribution_mcase__dophases=false
            shift
            ;;
        -S)
            __distribution_mcase__spolicy=cont
            shift
            ;;
        -c)
            __distribution_mcase__rball=true
            shift
            ;;
        -w)
            __distribution_mcase__workflow="$2"
            shift 2 || {
                __distribution_mcase__error "missing value to -w parameter"
                return 2
            }
            ;;
        -*)
            __distribution_mcase__error "bad argument: '$1'"
            return 2
            ;;
        "")
            break
            ;;
        *)
            __distribution_mcase__error "bad argument: '$1'"
            return 2
            ;;
    esac done
    __distribution_mcase__validate_id || return 2
    __distribution_mcase__tmp=$(mktemp -d -t distribution_mcase.meta.XXXXXXXX)
    __distribution_mcase__run_all \
     || __distribution_mcase__error "errors encountered during case traversal"
    $__distribution_mcase__rball \
     && rlFileSubmit "$__distribution_mcase__tmp/relics.tar.gz" "mcase-relics.tar.gz"
    rm -rf "$__distribution_mcase__tmp"
}


#           #                                                            #
# TEMPLATES # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ #
#           #                                                            #

_distribution_mcase__setup() {
    #
    # Skeleton for setup handler
    #
    # Perform setup tasks for case id.
    #
    true
}

_distribution_mcase__test() {
    #
    # Skeleton for test handler
    #
    # Perform tests for case id.
    #
    true
}

_distribution_mcase__diag() {
    #
    # Skeleton for diag handler
    #
    # Perform diag tasks for case id.
    #
    true
}

_distribution_mcase__cleanup() {
    #
    # Skeleton for cleanup handler
    #
    # Perform cleanup tasks for case id.
    #
    true
}


#          #                              handling code behind this line #
# INTERNAL # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ #
#          #                              is just, like, tOtally bad!..! #

#
# True if this library has been loaded
#
# This exists only to let distribution/upgrade employ an ugly hack, all to
# avoid bug beakerlib#50; see:
#
#   https://github.com/beakerlib/beakerlib/issues/50
#
#shellcheck disable=SC2034
__distribution_mcase__self_loaded=true


__distribution_mcase__has() {
    #
    # Check if handler has been implemented
    #
    type -t "distribution_mcase__$1" >/dev/null
}

__distribution_mcase__error() {
    #
    # Show internal error $1 properly
    #
    # One should not use `rlFail "error message"`, since rlFail is an
    # assert and asserts should always bear "positive" comment (eg.
    # `rlRun "true" 0 "all is OK"`).
    #
    # Instead we should log error via rlLogError.  Since beaker and
    # other tools do not properly bring that into user's attention,
    # we can "abuse" rlFail to trigger failure, but this time just add
    # a specific unique message that cannot be confused with SUT-related
    # assert.
    #
    local msg   # each message
    for msg in "$@";
    do
        rlLogError "$msg"
    done
    rlFail "(INTERNAL TEST ERROR)"
}

__distribution_mcase__run_all() {
    #
    # Run all handlers
    #
    local __distribution_mcase__htype       # handler type
    local __distribution_mcase__workdir     # actual work directory
    local __distribution_mcase__sfail       # did setup fail?
    local __distribution_mcase__tfail       # did test fail?
    local __distribution_mcase__wf          # selected workflow name
    local __distribution_mcase__wfline      # workflow line
    local __distribution_mcase__wfitem      # workflow item
    local __distribution_mcase__wfargs      # workflow item arguments
    local __distribution_mcase__killwd=false     # remove work dir?

    __distribution_mcase__workdir="$distribution_mcase__root/mcase-relics/$__distribution_mcase__id"
    mkdir -p "$__distribution_mcase__workdir" || {
        __distribution_mcase__error "cannot create work directory: $__distribution_mcase__workdir"
        return 3
    }
    __distribution_mcase__pushd "$__distribution_mcase__workdir" || return 3

        __distribution_mcase__sfail=false
        __distribution_mcase__tfail=false

        if $__distribution_mcase__rball; then
            mkdir -p "tmp" \
             || rlLogError "failed to create test tmp"
        fi
        cp -aur "$__distribution_mcase__testhome/"* .

        __distribution_mcase__wf=$(__distribution_mcase__select_workflow) || {
            __distribution_mcase__error \
                "could not select workflow"
            return 3
        }
        __distribution_mcase__info "selected workflow: $__distribution_mcase__wf"
        __distribution_mcase__info ""
        __distribution_mcase__mkworkflow >"$__distribution_mcase__tmp/workflow"
        __distribution_mcase__info "steps:"
        __distribution_mcase__info ""
        while read -r __distribution_mcase__wfline; do
            __distribution_mcase__info "    $__distribution_mcase__wfline"
        done <"$__distribution_mcase__tmp/workflow"

        cp "$__distribution_mcase__tmp/workflow" "$__distribution_mcase__tmp/plan.todo"
        touch "$__distribution_mcase__tmp/plan.done"
        touch "$__distribution_mcase__tmp/plan.now"
        while true; do
            {
                head -1 \
                    <"$__distribution_mcase__tmp/plan.todo" \
                    >"$__distribution_mcase__tmp/plan.now"
                sed -i "1d" "$__distribution_mcase__tmp/plan.todo"
                read -r __distribution_mcase__wfitem __distribution_mcase__wfargs \
                    <"$__distribution_mcase__tmp/plan.now" \
                 || break
            }
            case $__distribution_mcase__wfitem in
                "")
                    continue
                    ;;
                "#"*)
                    continue
                    ;;
                setup|test|diag|cleanup)
                    __distribution_mcase__htype=$__distribution_mcase__wfitem
                    __distribution_mcase__wrap_handler
                    ;;
                *)
                    __distribution_mcase__run_wcmd \
                        "$__distribution_mcase__wfitem" \
                        "$__distribution_mcase__wfargs" \
                     || {
                            __distribution_mcase__error \
                                "workflow command failed: $__distribution_mcase__wfitem $__distribution_mcase__wfargs"
                            return 3
                        }
                    ;;
            esac
            case $__distribution_mcase__wfitem in
                cleanup)    __distribution_mcase__killwd=true ;;
                *)          __distribution_mcase__killwd=false ;;
            esac
            echo "$__distribution_mcase__wfitem" "$__distribution_mcase__wfargs" \
                >>"$__distribution_mcase__tmp/plan.done"
        done

    __distribution_mcase__popd "$__distribution_mcase__workdir" \
     || return 3

    __distribution_mcase__mkball

    if "$__distribution_mcase__killwd"; then
        rm -r "$__distribution_mcase__workdir"
    fi
}

__distribution_mcase__info() {
    #
    # Print our rlLogInfo
    #
    local line
    for line in "$@"; do
        case "$line" in
            "") rlLogInfo "d/mcase:" ;;
            *)  rlLogInfo "d/mcase: $line" ;;
        esac
    done
}

__distribution_mcase__mkball() {
    #
    # Create and submit tarball
    #
    local line
    $__distribution_mcase__rball || return 0
    find "$__distribution_mcase__workdir" \
      | grep -v \
            -e "^$__distribution_mcase__workdir$" \
            -e "^$__distribution_mcase__workdir/tmp$" \
            -e "^$__distribution_mcase__workdir/tmp/" \
      | grep . \
     || {
        __distribution_mcase__info "nothing to collect"
        return 0
    }
    __distribution_mcase__pushd "$distribution_mcase__root" \
     || return 3
        tar \
            --exclude="mcase-relics/$__distribution_mcase__id/tmp" \
            -czf "$__distribution_mcase__tmp/relics.tar.gz" \
            "mcase-relics/$__distribution_mcase__id"
        __distribution_mcase__info "created mcase-relics.tar.gz with files:"
        __distribution_mcase__info ""
        tar -tf "$__distribution_mcase__tmp/relics.tar.gz" \
          | sort \
          | while read -r line; do
                __distribution_mcase__info "    $line"
            done
        __distribution_mcase__info ""
    __distribution_mcase__popd "$distribution_mcase__root" \
     || return 3
}

__distribution_mcase__popd() {
    #
    # popd from $1, warn and false if it goes wrong
    #
    local path=$1
    rlLogDebug "popding from: $path"
    popd >/dev/null && return 0
    __distribution_mcase__error "could not popd from: $path"
    return 3
}

__distribution_mcase__pushd() {
    #
    # pushd to $1, warn and false if it goes wrong
    #
    local path=$1
    rlLogDebug "pushding to: $path"
    pushd "$path" >/dev/null && return 0
    __distribution_mcase__error "could not pushd to: $path"
    return 3
}

__distribution_mcase__run_wcmd() {
    #
    # Run workflow command
    #
    local cmd=$1
    local args=$2
    case $cmd in
        sleep)
            __distribution_mcase__info "sleeping for: $args"
            sleep "$args"
            ;;
        *)
            __distribution_mcase__error \
                "unknown workflow command: $cmd"
            return 3
            ;;
    esac
}

__distribution_mcase__tmpread() {
    #
    # Get result metadata from key $1
    #
    # See __distribution_mcase__tmpfile() for key syntax.
    #
    local key=$1    # key to read
    cat "$(__distribution_mcase__tmpfile "$key")"
}

__distribution_mcase__tmpwrite() {
    #
    # Save result metadata value $2 under key $1
    #
    # See __distribution_mcase__tmpfile() for key syntax.
    #
    local key=$1    # key to write
    local value=$2  # value to write
    local tgt       # target file path
    tgt=$(__distribution_mcase__tmpfile "$key")
    echo "$value" > "$tgt"
}

__distribution_mcase__tmpfile() {
    #
    # Dereference temp storage key $1
    #
    # The key may be prefixed by `C.` or `H.`, meaning "for current case id"
    # or "for current handler", respectively.  For example, following keys are
    # valid:
    #
    #     foo       # same file at any time
    #     C.foo     # same file until the end of this subtest (case id)
    #     H.foo     # same file until the end of this handler (eg. setup)
    #
    # Note: This function has a side effect within the storage structure that
    # directory for the data file is automatically created so that caller does
    # not need to.
    #
    local key=$1    # key to dereference
    local ns_case   # case id infix
    local ns_htype  # handler type infix
    local path      # final path
    ns_case=id/$__distribution_mcase__id
    ns_htype=handler/$__distribution_mcase__htype
    path=$__distribution_mcase__tmp/data/
    case $key in
        C.*)    path+="$ns_case/${key#C.}"           ;;
        H.*)    path+="$ns_case/$ns_htype/${key#H.}" ;;
        *)      path+="$key"                         ;;
    esac
    mkdir -p "${path%/*}"
    echo "$path"
}

__distribution_mcase__phase() {
    #
    # Handle phase if needed
    #
    $__distribution_mcase__dophases || return 0
    local what=$1
    case $what in
        starts)
            rlPhaseStartSetup   "$__distribution_mcase__id :: setup"
            ;;
        startt)
            rlPhaseStartTest    "$__distribution_mcase__id :: test"
            ;;
        startd)
            rlPhaseStartCleanup "$__distribution_mcase__id :: diag"
            ;;
        startc)
            rlPhaseStartCleanup "$__distribution_mcase__id :: cleanup"
            ;;
        end)
            rlPhaseEnd
            ;;
        *)
            __distribution_mcase__error \
                "invalid phase op (probably bug in d/mcase)!"
            ;;
    esac
}

__distribution_mcase__wrap_handler() {
    #
    # Handler wrapper
    #
    # Set phases, record failures, set up environment...
    #
    local __distribution_mcase__hfails=""       # this handler fails num.
    local __distribution_mcase__hresult=none    # this handler result
    __distribution_mcase__has "$__distribution_mcase__htype" || {
        __distribution_mcase__tmpwrite H.result "none"
        return 0
    }
    case $__distribution_mcase__htype in
        setup)
            __distribution_mcase__phase starts
            distribution_mcase__setup
            ;;
        test)
            __distribution_mcase__phase startt
            case $__distribution_mcase__dophases:$__distribution_mcase__sfail:$__distribution_mcase__spolicy in
                true:true:abort)
                    rlLogWarning "setup failed--skipping test"
                    __distribution_mcase__tmpwrite H.result "abort"
                    rlPhaseEnd
                    return 1
                    ;;
                true:true:cont)
                    rlLogWarning "setup failed but policy is to keep running (-S)"
                    distribution_mcase__test
                    ;;
                *)
                    distribution_mcase__test
                    ;;
            esac
            ;;
        diag)
            __distribution_mcase__phase startd
            distribution_mcase__diag
            ;;
        cleanup)
            __distribution_mcase__phase startc
            distribution_mcase__cleanup
            ;;
    esac
    $__distribution_mcase__dophases && {
        rlGetPhaseState; __distribution_mcase__hfails=$?
    }
    __distribution_mcase__phase end
    case $__distribution_mcase__hfails in
        0)  __distribution_mcase__hresult=pass ;;
        *)  __distribution_mcase__hresult=fail ;;
    esac
    __distribution_mcase__tmpwrite H.result "$__distribution_mcase__hresult"
    #shellcheck disable=SC2034
    case $__distribution_mcase__htype:$__distribution_mcase__hresult in
        setup:fail) __distribution_mcase__sfail=true ;;
        test:fail)  __distribution_mcase__tfail=true  ;;
    esac
}

__distribution_mcase__validate_id() {
    #
    # Make sure $distribution_mcase__id has no banned chars
    #
    local allowed='[:alnum:]._,+%=-'    # allowed chars in case id
    local es=                           # exit status of this function
    if grep "[^$allowed]" <<<"$__distribution_mcase__id";
    then
        rlLogError "Sorry, when leaf directory mode (default) or variable"
        rlLogError "setting mode is used, range of characters that"
        rlLogError "CASEID can contain is limited to:"
        rlLogError ""
        rlLogError "    $allowed"
        rlLogError ""
        rlLogError "This is to enable usage of this data as file, directory"
        rlLogError "and variable names."
        __distribution_mcase__error "illegal characters in enumerator"
        rlLogWarning "Note that in order to make best use of d/mcase, the case id"
        rlLogWarning "should not hold any 'real' testing data but rather just"
        rlLogWarning "simple generic words to hint *intent* of the test case."
        es=2
    fi
    return $es
}

__distribution_mcase__mkworkflow() {
    #
    # Produce workflow (list of handlers to call)
    #
    local fn
    fn=$(__distribution_mcase__select_workflowfn "$__distribution_mcase__wf")
    type -t "$fn" >/dev/null || {
        __distribution_mcase__error \
            "invalid workflow: $__distribution_mcase__workflow"
            "(workflow function does not exist: $fn())"
        return 3
    }
    "$fn" || {
        __distribution_mcase__error \
            "error when creating workflow: $__distribution_mcase__workflow"
            "(workflow function failed: $fn())"
        return 3
    }
}

__distribution_mcase__select_workflow_auto() {
    #
    # Automatically detect a particular workflow
    #
    #shellcheck disable=SC2154
    case $morf__stage in
        src|dst)
            rlImport 'distribution/upgrade'
            echo morf_upg
            return 0
            ;;
    esac
    case $IN_PLACE_UPGRADE in
        old|new)
            rlImport 'distribution/upgrade'
            echo tmt_upgrade
            return 0
            ;;
    esac
    return 1
}

__distribution_mcase__select_workflow() {
    #
    # Select which workflow to use
    #
    case $__distribution_mcase__workflow in
        "")
            __distribution_mcase__error \
                "no workflow provided (probably bug in d/mcase)!"
            return 3
            ;;
        auto)
            __distribution_mcase__select_workflow_auto \
             || echo "basic"
            ;;
        *)
            echo "$__distribution_mcase__workflow"
            ;;
    esac
}

__distribution_mcase__select_workflowfn() {
    #
    # Select which workflow to use
    #
    local wf=$1
    case $wf in
        *'()')
            #shellcheck disable=SC2001
            sed 's/..$//' <<<"$wf"
            ;;
        *)
            echo "__distribution_mcase__w_$wf"
            ;;
    esac \
      | head -1 \
      | grep .
}

__distribution_mcase__w_just_setup() {
    echo setup
}

__distribution_mcase__w_just_test() {
    echo test
}

__distribution_mcase__w_just_diag() {
    echo diag
}

__distribution_mcase__w_just_cleanup() {
    echo cleanup
}

__distribution_mcase__w_dbg_start() {
    echo setup
    echo diag
}

__distribution_mcase__w_dbg_test() {
    echo test
    echo diag
}

__distribution_mcase__w_dbg_stop() {
    echo diag
    echo cleanup
}

__distribution_mcase__w_basic() {
    echo setup
    echo test
    echo diag
    echo cleanup
}

__distribution_mcase__w_tmt_upgrade() {
    if distribution_upgrade__at_src; then
        echo setup
        echo test
        echo diag
    elif distribution_upgrade__at_dst; then
        echo test
        echo diag
    else
        __distribution_mcase__error "invalid tmt_upgrade call; stage not applicable"
    fi
}

__distribution_mcase__w_morf_upg() {
    if distribution_upgrade__at_src; then
        echo setup
        echo test
        echo diag
    elif distribution_upgrade__at_dst; then
        echo test
        echo diag
    else
        __distribution_mcase__error "invalid morf call; stage not applicable"
    fi
}

distribution_mcase__LibraryLoaded() {
    #
    # Do nothing (handler mandated by beakerlib -- see BZ#1460035)
    #
    :
}

#----- SFDOC EMBEDDED POD BEGIN -----#
#
# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
# !! DO NOT EDIT section between this comment      !!
# !! and the end mark or YOUR CHANGES WILL BE LOST !!
# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
#
# The end mark should look like this:
#
#     #----- SFDOC EMBEDDED POD END -----#
#
# To update module documentation properly:
#
#  1. Edit in-code docstrings according to Docstrings section
#     of the Shellfu coding style guide:
#
#     <https://gitlab.com/vornet/shellfu/shellfu/-/blob/master/notes/style.md>
#
#  2. Run following command to re-build this section:
#
#         sfembed_pod -n "library/name" -i path/to/lib.sh
#
# Call sfembed_pod --help for more details.
#
# For Fedora-based distributions, sfembed_pod can be found in
# shellfu-devel package in this COPR:
#
# <https://copr.fedorainfracloud.org/coprs/netvor/shellfu/>
#

#shellcheck disable=SC2217
true <<'=cut'
=pod

=encoding utf8

=head1 NAME

ControlFlow/mcase - Modal test case

=head1 DESCRIPTION

Modal test case

This module brings modal approach to defining and running test
code.

Instead of writing your test case as a single body of code,
you will define handlers for different modes: setup, test, diag
and cleanup, and call a special function which will run all the
handlers in particular order.

The standard order is `setup`, `test`, `diag`, `cleanup` but the
runner function can amend this order based on instructions from test
scheduler, typically passed as environment variables.

Typical example of this is an upgrade test that will run `setup` and
`test` on first environment, then upgrade the system and run `test`
on upgraded system again.


=head1 HELP, MY TEST IS FAILING AND I DON'T UNDERSTAND THIS SORCERY!

If you encounter mcase-based test and want to understand what's
happening, usually the fastest way to get the grip is:

 1. Look at early log text around 'selected workflow:'  This is
    where the "workflow" is shown, ie. planned sequence of handlers

 2. All the test really does is just call these handlers in that order,
    wrapping them in phases.

 4. Open the test code.

    For every phase (setup, test, diag and cleanup), there is
    one function ("handler") named `distribution_mcase__test`
    etc. (Actually only 'test' is mandatory.)


=head1 GETTING STARTED

Here's what you need to do:

 1. Implement handlers:

        distribution_mcase__setup (optional)
        distribution_mcase__test
        distribution_mcase__diag (optional)
        distribution_mcase__cleanup (optional)

 2. Finally, run a single "magic" function, `distribution_mcase__run()`.
    This will take care of the rest.


=head1 EXAMPLE

    distribution_mcase__setup() {
        rlRun "mkdir /var/ftp"                    || return 1
        rlRun "cp testfile /var/ftp"              || return 1
        rlRun "useradd joe"                       || return 1
        rlRun "rlServiceRestart hypothetical_ftp  || return 1
        rlRun "rlServiceEnable hypothetical_ftp   || return 1
    }

    distribution_mcase__test() {
        rlRun "su -c 'hypo_ftp localhost 25 <<<\"get testfile\"' - joe"
        rlRun "diff /var/ftp/testfile /home/joe/testfile"
    }

    distribution_mcase__cleanup() {
        rlRun "rm -rf /var/ftp"
        rlRun "userdel joe"
        rlRun "rlServiceRestart hypothetical_ftp
    }


    rlJournalStart

        rlPhaseStartSetup
            rlImport distribution/mcase
        rlPhaseEnd

        distribution_mcase__run

    rlJournalEnd
    rlJournalPrint

Notice:

 *  The same test without ControlFlow/mcase would require lot of
    rlPhase*() calls.

 *  The setup is now responsive to situations when something is terribly
    wrong: the setup will now stop (causing test to be skipped) if
    any of the commands fail.


=head1 WORKFLOWS

By default, (`basic` workflow) handlers are called in this order:

    setup
    test
    diag
    cleanup

In various circumstances, it may be useful to tweak the order.  With
ControlFlow/mcase, you can have the runner function run handlers in
any order without need touch the test code, using *workflows*.

With ControlFlow/mcase, you can alter the order:

 *  using one of built-in workflows,
 *  providing your own workflow.

Note that all handlers except `test` are optional and are silently
skipped if missing.


=head2 Built-in workflows

To use a built-in workflow, set $distribution_mcase__workflow variable
to one of following values:

 *  `auto` - will let d/mcase choose workflow automatically.  This is
     the default value.

 *  `basic` - this is the default selection of `auto` workflow, if no
     other known modes (eg. upgrade mode) are detected.

    `basic` workflow runs handlers in natural order:

        setup
        test
        diag
        cleanup

 *  `just_setup`, `just_test`, `just_diag`, `just_cleanup` - these
    workflows run only single handler.

 *  `dbg_start`, `dbg_test`, `dbg_stop` - these workflows are handy when
    hacking on a test with an expensive setup and/or cleanup.

     *  `dbg_start` runs `setup` and `diag` only,
     *  `dbg_test` runs `test` and `diag` only.
     *  `and dbg_stop` runs `diag` and `cleanup` only.

    The idea is that you may want to run `dbg_start` once just to
    your testing machine, then possibly many times run `dbg_test`
    until you're happy with your test handler, then run `dbg_stop`
    to "close the circle".

 *  `tmt_upgrade` - if d/mcase detects that your test is running under
    upgrade mode of the TMT framework (/upgrade executor plugin), it
    will consult IN_PLACE_UPGRADE to decide which handlers to run.

    Normally this will mean `setup`, `test`, `diag` if the value of
    IN_PLACE_UPGRADE variable is `old`, and `test`, `diag` and `cleanup`
    if the value is `new` (upgraded distro).

 *  `morf_upg` - if d/mcase detects that your test is running under
    upgrade mode of the MORF framework (upgrade test), it will consult
    MORF to decide which handlers to run.

    Normally this will mean `setup`, `test`, `diag` on source distro,
    and `test`, `diag` and `cleanup` on destination (upgraded) distro.


=head1 PERSISTENCE AND WORKING DIRECTORY

Note that d/mcase will ensure that:

 *  All handlers run in the same directory, dedicated for given
    test case.

 *  Files are preserved from previous handler.

This means if one handler creates a file in its work directory ($PWD or
`pwd` in Bash), next one can read it.

The work directory is created by the distribution_mcase__run() function
and is a sub-directory of $distribution_mcase__root named either `mcase`,
or by name specified as CASE ID, specified as -I parameter of
distribution_mcase__run().

For example, following calls will work:

    distribution_mcase__setup() {
        echo "foo" >bar
    }

    distribution_mcase__test() {
        rlAssert "grep foo bar"
    }

    distribution_mcase__run

even in upgrade mode, where if `foo` was kept in a variable, it would
be lost.  Without passing any additional variables, both handlers will
run in */var/tmp/distribution_mcase/mcase*.

If the test code is parametrized using its own environment variables,
in order to avoid conflicts, it's recommended to create case id
containing all of the variables and pass it using the `-I` option:

    distribution_mcase__setup() {
        echo "$TEST_MODE" >bar
    }

    distribution_mcase__test() {
        rlAssert "grep $TEST_MODE bar"
    }

    distribution_mcase__run -I "$TEST_MODE"

That way the test code can be run with different TEST_MODE sequentially
without risk of "cross-contamination" between handlers.


=head1 RELICS COLLECTION

If your test code creates various test config and diagnostic files,
d/mcase can automatically collect them for you.  (Ie. you won't have
to rlFileSubmit() or rlBundleLogs() them.)

Auto-collection is enabled by passing `-c` to distribution_mcase__run()
and when enabled, files left over in the work directory after running
handlers, are collected into a single tarball: `mcase-relics.tar.gz`.

Exception from this are files created under `tmp` sub-directory (created
automatically by d/mcase); this directory is ignored when creating the
tarball.  If your test creates huge files, make sure to put them under
the `tmp` subdir before enabling the auto-collection feature.


=head1 THE WHY

Compared to traditional "linear" style, where you have all your test code
written command after command, tests implemented using d/mcase have multiple
advantages:

 *  far less code necessary,

 *  more flexible (the workflow can be customized, eg. skip cleanup,
    repeat test 100x, run in upgrade scenario..),

 *  "don't run test if setup failed" logic is used, possibly saving
    lot of resources,

 *  no need for boring formalities such as `rlPhaseStart`,

 *  moving code to functions enables you to short-cut by
    `return` keyword (=> clarity AND resource saving),

 *  the test is much easier to understand (if done well).



=head1 VARIABLES

=over 8


=item I<$distribution_mcase__workflow>

Default workflow to use


=item I<$distribution_mcase__root>

Test work dir root

Root directory where working directories for handlers are created.

See PERSISTENCE AND WORKING DIRECTORY for details.

=back


=head1 FUNCTIONS

=over 8


=item I<distribution_mcase__id()>

Print current case ID

Usage:

    distribution_mcase__id

Inside handler, this function will output CASEID.


=item I<distribution_mcase__run()>

Run all cases from distribution_mcase__enum()

Usage:

    distribution_mcase__run [-I CASEID] [-c] [-w WORKFLOW]

This function is the main launcher for tests.  It will perform roughly
following steps:

 1. Create run directory and chdir there.

    (The directory path is composed of $distribution_mcase__root
    and CASEID).

 2. Run all available handlers as defined by workflow.  With basic
    workflow this is:

     1. setup
     2. test
     3. diag
     4. cleanup

 3. chdir back

See also "GETTING STARTED" and "WORKFLOWS" sections.

The behavior can be altered using options:

  '-I CASEID' - Use case ID CASEID instead of the default one,
      'mcase'.

  '-P' - don't touch phases.  This means handlers must declare
      phases themselves, but can have multiple phases per handler

      Due to how beakerlib works, this means d/mcase can't implement
      logic of skipping test if setup failed, ie. all handlers will
      be ran unconditionally.

  '-S' - don't skip 'test' handler on setup failure.

      It's often a good practice (leading to smaller, easier to"
      understand test code) to only run critical code in asserts.
      Before using this option, consider whether non-critical code
      in setup handler could be ran "plainly", outside rlRun.

  '-c' - automatically create and submit of relics tarball. See
      RELICS COLLECTION.

  '-w WORKFLOW' - Force non-default workflow WORKFLOW. See "WORKFLOWS"
      section of this manual.


=item I<distribution_mcase__LibraryLoaded()>

Do nothing (handler mandated by beakerlib -- see BZ#1460035)

=back

=cut
#----- SFDOC EMBEDDED POD END -----#
