#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Author: Dalibor Pospisil <dapospis@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2021 Red Hat, Inc. All rights reserved.
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

# Include rhts environment
. /usr/bin/rhts-environment.sh || :
. /usr/share/beakerlib/beakerlib.sh || exit 1

rlJournalStart
  rlPhaseStartSetup && {
    rlRun "rlImport --all" || rlDie 'cannot continue'
    rlRun "rlImport $(basename "$(dirname "$(readlink -m "$0")")")" || rlDie 'cannot continue'
    rlRun "rlCheckMakefileRequires" || rlDie 'cannot continue'
    rlRun "TmpDir=\$(mktemp -d)" 0 "Creating tmp directory"
    rlRun "pushd $TmpDir"
  rlPhaseEnd; }

  rlPhaseStartTest && {
    sessionOpen
    rlRun "sessionRun 'false'" 1
    rlRun "sessionRun 'true'" 0
    rlRun "sessionRun '(exit 5)'" 5
    rlRun -s 'sessionRun "id"'
    rlAssertGrep 'uid=0(root)' $rlRun_LOG
    rm -f $rlRun_LOG
    rlRun "sessionSend 'for i in \`seq 4\`; do echo \$i; sleep 1; done'$'\r'"
    rlRun -s "sessionExpect 'seq 4'"
    rlRun "cat $rlRun_LOG"
    rlAssertGrep 'for i in `seq 4' $rlRun_LOG
    rlAssertNotGrep 'for i in `seq 4`' $rlRun_LOG
    rm -f $rlRun_LOG
    sleep 5
    rlRun -s "sessionExpect 4"
    rlRun "cat $rlRun_LOG"
    echo -en '`; do echo $i; sleep 1; done
1
2
3
4' > tmp
    rlRun  "diff -u tmp $rlRun_LOG"
    rm -f $rlRun_LOG
    rlRun -s 'sessionRun "id"'
    rlAssertGrep 'uid=0(root)' $rlRun_LOG
    rm -f $rlRun_LOG
    rlRun -s "sessionRun 'for i in \`seq 4\`; do echo -n \$i,; sleep 1; done; echo'"
    rlRun "cat $rlRun_LOG"
    echo -en '1,2,3,4,\n' > tmp
    rlRun "diff -u tmp $rlRun_LOG"
    rm -f $rlRun_LOG
    rlRun -s "sessionRun 'for i in \`seq 4\`; do echo -n \$i,; sleep 1; done'"
    rlRun "cat $rlRun_LOG"
    echo -en "1,2,3,4," > tmp
    rlRun "diff -u tmp $rlRun_LOG"
    rm -f $rlRun_LOG tmp
    rlRun "sessionRun --timeout 1 'sleep 2'" 254
    rlRun "sessionRun 'sleep 2'"
    sessionRunTIMEOUT=1
    rlRun "sessionRun 'sleep 2'" 254
    unset sessionRunTIMEOUT
    rlRun "sessionRun 'sleep 2'"
    rlLog "check regexp switches"
    sessionSend 'for (( i=0; i<=10; i++)); do echo -en "\na$i"; sleep 1; done; sleep 5'$'\r'
    rlRun 'sessionExpect --timeout 6 "a5"'
    rlRun 'DEBUG=1 sessionExpect --timeout 6 -nocase "a10"'
    sessionWaitAPrompt
    rlLog "send enter"
    rlRun 'sessionRun "(exit 5)"' 5
    rlRun "sessionRun '(exit \$?)'" 5
    rlRun "sessionSend '(exit 4)"$'\r'"'"
    sessionWaitAPrompt
    rlRun "sessionRun '(exit \$?)'" 4
    rlRun 'sessionSend "(exit 3)'$'\r''"'
    sessionWaitAPrompt
    rlRun "sessionRun '(exit \$?)'" 3
    rlRun 'sessionSend "(exit 6)"'; sessionSend $'\r'
    sessionWaitAPrompt
    rlRun "sessionRun '(exit \$?)'" 6
    rlRun 'sessionSend "(exit 7)
"'
    sessionWaitAPrompt
    rlRun "sessionRun '(exit \$?)'" 7
    rlLog "check very log command output"
    rlRun "sessionRun 'for (( i=0; i<10000; i++ )); do echo \"line \$i\"; done'"
    sessionClose
  rlPhaseEnd; }

  rlPhaseStartCleanup && {
    sessionCleanup
    rlRun "popd"
    rlRun 'rm -r $TmpDir' 0 'Removing tmp directory'
  rlPhaseEnd; }
rlJournalPrintText
rlJournalEnd
