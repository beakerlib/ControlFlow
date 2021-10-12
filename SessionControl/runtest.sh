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
    rlRun "rlImport SessionControl" || rlDie 'cannot continue'
    rlRun "rlCheckMakefileRequires" || rlDie 'cannot continue'
    rlRun "TmpDir=\$(mktemp -d)" 0 "Creating tmp directory"
    rlRun "pushd $TmpDir"
  rlPhaseEnd; }

  rlPhaseStartTest && {
    sesOpen
    rlRun "sesRun 'false'" 1
    rlRun "sesRun 'true'" 0
    rlRun "sesRun '(exit 5)'" 5
    rlRun -s 'sesRun "id"'
    rlAssertGrep 'uid=0(root)' $rlRun_LOG
    rm -f $rlRun_LOG
    rlRun "sesSend 'for i in \`seq 4\`; do echo \$i; sleep 1; done'$'\r'"
    rlRun -s "sesExpect 'seq 4'"
    rlRun "cat $rlRun_LOG"
    rlAssertGrep 'for i in `seq 4' $rlRun_LOG
    rlAssertNotGrep 'for i in `seq 4`' $rlRun_LOG
    rm -f $rlRun_LOG
    sleep 5
    rlRun -s "sesExpect 4"
    rlRun "cat $rlRun_LOG"
    echo -en '`; do echo $i; sleep 1; done
1
2
3
4' > tmp
    rlRun  "diff -u tmp $rlRun_LOG"
    rm -f $rlRun_LOG
    rlRun -s 'sesRun "id"'
    rlAssertGrep 'uid=0(root)' $rlRun_LOG
    rm -f $rlRun_LOG
    rlRun -s "sesRun 'for i in \`seq 4\`; do echo -n \$i,; sleep 1; done; echo'"
    rlRun "cat $rlRun_LOG"
    echo -en '1,2,3,4,\n' > tmp
    rlRun "diff -u tmp $rlRun_LOG"
    rm -f $rlRun_LOG
    rlRun -s "sesRun 'for i in \`seq 4\`; do echo -n \$i,; sleep 1; done'"
    rlRun "cat $rlRun_LOG"
    echo -en "1,2,3,4," > tmp
    rlRun "diff -u tmp $rlRun_LOG"
    rm -f $rlRun_LOG tmp
    sesClose
  rlPhaseEnd; }

  rlPhaseStartCleanup && {
    sesCleanup
    rlRun "popd"
    rlRun 'rm -r $TmpDir' 0 'Removing tmp directory'
  rlPhaseEnd; }
rlJournalPrintText
rlJournalEnd
