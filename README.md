# Kleros Dispute Resolution - Phased Implementation

## How to Run
1. Make sure Solidity + Foundry is installed
2. Navigate to root directory
3. Run `forge test -vv`

## Phase 3 explanation

### SimpleKlerosPhase3: Simple Explanation

#### What Is It?

A decentralized court where jurors stake tokens, vote on disputes, and either **win money** (if they vote with majority) or **lose everything** (if they vote with minority).

---

#### The Flow

```
STAKE → CREATE DISPUTE → DRAW JURORS → COMMIT → REVEAL → FINALIZE
```

#### 1. Stake
Jurors lock tokens in the contract to become eligible.
```
J1 stakes 500, J2 stakes 300, J3 stakes 200
```

#### 2. Create Dispute
Anyone creates a dispute with evidence (IPFS link).

#### 3. Draw Jurors
Contract randomly selects jurors and **locks** their stakes. Their voting weight is **snapshot** at this moment.

#### 4. Commit (Secret Voting)
Each juror submits `hash(vote + salt)` — nobody can see anyone's vote yet.
```
J1: hash(1, "abc") → commits
J2: hash(1, "def") → commits  
J3: hash(2, "ghi") → commits
```

#### 5. Reveal
After commit deadline, jurors reveal their vote + salt. Contract verifies the hash matches.
```
Option1: 500 + 300 = 800 weighted votes
Option2: 200 weighted votes
```

#### 6. Finalize
```
Winner: Option1 (800 > 200)

Losers slashed:  J3 loses 200 tokens
Winners gain:    J1 gets 125 (5/8 of 200)
                 J2 gets 75  (3/8 of 200)

Final stakes:    J1: 625, J2: 375, J3: 0
```

---

#### Key Rules

| Rule | Why |
|------|-----|
| **Commit-reveal** | Prevents copying others' votes |
| **Weight snapshot** | Can't add stake after being selected |
| **Locked during dispute** | Can't withdraw while voting |
| **Non-revealers lose** | Forces participation |

---

#### The Economic Logic

```
"I think others will vote for the obvious truth"
        ↓
"If I vote the same, I'm in the majority"
        ↓
"I'll take money from the minority"
        ↓
Everyone votes honestly → System finds truth
```

That's the **Kleros loop** — economic self-interest drives honest behavior.

## Phase 3 results (output)
```
Ran 31 tests for test/SimpleKlerosPhase3Test.t.sol:SimpleKlerosPhase3Test
[PASS] testCannotCommitAfterDeadline() (gas: 437070)
[PASS] testCannotCommitTwice() (gas: 464149)
[PASS] testCannotCreateDisputeWithoutEnoughJurors() (gas: 1481703)
[PASS] testCannotDrawJurorsTwice() (gas: 432961)
[PASS] testCannotFinalizeBeforeRevealDeadline() (gas: 625016)
[PASS] testCannotRevealAfterDeadline() (gas: 463860)
[PASS] testCannotRevealBeforeCommitDeadline() (gas: 463470)
[PASS] testCannotRevealInvalidVoteValue() (gas: 463482)
[PASS] testCannotRevealTwice() (gas: 514611)
[PASS] testCannotRevealWithWrongSalt() (gas: 467315)
[PASS] testCannotRevealWithWrongVote() (gas: 466718)
[PASS] testCannotStakeBelowMinimum() (gas: 128523)
[PASS] testCannotStakeZero() (gas: 11708)
[PASS] testCannotUnstakeMoreThanStaked() (gas: 604053)
[PASS] testCannotUnstakeWhileLocked() (gas: 435769)
[PASS] testGetDisputeSummary() (gas: 129371)
[PASS] testGetJurorStake() (gas: 12444)
[PASS] testJurorListGrows() (gas: 141528)
[PASS] testNoOneReveals() (gas: 471552)
[PASS] testNonJurorCannotCommit() (gas: 437393)
[PASS] testNonJurorCannotReveal() (gas: 522816)
[PASS] testOption2Wins() (gas: 640556)
[PASS] testPhase3AllLoseIfAllMinority() (gas: 601290)
[PASS] testPhase3CanUnstakeAfterWinning() (gas: 660576)
[PASS] testPhase3MajorityWinsAndGetsReward() (gas: 649341)
[PASS] testPhase3NonRevealerLosesEverything() (gas: 595221)
[PASS] testPhase3ProportionalRewardDistribution() (gas: 640828)
[PASS] testPhase3TieNoRedistribution() (gas: 610355)
[PASS] testSingleRevealerTakesAll() (gas: 564139)
[PASS] testUnanimousVote() (gas: 611828)
[PASS] testVoteWeightSnapshot() (gas: 435420)
Suite result: ok. 31 passed; 0 failed; 0 skipped; finished in 4.83ms (5.34ms CPU time)
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
