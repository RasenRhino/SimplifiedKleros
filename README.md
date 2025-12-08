# Kleros Dispute Resolution - Phased Implementation

## How to Run

```bash
# Install Foundry if not already installed
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Run all tests
forge test -vv

# Run with detailed logs
forge test -vvv

# Run specific phase tests
forge test --match-path test/SimpleKlerosPhase3Test.t.sol -vv

# Run specific test
forge test --match-test "testMajorityWinsAndGetsReward" -vvv

# Run weighted selection test with RANDOM seed (different results each run!)
RANDOM_SEED=$RANDOM forge test --match-test "testWeightedSelectionWithMultipleRandomSeeds" -vvv

# Run with specific seed (reproducible results)
RANDOM_SEED=12345 forge test --match-test "testWeightedSelectionWithMultipleRandomSeeds" -vvv

# Run fuzz tests (256 runs with random inputs)
forge test --match-test "testFuzz_" -vv
```

---

## Phase 3: SimpleKlerosPhase3

### What Is It?

A decentralized court where jurors stake tokens, vote on disputes, and either **win money** (if they vote with majority) or **lose everything** (if they vote with minority).

### Key Features

| Feature | Description |
|---------|-------------|
| **Weighted Random Selection** | Higher stake = higher chance of being selected as juror |
| **Multi-Selection** | Same juror can be picked multiple times (each pick = +1 voting power) |
| **Odd Number of Draws** | Always odd (3, 5, 7...) to prevent ties |
| **Stake Locking** | Each selection locks `minStake` tokens until dispute resolves |
| **Commit-Reveal Voting** | Secret votes prevent copying others |
| **Stake Redistribution** | Losers are slashed, winners gain proportionally |

---

### The Flow

```
STAKE → CREATE DISPUTE → DRAW JURORS → COMMIT → REVEAL → FINALIZE
```

#### 1. Stake
Jurors lock tokens in the contract to become eligible.
```
Alice stakes 500, Bob stakes 300, Charlie stakes 200
Total: 1000 tokens in the pool
```

#### 2. Create Dispute
Anyone creates a dispute with evidence (IPFS link).

#### 3. Draw Jurors (Weighted Random)
Contract performs N random draws (N must be odd, e.g., 3).
- Each draw selects a juror with probability proportional to their **available** stake
- Same juror can be picked multiple times
- Each selection locks `minStake` (100 tokens)

Example with 3 draws:
```
Draw 1: Alice (500/1000 = 50% chance) → Selected! Locks 100 tokens
Draw 2: Alice again (400/900 = 44% chance) → Selected! Locks another 100
Draw 3: Bob (300/800 = 37.5% chance) → Selected! Locks 100

Result: Alice has voting weight 2, Bob has voting weight 1
```

#### 4. Commit (Secret Voting)
Each juror submits `hash(vote + salt)` — nobody can see anyone's vote yet.
```
Alice: hash(1, "abc") → commits (weight: 2)
Bob:   hash(2, "def") → commits (weight: 1)
```

#### 5. Reveal
After commit deadline, jurors reveal their vote + salt. Contract verifies the hash matches.
```
Option 1: 2 votes (Alice's weight)
Option 2: 1 vote (Bob's weight)
```

#### 6. Finalize
```
Winner: Option 1 (2 > 1)

Alice voted correctly → Gains Bob's slashed stake
Bob voted incorrectly → Loses his locked 100 tokens

Alice: 500 + 100 = 600 tokens
Bob: 300 - 100 = 200 tokens
```

---

### Stake Terminology

```
┌─────────────────────────────────────────────────────────────────┐
│  amount (Total Stake)     = All tokens you've deposited        │
│  lockedAmount             = Tokens frozen in active disputes   │
│  available                = amount - lockedAmount              │
│                           = What can be selected or withdrawn  │
└─────────────────────────────────────────────────────────────────┘
```

---

### Key Rules

| Rule | Why |
|------|-----|
| **Commit-reveal** | Prevents copying others' votes |
| **Weighted selection** | Higher stake = more skin in the game |
| **Multi-selection** | Natural weighting without complex math |
| **Odd draws only** | Prevents ties in voting |
| **Locked during dispute** | Can't withdraw while voting |
| **Non-revealers lose** | Forces participation |
| **Recalculate stake each draw** | Prevents stale stake bugs |

---

### The Economic Logic

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

---

## Bug Fixes Implemented

Three critical bugs were identified and fixed in `SimpleKlerosPhase3`:

