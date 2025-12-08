# Kleros Dispute Resolution - Phased Implementation

**[Read the Full Report](report.md)** - Detailed analysis, architecture, and gap analysis. 
<br>
**Please view it on our github: https://github.com/DanMint/DistributedSystemsFinalProject**

---

## Quick Start

### Option 1: Run with Docker 

```bash

# Run only the 4 core demonstration tests
docker compose run core-tests

# Run all tests (37 tests)
docker compose run tests


# Run with random seed (different results each time) , ONLY used for random juror selection test if you want to give your own random seed. Fuzz testing command mentioned below.
RANDOM_SEED=$RANDOM docker compose run core-tests

# Run all tests with maximum verbosity , helpful if you want to see gas fees and nuanced transaction data. Currently out of the purview of our implementaion
docker compose run all-verbose

# Run fuzz tests (256 iterations) , ONLY used for random juror selection test. 
docker compose run fuzz-tests

```

### Option 2: Run Locally (Requires Foundry)

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Run all tests
forge test -vv

# Run core tests script
chmod +x run_core_tests.sh
./run_core_tests.sh

# Run with random seed
RANDOM_SEED=$RANDOM ./run_core_tests.sh
```

---

## Core Tests (4 Key Demonstrations)

These 4 tests demonstrate the essential functionality of the Kleros dispute system:

| # | Test | What It Demonstrates |
|---|------|----------------------|
| 1 | `testWeightedSelectionWithMultipleRandomSeeds` | Higher stake = higher chance of being selected as juror |
| 2 | `testMajorityWinsAndGetsReward` | Majority voters win and receive slashed stake from losers |
| 3 | `testLoserGetsSlashed` | Minority voters lose their locked stake |
| 4 | `testNonRevealerLosesStake` | Jurors who don't reveal their vote automatically lose |

### Run Core Tests Only

**With Docker:**
```bash
docker compose run core-tests
```

**Locally:**
```bash
./run_core_tests.sh

# Or manually:
forge test --match-test "testWeightedSelectionWithMultipleRandomSeeds" -vvv
forge test --match-test "testMajorityWinsAndGetsReward" -vvv
forge test --match-test "testLoserGetsSlashed" -vvv
forge test --match-test "testNonRevealerLosesStake" -vvv
```

---

## All Test Commands

### Local Commands (Requires Foundry)

```bash
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

### Docker Commands (No Installation Required)

```bash
# Build the Docker image (done automatically on first run)
docker compose build

# Run all tests (37 tests)
docker compose run tests

# Run core tests only (4 key demonstrations)
docker compose run core-tests

# Run with random seed (different results each time)
RANDOM_SEED=$RANDOM docker compose run core-tests

# Run all tests with maximum verbosity
docker compose run all-verbose

# Run fuzz tests (256 iterations)
docker compose run fuzz-tests

# Run Phase 3 tests only
docker compose run phase3-tests
```

### Rebuild & Cleanup Commands

```bash
# Force rebuild (use after code changes)
docker compose build --no-cache

# Rebuild specific service
docker compose build --no-cache tests

# Remove all containers
docker compose down

# Remove containers + images (full cleanup)
docker compose down --rmi all

# Remove containers + images + volumes (complete reset)
docker compose down --rmi all --volumes

# Remove orphan containers
docker compose down --remove-orphans

# View running containers
docker compose ps

# View logs
docker compose logs
```

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
Anyone creates a dispute with evidence 

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


## Test Categories

### Core Demonstration Tests (4 tests) 

| Test | What It Demonstrates |
|------|----------------------|
| `testWeightedSelectionWithMultipleRandomSeeds` | Weighted random juror selection |
| `testMajorityWinsAndGetsReward` | Majority wins, gets slashed stake |
| `testLoserGetsSlashed` | Minority loses their stake |
| `testNonRevealerLosesStake` | Not revealing = automatic loss |

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
| `testWeightedSelectionFavorsHigherStakes` | Deterministic - uses fixed block number each time for reproducibility |
| `testWeightedSelectionWithMultipleRandomSeeds` | Shows varying results with external random seeds |
| `testFuzz_WeightedSelectionFavorsHigherStakes(uint256 seed)` | **Fuzz test** - runs 256 times with random seeds |

#### Fuzz Testing

The function `testFuzz_WeightedSelectionFavorsHigherStakes(uint256 seed)` is a **fuzz test**. Foundry automatically:
- Runs it **256 times** (default)
- Provides a **different random `seed`** each run
- Tests that weighted selection works correctly across many random scenarios

```bash
# Run fuzz tests
forge test --match-test "testFuzz_" -vv

# Output shows 256 runs:
# [PASS] testFuzz_WeightedSelectionFavorsHigherStakes(uint256) (runs: 256)
```

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

## File Structure

```
├── Dockerfile              # Docker image for running tests
├── docker-compose.yml      # Docker services for different test modes
├── run_core_tests.sh       # Script to run 4 core tests locally
├── foundry.toml            # Foundry configuration
│
├── src/
│   ├── SimpleKlerosPhase3.sol   # Full weighted selection & multi-select
│   └── TestToken.sol            # Mock ERC20 for testing
│
├── test/
│   └── SimpleKlerosPhase3Test.t.sol   # 37 tests
│
└── lib/
    └── forge-std/               # Foundry standard library
```

---
