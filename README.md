# Kleros Dispute Resolution - Phased Implementation

## How to Run
1. Make sure Solidity + Foundry is installed
2. Navigate to root directory
3. Run `forge test -vv`

## Test Results

### Phase 1
```
Ran 6 tests for test/SimpleKlerosPhase1Test.t.sol:SimpleKlerosPhase1Test
[PASS] testCannotDoubleCommit() (gas: 334242)
[PASS] testCannotRevealWithWrongSalt() (gas: 337137)
[PASS] testCannotVoteWithoutSufficientBalance() (gas: 44861)
[PASS] testCommitRevealSecrecy() (gas: 407935)
[PASS] testPhase1MajorityWins() (gas: 618653)
[PASS] testPhase1TokenWeightedVoting() (gas: 601307)
Suite result: ok. 6 passed; 0 failed; 0 skipped; finished in 1.26ms
```

### Phase 2
```
Ran 8 tests for test/SimpleKlerosPhase2Test.t.sol:SimpleKlerosPhase2Test
[PASS] testCanStakeMultipleTimes() (gas: 140596)
[PASS] testCanUnstakeAfterFinalization() (gas: 622710)
[PASS] testCannotStakeBelowMinimum() (gas: 128070)
[PASS] testCannotUnstakeMoreThanStaked() (gas: 15505)
[PASS] testCannotUnstakeWhileLocked() (gas: 367772)
[PASS] testPhase2MajorityWins() (gas: 621757)
[PASS] testPhase2NoRedistribution() (gas: 629276)
[PASS] testPhase2StakeBasedWeighting() (gas: 615316)
Suite result: ok. 8 passed; 0 failed; 0 skipped; finished in 1.34ms
```

### Phase 3
```
Ran 6 tests for test/SimpleKlerosPhase3Test.t.sol:SimpleKlerosPhase3Test
[PASS] testPhase3AllLoseIfAllMinority() (gas: 600505)
[PASS] testPhase3CanUnstakeAfterWinning() (gas: 657005)
[PASS] testPhase3MajorityWinsAndGetsReward() (gas: 645395)
[PASS] testPhase3NonRevealerLosesEverything() (gas: 569765)
[PASS] testPhase3ProportionalRewardDistribution() (gas: 637147)
[PASS] testPhase3TieNoRedistribution() (gas: 609922)
Suite result: ok. 6 passed; 0 failed; 0 skipped; finished in 1.32ms
```
### All the tests for Phase3

| Test | What it checks |
|------|----------------|
| `testPhase3MajorityWinsAndGetsReward` | Minority loses stake, majority gains it proportionally |
| `testPhase3TieNoRedistribution` | 500 vs 500 weighted vote → no one gets slashed |
| `testPhase3NonRevealerLosesEverything` | Juror who commits but doesn't reveal loses entire stake |
| `testPhase3ProportionalRewardDistribution` | Rewards match stake ratio (5:3 stake → 5:3 reward) |
| `testPhase3AllLoseIfAllMinority` | Verifies 500 vs 500 is correctly detected as tie |
| `testPhase3CanUnstakeAfterWinning` | Winner can withdraw rewards as real tokens |

## Security & Access Control

| Test | What it checks |
|------|----------------|
| `testCannotCommitTwice` | Same juror can't submit two commits |
| `testNonJurorCannotCommit` | Random address blocked from voting |
| `testNonJurorCannotReveal` | Random address blocked from reveal phase |
| `testCannotRevealWithWrongSalt` | Wrong salt → reveal rejected |
| `testCannotRevealWithWrongVote` | Can't lie about what you committed |
| `testCannotRevealTwice` | No double reveals |
| `testCannotRevealInvalidVoteValue` | Vote must be 1 or 2, not 0 or 3 |

## Phase Timing Enforcement

| Test | What it checks |
|------|----------------|
| `testCannotRevealBeforeCommitDeadline` | Must wait for commit phase to end |
| `testCannotCommitAfterDeadline` | Late commits rejected |
| `testCannotRevealAfterDeadline` | Late reveals rejected |
| `testCannotFinalizeBeforeRevealDeadline` | Can't end dispute early |
| `testCannotDrawJurorsTwice` | Jurors drawn only once per dispute |

## Staking Mechanics

| Test | What it checks |
|------|----------------|
| `testCannotUnstakeWhileLocked` | Can't withdraw while in active dispute |
| `testCannotStakeBelowMinimum` | Must stake ≥ 100 tokens |
| `testCannotStakeZero` | Zero stake rejected |
| `testCannotUnstakeMoreThanStaked` | Can't withdraw more than you have |

## Edge Cases

| Test | What it checks |
|------|----------------|
| `testUnanimousVote` | All vote same → no losers, stakes unchanged |
| `testSingleRevealerTakesAll` | One revealer wins all 1000 tokens |
| `testNoOneReveals` | Zero reveals → Undecided ruling |
| `testOption2Wins` | Option2 can win (not just Option1) |
| `testCannotCreateDisputeWithoutEnoughJurors` | Need enough stakers before creating disputes |
| `testJurorListGrows` | New stakers added to juror pool |
| `testVoteWeightSnapshot` | Weight captured at draw time, not reveal time |

## View Function Tests

| Test | What it checks |
|------|----------------|
| `testGetDisputeSummary` | Returns correct phase, ruling, vote counts |
| `testGetJurorStake` | Returns correct stake amount and lock status |