### Bug 1: Stale `totalStake` in Draw Loop
**Problem:** `totalStake` was calculated once before the loop, but each selection locks tokens, reducing available stake.
```
Draw 1: target = rand % 1000 → selects juror, locks 100
Draw 2: target = rand % 1000 → but actual available is now 900!
        target could be 950 → can't reach → falls to FALLBACK
```
**Fix:** Recalculate `currentTotalStake = _getTotalStake()` at the start of each draw iteration.

### Bug 2: DoS on Insufficient Stake
**Problem:** If a selected juror didn't have enough stake, the entire transaction reverted.
```solidity
require(js.amount >= js.lockedAmount + minStake, "insufficient"); // ← Reverts!
```
**Fix:** Added retry mechanism with `nonce` and `maxRetries`. If a juror can't be selected, try again with a different random value.

### Bug 3: Fallback Checks Total Instead of Available
**Problem:** Fallback returned the first juror with sufficient **total** stake, but they might have it all locked.
```solidity
if (stakes[jurorList[i]].amount >= minStake) { // Wrong! Checks total
    return jurorList[i];
}
```
**Fix:** Check available stake: `if (availableFallback >= minStake)`.

---

## Test Results

```
Ran 37 tests for test/SimpleKlerosPhase3Test.t.sol:SimpleKlerosPhase3Test
[PASS] testCanUnstakeAfterDispute() (gas: 621354)
[PASS] testCannotCommitAfterDeadline() (gas: 459278)
[PASS] testCannotCommitTwice() (gas: 489529)
[PASS] testCannotDrawJurorsTwice() (gas: 454596)
[PASS] testCannotFinalizeBeforeRevealDeadline() (gas: 587737)
[PASS] testCannotRevealAfterDeadline() (gas: 484567)
[PASS] testCannotRevealBeforeCommitDeadline() (gas: 485431)
[PASS] testCannotRevealInvalidVoteValue() (gas: 482701)
[PASS] testCannotRevealTwice() (gas: 536865)
[PASS] testCannotRevealWithWrongSalt() (gas: 494080)
[PASS] testCannotRevealWithWrongVote() (gas: 491979)
[PASS] testCannotStakeBelowMinimum() (gas: 140806)
[PASS] testCannotStakeZero() (gas: 20552)
[PASS] testCannotUnstakeMoreThanAvailable() (gas: 587237)
[PASS] testCannotUnstakeWhileLocked() (gas: 462017)
[PASS] testFix_CorrectTotalStakeAfterMultipleSelections() (gas: 499059)
[PASS] testFix_FallbackChecksAvailableNotTotalStake() (gas: 2427413)
[PASS] testFix_NoDoSWhenJurorHasInsufficientStake() (gas: 4105592)
[PASS] testFix_StaleTotalStakeInDrawLoop() (gas: 2047512)
[PASS] testFuzz_WeightedSelectionFavorsHigherStakes(uint256) (runs: 256)
[PASS] testGetDisputeSummary() (gas: 164745)
[PASS] testGetJurorStake() (gas: 22450)
[PASS] testGetTotalSelections() (gas: 449658)
[PASS] testJurorCanBeSelectedMultipleTimes() (gas: 2014404)
[PASS] testLoserGetsSlashed() (gas: 2518032)
[PASS] testMajorityWinsAndGetsReward() (gas: 660814)
[PASS] testNonJurorCannotCommit() (gas: 457756)
[PASS] testNonJurorCannotReveal() (gas: 511611)
[PASS] testNonRevealerLosesStake() (gas: 2476088)
[PASS] testNumDrawsMustBeOdd() (gas: 52057)
[PASS] testNumDrawsMustBePositive() (gas: 51767)
[PASS] testStakeLockedIsMinStakeTimesSelections() (gas: 475850)
[PASS] testTieNoRedistribution() (gas: 2097271)
[PASS] testTieResultsInUndecided() (gas: 503175)
[PASS] testTotalSelectionsEqualsNumDraws() (gas: 467457)
[PASS] testWeightedSelectionFavorsHigherStakes() (gas: 6263945)
[PASS] testWeightedSelectionWithMultipleRandomSeeds() (gas: 15534933)

Suite result: ok. 37 passed; 0 failed; 0 skipped
```

---

## Test Categories

### Core Functionality Tests (5 tests)

| Test | What It Checks |
|------|----------------|
| `testNumDrawsMustBeOdd` | Number of juror draws must be odd (1, 3, 5...) |
| `testNumDrawsMustBePositive` | Cannot create court with 0 draws |
| `testTotalSelectionsEqualsNumDraws` | Total selections equals configured numDraws |
| `testJurorCanBeSelectedMultipleTimes` | Same juror can be picked multiple times |
| `testStakeLockedIsMinStakeTimesSelections` | Locked stake = minStake × selection count |

### Weighted Selection Tests (3 tests)

