## How to run

0) make sure that solidity + fordge is installed
1) make sure you are in the root directory
2) forge test -vv

## Outputs 
### Output for phase 1
Ran 6 tests for test/SimpleKlerosPhase1Test.t.sol:SimpleKlerosPhase1Test
[PASS] testCannotDoubleCommit() (gas: 334242)
[PASS] testCannotRevealWithWrongSalt() (gas: 337137)
[PASS] testCannotVoteWithoutSufficientBalance() (gas: 44861)
[PASS] testCommitRevealSecrecy() (gas: 407935)
[PASS] testPhase1MajorityWins() (gas: 618653)
[PASS] testPhase1TokenWeightedVoting() (gas: 601307)
Suite result: ok. 6 passed; 0 failed; 0 skipped; finished in 1.26ms (1.39ms CPU time)

### Output for phase 2
Ran 8 tests for test/SimpleKlerosPhase2Test.t.sol:SimpleKlerosPhase2Test
[PASS] testCanStakeMultipleTimes() (gas: 140596)
[PASS] testCanUnstakeAfterFinalization() (gas: 622710)
[PASS] testCannotStakeBelowMinimum() (gas: 128070)
[PASS] testCannotUnstakeMoreThanStaked() (gas: 15505)
[PASS] testCannotUnstakeWhileLocked() (gas: 367772)
[PASS] testPhase2MajorityWins() (gas: 621757)
[PASS] testPhase2NoRedistribution() (gas: 629276)
[PASS] testPhase2StakeBasedWeighting() (gas: 615316)
Suite result: ok. 8 passed; 0 failed; 0 skipped; finished in 1.34ms (1.92ms CPU time)

### Output for phase 3
Ran 6 tests for test/SimpleKlerosPhase3Test.t.sol:SimpleKlerosPhase3Test
[PASS] testPhase3AllLoseIfAllMinority() (gas: 600505)
[PASS] testPhase3CanUnstakeAfterWinning() (gas: 657005)
[PASS] testPhase3MajorityWinsAndGetsReward() (gas: 645395)
[PASS] testPhase3NonRevealerLosesEverything() (gas: 569765)
[PASS] testPhase3ProportionalRewardDistribution() (gas: 637147)
[PASS] testPhase3TieNoRedistribution() (gas: 609922)
Suite result: ok. 6 passed; 0 failed; 0 skipped; finished in 1.32ms (1.60ms CPU time)


