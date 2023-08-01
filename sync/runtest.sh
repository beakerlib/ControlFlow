#!/bin/bash

# Include Beaker environment
. /usr/bin/rhts-environment.sh || :
. /usr/share/beakerlib/beakerlib.sh || exit 1


rlJournalStart
  rlPhaseStartSetup
    . $TMT_TOPOLOGY_BASH
    rlRun "env"
    rlRun "env | grep -i ^tmt_"
    rlRun "cat $TMT_TOPOLOGY_BASH"
    rlRun "rlImport ." || rlDie "cannot continue"
  rlPhaseEnd

  rlPhaseStartTest "pure flag"
    syncIsServer && rlRun "DEBUG=1 syncSet test1"
    syncIsClient && rlRun "DEBUG=1 syncExp test1"
  rlPhaseEnd

  rlPhaseStartTest "with message"
    syncIsClient && rlRun "DEBUG=1 syncSet test2 'test message'"
    syncIsServer && {
      rlRun -s "DEBUG=1 syncExp test2"
      rlAssertGrep 'test message' $rlRun_LOG
    }
  rlPhaseEnd

  rlPhaseStartTest "with stdin"
    syncIsServer && rlRun "echo test message2 | (DEBUG=1 syncSet test3 -)"
    syncIsClient && {
      rlRun -s "DEBUG=1 syncExp test3"
      rlAssertGrep 'test message2' $rlRun_LOG
    }
  rlPhaseEnd

  rlPhaseStartTest "omni-directional sync"
    rlRun "DEBUG=1 syncSynchronize"
  rlPhaseEnd

  rlPhaseStartTest "the other side result"
    rlRun "syncSet SYNC_RESULT $(rlGetTestState; echo $?)"
    rlAssert0 'check ther the other site finished successfuly' $(DEBUG=1 syncExp SYNC_RESULT)
  rlPhaseEnd

  rlPhaseStartTest "the other sides result"
    rlRun "syncResults"
  rlPhaseEnd

rlJournalPrintText
rlJournalEnd