| Test | What It Checks |
|------|----------------|
| `testWeightedSelectionFavorsHigherStakes` | Higher stake jurors selected more often (deterministic) |
| `testWeightedSelectionWithMultipleRandomSeeds` | Shows varying results with external random seeds |
| `testFuzz_WeightedSelectionFavorsHigherStakes` | Fuzz test - runs 256 times with random seeds |

**Running with Different Seeds:**
```bash
# Different results each run:
RANDOM_SEED=$RANDOM forge test --match-test "testWeightedSelectionWithMultipleRandomSeeds" -vvv

# Example outputs with different seeds:
# Seed 111:  Alice 7/15, Bob 5/15, Charlie 3/15
# Seed 999:  Alice 8/15, Bob 2/15, Charlie 5/15
# Seed 17032: Alice 7/15, Bob 4/15, Charlie 4/15
```

### Voting & Reward Distribution Tests (6 tests)

| Test | What It Checks |
|------|----------------|
| `testMajorityWinsAndGetsReward` | Majority wins, minority gets slashed |
| `testLoserGetsSlashed` | Losing juror loses their locked stake |
| `testNonRevealerLosesStake` | Not revealing = automatic loss |
| `testTieNoRedistribution` | Single juror case handling |
| `testTieResultsInUndecided` | Zero reveals (0 vs 0) = Undecided ruling |
| `testCanUnstakeAfterDispute` | Winners can withdraw after dispute ends |

### Security & Access Control Tests (7 tests)

| Test | What It Checks |
|------|----------------|
| `testCannotCommitTwice` | Same juror can't submit two commits |
| `testNonJurorCannotCommit` | Random address blocked from voting |
| `testNonJurorCannotReveal` | Random address blocked from reveal |
| `testCannotRevealWithWrongSalt` | Wrong salt → reveal rejected |
| `testCannotRevealWithWrongVote` | Can't lie about committed vote |
| `testCannotRevealTwice` | No double reveals |
| `testCannotRevealInvalidVoteValue` | Vote must be 1 or 2 |

### Phase Timing Enforcement Tests (5 tests)

| Test | What It Checks |
|------|----------------|
| `testCannotRevealBeforeCommitDeadline` | Must wait for commit phase to end |
| `testCannotCommitAfterDeadline` | Late commits rejected |
| `testCannotRevealAfterDeadline` | Late reveals rejected |
| `testCannotFinalizeBeforeRevealDeadline` | Can't end dispute early |
| `testCannotDrawJurorsTwice` | Jurors drawn only once per dispute |

### Staking Mechanics Tests (4 tests)

| Test | What It Checks |
|------|----------------|
| `testCannotUnstakeWhileLocked` | Can't withdraw during active dispute |
| `testCannotStakeBelowMinimum` | Must stake ≥ minStake tokens |
| `testCannotStakeZero` | Zero stake rejected |
| `testCannotUnstakeMoreThanAvailable` | Can't withdraw more than unlocked |

### Bug Fix Verification Tests (4 tests)

| Test | What It Checks |
|------|----------------|
| `testFix_StaleTotalStakeInDrawLoop` | totalStake recalculated each draw |
| `testFix_NoDoSWhenJurorHasInsufficientStake` | Retry mechanism prevents DoS |
| `testFix_CorrectTotalStakeAfterMultipleSelections` | Stake tracking after multi-selection |
| `testFix_FallbackChecksAvailableNotTotalStake` | Fallback checks available, not total stake |

### View Function Tests (3 tests)

| Test | What It Checks |
|------|----------------|
| `testGetDisputeSummary` | Returns correct phase, ruling, vote counts |
| `testGetJurorStake` | Returns correct stake amount and lock status |
| `testGetTotalSelections` | Returns correct total selections |

---

## Known Limitations

| Issue | Description |
|-------|-------------|
| **Confidence Attack** | If stake > minStake, wealthy jurors can overwhelm votes |
| **Whale Manipulation** | Large token holders can dominate juror selection |
| **No Hedging** | All eggs in one basket even with multiple selections |
| **Rounding Errors** | Some edge cases have minor rounding issues |
| **No Concurrent Disputes** | Only one dispute at a time per juror |
| **No Appeals** | Next step should be to implement appeals |

---

## File Structure

```
src/
├── SimpleKlerosPhase1.sol   # Basic staking & commit-reveal
├── SimpleKlerosPhase2.sol   # Added juror selection
├── SimpleKlerosPhase3.sol   # Full weighted selection & multi-select
└── TestToken.sol            # Mock ERC20 for testing

test/
├── SimpleKlerosPhase1Test.t.sol
├── SimpleKlerosPhase2Test.t.sol
└── SimpleKlerosPhase3Test.t.sol   # 37 tests
```

---
