#!/bin/bash

# ============================================
# SimpleKleros Core Tests Runner
# ============================================
# This script runs the 4 core demonstration tests
# that showcase the main functionality of the system.
# ============================================

set -e

echo "============================================"
echo "  SimpleKleros - Core Tests"
echo "============================================"
echo ""

# Default random seed (can be overridden)
SEED=${RANDOM_SEED:-$RANDOM}

echo "Running with RANDOM_SEED=$SEED"
echo ""

# Core Test 1: Weighted Random Selection
echo "--------------------------------------------"
echo "TEST 1: Weighted Selection (Random Seed)"
echo "  Shows that higher stake = higher selection chance"
echo "--------------------------------------------"
RANDOM_SEED=$SEED forge test --match-test "testWeightedSelectionWithMultipleRandomSeeds" -vvv
echo ""

# Core Test 2: Majority Wins
echo "--------------------------------------------"
echo "TEST 2: Majority Wins and Gets Reward"
echo "  Shows that majority voters win and get rewards"
echo "--------------------------------------------"
forge test --match-test "testMajorityWinsAndGetsReward" -vvv
echo ""

# Core Test 3: Loser Gets Slashed
echo "--------------------------------------------"
echo "TEST 3: Loser Gets Slashed"
echo "  Shows that minority voters lose their stake"
echo "--------------------------------------------"
forge test --match-test "testLoserGetsSlashed" -vvv
echo ""

# Core Test 4: Non-Revealer Loses Stake
echo "--------------------------------------------"
echo "TEST 4: Non-Revealer Loses Stake"
echo "  Shows that not revealing = automatic loss"
echo "--------------------------------------------"
forge test --match-test "testNonRevealerLosesStake" -vvv
echo ""

echo "============================================"
echo "  All Core Tests Completed!"
echo "============================================"

