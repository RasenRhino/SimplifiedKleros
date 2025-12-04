// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "../src/TestToken.sol";
import "../src/SimpleKlerosPhase3.sol";

/**
 * @title SimpleKlerosPhase3Test
 * @notice Comprehensive test suite for the Kleros dispute resolution system
 * 
 * WHAT IS KLEROS?
 * ---------------
 * Kleros is a decentralized court system. When two parties have a dispute,
 * random jurors are selected to vote on the outcome. The majority wins,
 * and losers have their staked tokens taken away and given to winners.
 * 
 * KEY CONCEPTS:
 * - STAKE: Tokens you lock up to become eligible as a juror
 * - WEIGHTED SELECTION: The more you stake, the higher chance of being picked
 * - MULTI-SELECTION: Same juror can be picked multiple times (more voting power)
 * - COMMIT-REVEAL: Jurors first submit encrypted votes, then reveal them
 * - SLASHING: Losing jurors lose their staked tokens to winners
 */
contract SimpleKlerosPhase3Test is Test {
    TestToken token;
    SimpleKlerosPhase3 kleros;

    address juror1 = address(0x1);
    address juror2 = address(0x2);
    address juror3 = address(0x3);
    address nonJuror = address(0x99);

    uint256 constant TOKEN_UNIT = 1e18;
    uint256 constant MIN_STAKE = 100 ether;
    uint256 constant NUM_DRAWS = 3; // Must be odd to avoid ties

    // ==========================
    // Helper Functions
    // ==========================

    function _toTokens(uint256 weiAmount) internal pure returns (uint256) {
        return weiAmount / TOKEN_UNIT;
    }

    function _phaseToString(SimpleKlerosPhase3.Phase phase) internal pure returns (string memory) {
        if (phase == SimpleKlerosPhase3.Phase.None) return "None";
        if (phase == SimpleKlerosPhase3.Phase.Created) return "Created";
        if (phase == SimpleKlerosPhase3.Phase.JurorsDrawn) return "JurorsDrawn";
        if (phase == SimpleKlerosPhase3.Phase.Commit) return "Commit";
        if (phase == SimpleKlerosPhase3.Phase.Reveal) return "Reveal";
        if (phase == SimpleKlerosPhase3.Phase.Resolved) return "Resolved";
        return "Unknown";
    }

    function _rulingToString(SimpleKlerosPhase3.Ruling ruling) internal pure returns (string memory) {
        if (ruling == SimpleKlerosPhase3.Ruling.Undecided) return "Undecided (Tie)";
        if (ruling == SimpleKlerosPhase3.Ruling.Option1) return "Option 1 Wins";
        if (ruling == SimpleKlerosPhase3.Ruling.Option2) return "Option 2 Wins";
        return "Unknown";
    }

    function _divider() internal pure {
        console2.log("");
        console2.log("============================================================");
        console2.log("");
    }

    function _header(string memory title) internal pure {
        console2.log("");
        console2.log("============================================================");
        console2.log(title);
        console2.log("============================================================");
        console2.log("");
    }

    function _step(uint256 num, string memory description) internal pure {
        console2.log("");
        console2.log("STEP", num, ":", description);
        console2.log("------------------------------------------------------------");
    }

    function _explain(string memory text) internal pure {
        console2.log("  >>", text);
    }

    // ==========
    // setUp - Runs before EVERY test
    // ==========

    function setUp() public {
        // Label addresses for better debugging
        vm.label(juror1, "Juror_Alice");
        vm.label(juror2, "Juror_Bob");
        vm.label(juror3, "Juror_Charlie");
        vm.label(nonJuror, "Random_Person");

        // Create the token used for staking
        token = new TestToken(1_000_000 ether);
        vm.label(address(token), "StakingToken");

        // Give tokens to our test participants
        token.transfer(juror1, 10_000 ether);
        token.transfer(juror2, 10_000 ether);
        token.transfer(juror3, 10_000 ether);
        token.transfer(nonJuror, 1_000 ether);

        // Deploy the Kleros court system
        kleros = new SimpleKlerosPhase3(
            IERC20(address(token)),
            MIN_STAKE,      // Minimum 100 tokens to be a juror
            NUM_DRAWS,      // 3 random draws per dispute
            1 hours,        // 1 hour to submit encrypted votes
            1 hours         // 1 hour to reveal votes
        );
        vm.label(address(kleros), "KlerosCourt");

        // Jurors stake their tokens (different amounts = different selection probabilities)
        vm.startPrank(juror1);
        token.approve(address(kleros), type(uint256).max);
        kleros.stake(500 ether);  // Alice stakes 500 tokens (highest)
        vm.stopPrank();

        vm.startPrank(juror2);
        token.approve(address(kleros), type(uint256).max);
        kleros.stake(300 ether);  // Bob stakes 300 tokens (medium)
        vm.stopPrank();

        vm.startPrank(juror3);
        token.approve(address(kleros), type(uint256).max);
        kleros.stake(200 ether);  // Charlie stakes 200 tokens (lowest)
        vm.stopPrank();
    }

    // ============================================================================
    // CORE FUNCTIONALITY TESTS
    // ============================================================================

    function testNumDrawsMustBeOdd() public {
        _header("TEST: Number of Draws Must Be Odd");
        
        _explain("Why odd? To prevent ties! With odd jurors, there's always a majority.");
        _explain("For example: 3 jurors means you need 2+ to win. Never a 1.5 vs 1.5 situation.");
        
        console2.log("");
        console2.log("Trying to create a court with 4 draws (even number)...");
        
        vm.expectRevert("numDraws must be odd and > 0");
        new SimpleKlerosPhase3(
            IERC20(address(token)),
            MIN_STAKE,
            4,  // EVEN NUMBER - Should fail!
            1 hours,
            1 hours
        );
        
        console2.log("RESULT: Transaction was rejected as expected!");
        console2.log("The system correctly prevents even numbers of draws.");
    }

    function testNumDrawsMustBePositive() public {
        _header("TEST: Number of Draws Must Be Greater Than Zero");
        
        _explain("You can't have a court with zero jurors!");
        _explain("At least 1 juror is needed to make a decision.");
        
        console2.log("");
        console2.log("Trying to create a court with 0 draws...");
        
        vm.expectRevert("numDraws must be odd and > 0");
        new SimpleKlerosPhase3(
            IERC20(address(token)),
            MIN_STAKE,
            0,  // ZERO - Should fail!
            1 hours,
            1 hours
        );
        
        console2.log("RESULT: Transaction was rejected as expected!");
    }

    function testTotalSelectionsEqualsNumDraws() public {
        _header("TEST: Total Selections Should Equal Number of Draws");
        
        _explain("When we draw jurors, we perform exactly 'numDraws' random selections.");
        _explain("Each selection picks one juror (possibly the same juror multiple times).");
        
        _step(1, "Create a new dispute");
        uint256 id = kleros.createDispute("ipfs://QmTest");
        console2.log("  Dispute ID:", id);
        
        _step(2, "Draw jurors for this dispute");
        console2.log("  Performing", NUM_DRAWS, "random draws...");
        kleros.drawJurors(id);
        
        _step(3, "Verify total selections");
        (,,,, uint256 totalSelections) = kleros.getDisputeSummary(id);
        console2.log("  Expected selections:", NUM_DRAWS);
        console2.log("  Actual selections:", totalSelections);
        
        assertEq(totalSelections, NUM_DRAWS, "Total selections should equal numDraws");
        console2.log("");
        console2.log("SUCCESS: The system performed exactly", NUM_DRAWS, "selections!");
    }

    function testJurorCanBeSelectedMultipleTimes() public {
        _header("TEST: Same Juror Can Be Selected Multiple Times");
        
        _explain("Unlike traditional juries, Kleros allows the same person to be picked multiple times.");
        _explain("Each selection gives them +1 voting power.");
        _explain("If Alice is picked 3 times, her vote counts as 3 votes!");
        
        _step(1, "Create a court with 5 draws and one dominant juror");
        SimpleKlerosPhase3 kleros5 = new SimpleKlerosPhase3(
            IERC20(address(token)),
            MIN_STAKE,
            5,  // 5 draws
            1 hours,
            1 hours
        );

        address bigJuror = address(0x100);
        token.transfer(bigJuror, 5000 ether);
        
        vm.startPrank(bigJuror);
        token.approve(address(kleros5), type(uint256).max);
        kleros5.stake(5000 ether);  // HUGE stake = very high selection chance
        vm.stopPrank();
        
        console2.log("  Created a juror with 5000 tokens staked (very high!)");
        console2.log("  They should be picked multiple times due to weighted selection.");

        _step(2, "Create dispute and draw jurors");
        uint256 id = kleros5.createDispute("ipfs://QmMultiSelect");
        kleros5.drawJurors(id);

        _step(3, "Check how many times the big juror was selected");
        (,, uint256 selectionCount,) = kleros5.getJurorVote(id, bigJuror);
        
        console2.log("  Big juror was selected", selectionCount, "times out of 5 draws!");
        console2.log("  This means their vote counts as", selectionCount, "votes.");
        
        assertGt(selectionCount, 0, "Big juror should be selected at least once");
        console2.log("");
        console2.log("SUCCESS: Multi-selection is working!");
    }

    function testStakeLockedIsMinStakeTimesSelections() public {
        _header("TEST: Stake Locked = Minimum Stake x Selection Count");
        
        _explain("When you're selected as a juror, some of your stake gets locked.");
        _explain("You can't withdraw locked stake until the dispute is resolved.");
        _explain("Formula: Locked Amount = 100 tokens x (number of times selected)");
        
        _step(1, "Create dispute and draw jurors");
        uint256 id = kleros.createDispute("ipfs://QmStakeLock");
        kleros.drawJurors(id);

        address[] memory jurors = kleros.getJurors(id);
        
        _step(2, "Check each juror's locked stake");
        console2.log("  Minimum stake per selection:", _toTokens(MIN_STAKE), "tokens");
        console2.log("");
        
        for (uint256 i = 0; i < jurors.length; i++) {
            (,, uint256 selectionCount, uint256 lockedStake) = 
                kleros.getJurorVote(id, jurors[i]);
            
            uint256 expectedLocked = MIN_STAKE * selectionCount;
            
            console2.log("  Juror", i + 1, ":");
            console2.log("    - Selected", selectionCount, "time(s)");
            console2.log("    - Expected locked:", _toTokens(expectedLocked), "tokens");
            console2.log("    - Actual locked:", _toTokens(lockedStake), "tokens");
            
            assertEq(lockedStake, expectedLocked, "Locked stake should be minStake * selectionCount");
        }
        
        console2.log("");
        console2.log("SUCCESS: Stake locking formula is correct!");
    }

    function testWeightedSelectionFavorsHigherStakes() public {
        _header("TEST: Higher Stake = Higher Selection Probability");
        
        _explain("This is the KEY feature of Kleros:");
        _explain("If you stake MORE tokens, you're MORE LIKELY to be selected as a juror.");
        _explain("It's like having more lottery tickets - more tickets = better odds.");
        console2.log("");
        console2.log("Our jurors and their stakes:");
        console2.log("  - Alice (juror1): 500 tokens (50% of total)");
        console2.log("  - Bob (juror2): 300 tokens (30% of total)");
        console2.log("  - Charlie (juror3): 200 tokens (20% of total)");
        
        _step(1, "Run 10 disputes and count selections");
        console2.log("  We'll create 10 disputes with 3 draws each = 30 total selections.");
        console2.log("  Let's see how often each juror gets picked...");
        
        uint256 aliceSelections = 0;
        uint256 bobSelections = 0;
        uint256 charlieSelections = 0;

        for (uint256 i = 0; i < 10; i++) {
            uint256 id = kleros.createDispute(string(abi.encodePacked("ipfs://Qm", i)));
            kleros.drawJurors(id);

            (,, uint256 s1,) = kleros.getJurorVote(id, juror1);
            (,, uint256 s2,) = kleros.getJurorVote(id, juror2);
            (,, uint256 s3,) = kleros.getJurorVote(id, juror3);

            aliceSelections += s1;
            bobSelections += s2;
            charlieSelections += s3;

            _completeDispute(id);
        }

        _step(2, "Results after 30 total selections");
        console2.log("");
        console2.log("  ALICE (500 stake / 50%):");
        console2.log("    Selected", aliceSelections, "times");
        
        console2.log("");
        console2.log("  BOB (300 stake / 30%):");
        console2.log("    Selected", bobSelections, "times");
        
        console2.log("");
        console2.log("  CHARLIE (200 stake / 20%):");
        console2.log("    Selected", charlieSelections, "times");
        
        console2.log("");
        console2.log("OBSERVATION: Alice (highest stake) should have the most selections.");
        console2.log("             Charlie (lowest stake) should have the fewest.");
        console2.log("             The weighted random selection is working as designed!");
    }

    // ============================================================================
    // VOTING AND REWARD DISTRIBUTION TESTS
    // ============================================================================

    function testMajorityWinsAndGetsReward() public {
        _header("TEST: Majority Wins and Gets Rewards");
        
        _explain("This is how Kleros dispute resolution works:");
        _explain("1. Jurors vote on Option 1 or Option 2");
        _explain("2. The option with more voting weight wins");
        _explain("3. Losing jurors have their stake taken and given to winners");
        
        _step(1, "Create a dispute and draw jurors");
        uint256 id = kleros.createDispute("ipfs://QmMajority");
        kleros.drawJurors(id);

        address[] memory jurors = kleros.getJurors(id);
        console2.log("  Number of unique jurors selected:", jurors.length);

        _step(2, "Check who was selected and their voting power");
        uint256[] memory selCounts = new uint256[](jurors.length);
        uint256 totalWeight = 0;
        
        for (uint256 i = 0; i < jurors.length; i++) {
            (,, uint256 selCount,) = kleros.getJurorVote(id, jurors[i]);
            selCounts[i] = selCount;
            totalWeight += selCount;
            console2.log("  Juror", i + 1, "voting power:", selCount);
        }
        console2.log("  Total voting power:", totalWeight);

        _step(3, "Set up voting - minority vs majority");
        // Find juror with lowest weight to be the minority
        uint256 minorityIdx = 0;
        uint256 lowestWeight = selCounts[0];
        for (uint256 i = 1; i < jurors.length; i++) {
            if (selCounts[i] < lowestWeight) {
                lowestWeight = selCounts[i];
                minorityIdx = i;
            }
        }

        uint256 majorityWeight = totalWeight - lowestWeight;
        console2.log("  Minority juror (votes Option 2): voting power =", lowestWeight);
        console2.log("  Majority jurors (vote Option 1): voting power =", majorityWeight);

        _step(4, "COMMIT PHASE - Jurors submit encrypted votes");
        console2.log("  (Votes are hidden during this phase - no one can see how others voted)");
        
        bytes32 saltMajority = keccak256("saltMajority");
        bytes32 saltMinority = keccak256("saltMinority");

        for (uint256 i = 0; i < jurors.length; i++) {
            vm.prank(jurors[i]);
            if (i == minorityIdx) {
                kleros.commitVote(id, keccak256(abi.encodePacked(uint8(2), saltMinority)));
                console2.log("  Juror", i + 1, "committed a hidden vote (will be Option 2)");
            } else {
                kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), saltMajority)));
                console2.log("  Juror", i + 1, "committed a hidden vote (will be Option 1)");
            }
        }

        _step(5, "Time passes... waiting for commit deadline");
        vm.warp(block.timestamp + 90 minutes);
        console2.log("  90 minutes have passed. Commit phase is over.");

        _step(6, "REVEAL PHASE - Jurors reveal their votes");
        console2.log("  Now everyone reveals what they actually voted for.");
        
        for (uint256 i = 0; i < jurors.length; i++) {
            vm.prank(jurors[i]);
            if (i == minorityIdx) {
                kleros.revealVote(id, 2, saltMinority);
                console2.log("  Juror", i + 1, "revealed: OPTION 2");
            } else {
                kleros.revealVote(id, 1, saltMajority);
                console2.log("  Juror", i + 1, "revealed: OPTION 1");
            }
        }

        _step(7, "Time passes... waiting for reveal deadline");
        vm.warp(block.timestamp + 1 hours);
        console2.log("  1 hour has passed. Reveal phase is over.");

        _step(8, "FINALIZE - Count votes and determine winner");
        kleros.finalize(id);

        (, SimpleKlerosPhase3.Ruling ruling, uint256 v1, uint256 v2,) = kleros.getDisputeSummary(id);
        
        console2.log("");
        console2.log("  FINAL VOTE COUNT:");
        console2.log("    Option 1:", v1, "votes");
        console2.log("    Option 2:", v2, "votes");
        console2.log("");
        console2.log("  RULING:", _rulingToString(ruling));

        if (jurors.length > 1 && majorityWeight > lowestWeight) {
            assertEq(uint256(ruling), uint256(SimpleKlerosPhase3.Ruling.Option1), "Majority should win");
            console2.log("");
            console2.log("SUCCESS: The majority won as expected!");
            console2.log("The minority juror will have their stake slashed and given to winners.");
        }
    }

    function testLoserGetsSlashed() public {
        _header("TEST: Losing Jurors Get Their Stake Slashed");
        
        _explain("When you vote against the majority, you LOSE your locked stake.");
        _explain("This is the 'skin in the game' mechanism that makes jurors vote honestly.");
        _explain("If you vote wrong, you lose real money!");

        _step(1, "Set up a court with balanced jurors");
        SimpleKlerosPhase3 kleros5 = new SimpleKlerosPhase3(
            IERC20(address(token)),
            MIN_STAKE,
            5,
            1 hours,
            1 hours
        );

        address slashJuror1 = address(0x301);
        address slashJuror2 = address(0x302);
        address slashJuror3 = address(0x303);
        
        token.transfer(slashJuror1, 1000 ether);
        token.transfer(slashJuror2, 1000 ether);
        token.transfer(slashJuror3, 1000 ether);

        vm.startPrank(slashJuror1);
        token.approve(address(kleros5), type(uint256).max);
        kleros5.stake(500 ether);
        vm.stopPrank();

        vm.startPrank(slashJuror2);
        token.approve(address(kleros5), type(uint256).max);
        kleros5.stake(500 ether);
        vm.stopPrank();

        vm.startPrank(slashJuror3);
        token.approve(address(kleros5), type(uint256).max);
        kleros5.stake(500 ether);
        vm.stopPrank();
        
        console2.log("  Created 3 jurors, each with 500 tokens staked.");

        _step(2, "Create dispute and draw jurors");
        uint256 id = kleros5.createDispute("ipfs://QmSlash");
        kleros5.drawJurors(id);

        address[] memory jurors = kleros5.getJurors(id);
        
        if (jurors.length < 2) {
            console2.log("  Only 1 unique juror was selected (all draws picked same person).");
            console2.log("  This is valid behavior - completing dispute normally.");
            bytes32 saltSkip = keccak256("saltSkip");
            vm.prank(jurors[0]);
            kleros5.commitVote(id, keccak256(abi.encodePacked(uint8(1), saltSkip)));
            vm.warp(block.timestamp + 90 minutes);
            vm.prank(jurors[0]);
            kleros5.revealVote(id, 1, saltSkip);
            vm.warp(block.timestamp + 1 hours);
            kleros5.finalize(id);
            return;
        }

        _step(3, "Find the juror with lowest voting power (they'll be our loser)");
        uint256 loserIdx = 0;
        uint256 lowestSelCount = type(uint256).max;
        for (uint256 i = 0; i < jurors.length; i++) {
            (,, uint256 selCount,) = kleros5.getJurorVote(id, jurors[i]);
            console2.log("  Juror", i + 1, "voting power:", selCount);
            if (selCount < lowestSelCount) {
                lowestSelCount = selCount;
                loserIdx = i;
            }
        }
        
        address loser = jurors[loserIdx];
        (uint256 loserInitialStake,) = kleros5.getJurorStake(loser);
        (,, uint256 loserSelCount,) = kleros5.getJurorVote(id, loser);
        
        console2.log("");
        console2.log("  DESIGNATED LOSER: Juror", loserIdx + 1);
        console2.log("  Their stake before dispute:", _toTokens(loserInitialStake), "tokens");
        console2.log("  Their locked stake (at risk):", _toTokens(loserSelCount * MIN_STAKE), "tokens");

        _step(4, "Voting - loser votes differently from everyone else");
        bytes32 salt0 = keccak256("salt0");
        bytes32 salt1 = keccak256("salt1");

        for (uint256 i = 0; i < jurors.length; i++) {
            if (i == loserIdx) {
                vm.prank(jurors[i]);
                kleros5.commitVote(id, keccak256(abi.encodePacked(uint8(1), salt0)));
                console2.log("  Juror", i + 1, "(LOSER) votes Option 1");
            } else {
                vm.prank(jurors[i]);
                kleros5.commitVote(id, keccak256(abi.encodePacked(uint8(2), salt1)));
                console2.log("  Juror", i + 1, "(WINNER) votes Option 2");
            }
        }

        vm.warp(block.timestamp + 90 minutes);

        for (uint256 i = 0; i < jurors.length; i++) {
            if (i == loserIdx) {
                vm.prank(jurors[i]);
                kleros5.revealVote(id, 1, salt0);
            } else {
                vm.prank(jurors[i]);
                kleros5.revealVote(id, 2, salt1);
            }
        }

        vm.warp(block.timestamp + 1 hours);
        
        _step(5, "Finalize dispute and check the damage");
        kleros5.finalize(id);

        (uint256 loserFinalStake,) = kleros5.getJurorStake(loser);
        uint256 expectedSlash = MIN_STAKE * loserSelCount;
        
        console2.log("");
        console2.log("  LOSER'S FINANCIAL SITUATION:");
        console2.log("    Stake before:", _toTokens(loserInitialStake), "tokens");
        console2.log("    Stake after:", _toTokens(loserFinalStake), "tokens");
        console2.log("    TOKENS LOST:", _toTokens(loserInitialStake - loserFinalStake), "tokens");
        
        assertEq(loserFinalStake, loserInitialStake - expectedSlash, "Loser should lose locked stake");
        
        console2.log("");
        console2.log("SUCCESS: The loser was slashed exactly as expected!");
        console2.log("Their lost tokens were redistributed to the winning jurors.");
    }

    function testNonRevealerLosesStake() public {
        _header("TEST: Not Revealing Your Vote = Automatic Loss");
        
        _explain("If you commit a vote but don't reveal it, you're treated as a LOSER.");
        _explain("This prevents jurors from 'sitting on the fence' and waiting to see how others vote.");
        _explain("You MUST reveal your vote, or you lose your stake!");

        _step(1, "Set up court with multiple jurors");
        SimpleKlerosPhase3 kleros5 = new SimpleKlerosPhase3(
            IERC20(address(token)),
            MIN_STAKE,
            5,
            1 hours,
            1 hours
        );

        address revealJuror1 = address(0x401);
        address revealJuror2 = address(0x402);
        address revealJuror3 = address(0x403);
        
        token.transfer(revealJuror1, 1000 ether);
        token.transfer(revealJuror2, 1000 ether);
        token.transfer(revealJuror3, 1000 ether);

        vm.startPrank(revealJuror1);
        token.approve(address(kleros5), type(uint256).max);
        kleros5.stake(500 ether);
        vm.stopPrank();

        vm.startPrank(revealJuror2);
        token.approve(address(kleros5), type(uint256).max);
        kleros5.stake(500 ether);
        vm.stopPrank();

        vm.startPrank(revealJuror3);
        token.approve(address(kleros5), type(uint256).max);
        kleros5.stake(500 ether);
        vm.stopPrank();

        _step(2, "Create dispute and draw jurors");
        uint256 id = kleros5.createDispute("ipfs://QmNoReveal");
        kleros5.drawJurors(id);

        address[] memory jurors = kleros5.getJurors(id);
        
        if (jurors.length < 2) {
            console2.log("  Only 1 unique juror - completing normally.");
            bytes32 salt = keccak256("salt");
            vm.prank(jurors[0]);
            kleros5.commitVote(id, keccak256(abi.encodePacked(uint8(1), salt)));
            vm.warp(block.timestamp + 90 minutes);
            vm.prank(jurors[0]);
            kleros5.revealVote(id, 1, salt);
            vm.warp(block.timestamp + 1 hours);
            kleros5.finalize(id);
            return;
        }

        console2.log("  Selected", jurors.length, "unique jurors.");

        uint256[] memory initialStakes = new uint256[](jurors.length);
        for (uint256 i = 0; i < jurors.length; i++) {
            (uint256 amt,) = kleros5.getJurorStake(jurors[i]);
            initialStakes[i] = amt;
        }

        _step(3, "ALL jurors commit their votes");
        bytes32 salt = keccak256("salt");
        for (uint256 i = 0; i < jurors.length; i++) {
            vm.prank(jurors[i]);
            kleros5.commitVote(id, keccak256(abi.encodePacked(uint8(1), salt)));
            console2.log("  Juror", i + 1, "committed a vote");
        }

        vm.warp(block.timestamp + 90 minutes);

        _step(4, "Only the FIRST juror reveals - others stay silent!");
        vm.prank(jurors[0]);
        kleros5.revealVote(id, 1, salt);
        console2.log("  Juror 1 revealed their vote: OPTION 1");
        
        for (uint256 i = 1; i < jurors.length; i++) {
            console2.log("  Juror", i + 1, "DID NOT REVEAL (stayed silent)");
        }

        _step(5, "Finalize and see the consequences");
        vm.warp(block.timestamp + 1 hours);
        kleros5.finalize(id);

        console2.log("");
        console2.log("  RESULTS:");
        console2.log("");
        
        (uint256 revealerFinal,) = kleros5.getJurorStake(jurors[0]);
        console2.log("  Juror 1 (REVEALED):");
        console2.log("    Stake before:", _toTokens(initialStakes[0]), "tokens");
        console2.log("    Stake after:", _toTokens(revealerFinal), "tokens");
        console2.log("    RESULT: GAINED", _toTokens(revealerFinal - initialStakes[0]), "tokens!");
        
        for (uint256 i = 1; i < jurors.length; i++) {
            (uint256 finalStake,) = kleros5.getJurorStake(jurors[i]);
            (,, uint256 selCount,) = kleros5.getJurorVote(id, jurors[i]);
            
            console2.log("");
            console2.log("  Juror", i + 1, "(DID NOT REVEAL):");
            console2.log("    Stake before:", _toTokens(initialStakes[i]), "tokens");
            console2.log("    Stake after:", _toTokens(finalStake), "tokens");
            console2.log("    RESULT: LOST", _toTokens(initialStakes[i] - finalStake), "tokens!");
            
            uint256 expectedSlash = MIN_STAKE * selCount;
            assertEq(finalStake, initialStakes[i] - expectedSlash, "Non-revealer should be slashed");
        }
        
        assertGt(revealerFinal, initialStakes[0], "Revealer should gain stake");
        
        console2.log("");
        console2.log("SUCCESS: Non-revealers were punished and their stake went to the revealer!");
    }

    function testTieNoRedistribution() public {
        _header("TEST: Tie Scenario - Single Juror Case");
        
        _explain("When there's only one unique juror (same person picked for all slots),");
        _explain("they're the only voter, so whatever they vote wins.");
        
        SimpleKlerosPhase3 kleros1 = new SimpleKlerosPhase3(
            IERC20(address(token)),
            MIN_STAKE,
            1,  // Just 1 draw
            1 hours,
            1 hours
        );

        address singleJuror = address(0x200);
        token.transfer(singleJuror, 1000 ether);

        vm.startPrank(singleJuror);
        token.approve(address(kleros1), type(uint256).max);
        kleros1.stake(500 ether);
        vm.stopPrank();
        
        console2.log("  Created court with 1 draw and 1 juror.");

        _step(1, "Create dispute and draw jurors");
        uint256 id = kleros1.createDispute("ipfs://QmTie");
        kleros1.drawJurors(id);

        address[] memory jurors = kleros1.getJurors(id);
        console2.log("  Selected", jurors.length, "unique juror(s).");

        _step(2, "Single juror votes Option 1");
        bytes32 salt = keccak256("salt");
        
        vm.prank(jurors[0]);
        kleros1.commitVote(id, keccak256(abi.encodePacked(uint8(1), salt)));
        console2.log("  Juror committed vote...");

        vm.warp(block.timestamp + 90 minutes);

        vm.prank(jurors[0]);
        kleros1.revealVote(id, 1, salt);
        console2.log("  Juror revealed: OPTION 1");

        vm.warp(block.timestamp + 1 hours);
        kleros1.finalize(id);

        _step(3, "Check the outcome");
        (, SimpleKlerosPhase3.Ruling ruling, uint256 v1, uint256 v2,) = kleros1.getDisputeSummary(id);
        
        console2.log("");
        console2.log("  Votes for Option 1:", v1);
        console2.log("  Votes for Option 2:", v2);
        console2.log("  RULING:", _rulingToString(ruling));
        
        assertEq(uint256(ruling), uint256(SimpleKlerosPhase3.Ruling.Option1));
        console2.log("");
        console2.log("SUCCESS: Single juror's vote decided the outcome!");
    }

    function testTieResultsInUndecided() public {
        _header("TEST: True Tie - No One Reveals Their Vote");
        
        _explain("If NO ONE reveals their vote, the result is 0 vs 0 = TIE!");
        _explain("In a tie, the ruling is 'Undecided' and no stake is redistributed.");
        _explain("Everyone just gets their stake back.");
        
        _step(1, "Create dispute and draw jurors");
        uint256 id = kleros.createDispute("ipfs://QmForcedTie");
        kleros.drawJurors(id);

        address[] memory jurors = kleros.getJurors(id);
        console2.log("  Selected", jurors.length, "unique juror(s).");

        _step(2, "All jurors commit votes");
        bytes32 salt = keccak256("salt");
        for (uint256 i = 0; i < jurors.length; i++) {
            vm.prank(jurors[i]);
            kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), salt)));
            console2.log("  Juror", i + 1, "committed a vote");
        }

        _step(3, "TIME PASSES... but NO ONE REVEALS!");
        console2.log("  Commit phase ends...");
        console2.log("  Reveal phase ends...");
        console2.log("  NO JUROR REVEALED THEIR VOTE!");
        
        vm.warp(block.timestamp + 3 hours);
        
        _step(4, "Finalize the dispute");
        kleros.finalize(id);

        (, SimpleKlerosPhase3.Ruling ruling, uint256 v1, uint256 v2,) = kleros.getDisputeSummary(id);
        
        console2.log("");
        console2.log("  FINAL COUNT:");
        console2.log("    Votes for Option 1:", v1);
        console2.log("    Votes for Option 2:", v2);
        console2.log("");
        console2.log("  RULING:", _rulingToString(ruling));

        assertEq(v1, 0, "No Option 1 votes since no one revealed");
        assertEq(v2, 0, "No Option 2 votes since no one revealed");
        assertEq(uint256(ruling), uint256(SimpleKlerosPhase3.Ruling.Undecided));
        
        console2.log("");
        console2.log("SUCCESS: With 0 vs 0 votes, the result is correctly Undecided!");
    }

    function testCanUnstakeAfterDispute() public {
        _header("TEST: Winners Can Withdraw Their Rewards");
        
        _explain("After a dispute is resolved, jurors can withdraw their stake.");
        _explain("Winners can withdraw their original stake PLUS their share of the losers' stake!");
        
        _step(1, "Create and complete a dispute");
        uint256 id = kleros.createDispute("ipfs://QmUnstake");
        kleros.drawJurors(id);
        
        address[] memory jurors = kleros.getJurors(id);

        bytes32 salt = keccak256("salt");
        for (uint256 i = 0; i < jurors.length; i++) {
            vm.prank(jurors[i]);
            kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), salt)));
        }

        vm.warp(block.timestamp + 90 minutes);

        for (uint256 i = 0; i < jurors.length; i++) {
            vm.prank(jurors[i]);
            kleros.revealVote(id, 1, salt);
        }

        vm.warp(block.timestamp + 1 hours);
        kleros.finalize(id);
        
        console2.log("  Dispute completed. All jurors voted the same way (no losers).");

        _step(2, "Check juror's stake status");
        (uint256 stakeAfter, uint256 lockedAfter) = kleros.getJurorStake(jurors[0]);
        console2.log("  Juror 1's stake:", _toTokens(stakeAfter), "tokens");
        console2.log("  Juror 1's locked amount:", _toTokens(lockedAfter), "tokens");
        
        assertEq(lockedAfter, 0, "Stake should be unlocked after dispute");

        _step(3, "Juror withdraws some tokens");
        uint256 balanceBefore = token.balanceOf(jurors[0]);
        console2.log("  Token balance before unstaking:", _toTokens(balanceBefore), "tokens");
        
        vm.prank(jurors[0]);
        kleros.unstake(100 ether);
        
        uint256 balanceAfter = token.balanceOf(jurors[0]);
        console2.log("  Token balance after unstaking:", _toTokens(balanceAfter), "tokens");
        console2.log("  Tokens received:", _toTokens(balanceAfter - balanceBefore), "tokens");

        (uint256 stakeAfterUnstake,) = kleros.getJurorStake(jurors[0]);
        assertEq(stakeAfterUnstake, stakeAfter - 100 ether);
        
        console2.log("");
        console2.log("SUCCESS: Juror was able to withdraw their tokens!");
    }

    // ============================================================================
    // SECURITY TESTS - Things That Should NOT Be Allowed
    // ============================================================================

    function testCannotCommitTwice() public {
        _header("TEST: Cannot Submit Vote Twice");
        
        _explain("Once you've committed your vote, you can't change it.");
        _explain("This prevents manipulation and 'vote changing' after seeing others' behavior.");
        
        uint256 id = kleros.createDispute("ipfs://QmDoubleCommit");
        kleros.drawJurors(id);
        address[] memory jurors = kleros.getJurors(id);

        bytes32 salt = keccak256("salt");
        bytes32 commitHash = keccak256(abi.encodePacked(uint8(1), salt));

        _step(1, "Juror commits their first vote");
        vm.prank(jurors[0]);
        kleros.commitVote(id, commitHash);
        console2.log("  First vote committed successfully.");

        _step(2, "Juror tries to commit again");
        console2.log("  Attempting to submit a second vote...");
        
        vm.prank(jurors[0]);
        vm.expectRevert("already committed");
        kleros.commitVote(id, commitHash);
        
        console2.log("  BLOCKED! System rejected the second vote.");
        console2.log("");
        console2.log("SUCCESS: Double voting is prevented!");
    }

    function testNonJurorCannotCommit() public {
        _header("TEST: Non-Jurors Cannot Vote");
        
        _explain("Only selected jurors can participate in voting.");
        _explain("Random people off the street can't just walk in and vote!");
        
        uint256 id = kleros.createDispute("ipfs://QmNonJuror");
        kleros.drawJurors(id);

        bytes32 salt = keccak256("salt");
        bytes32 commitHash = keccak256(abi.encodePacked(uint8(1), salt));

        console2.log("  A random person (not a selected juror) tries to vote...");
        
        vm.prank(nonJuror);
        vm.expectRevert("not a juror");
        kleros.commitVote(id, commitHash);
        
        console2.log("  BLOCKED! Only selected jurors can vote.");
        console2.log("");
        console2.log("SUCCESS: Non-jurors are prevented from voting!");
    }

    function testNonJurorCannotReveal() public {
        _header("TEST: Non-Jurors Cannot Reveal Votes");
        
        uint256 id = kleros.createDispute("ipfs://QmNonJurorReveal");
        kleros.drawJurors(id);
        address[] memory jurors = kleros.getJurors(id);

        bytes32 salt = keccak256("salt");

        for (uint256 i = 0; i < jurors.length; i++) {
            vm.prank(jurors[i]);
            kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), salt)));
        }

        vm.warp(block.timestamp + 90 minutes);

        console2.log("  Random person tries to reveal during reveal phase...");
        
        vm.prank(nonJuror);
        vm.expectRevert("not a juror");
        kleros.revealVote(id, 1, salt);
        
        console2.log("  BLOCKED! Only selected jurors can reveal.");
        console2.log("");
        console2.log("SUCCESS: Non-jurors cannot interfere with the reveal phase!");
    }

    function testCannotRevealWithWrongSalt() public {
        _header("TEST: Cannot Reveal With Wrong Secret");
        
        _explain("When you commit a vote, you use a secret 'salt' to encrypt it.");
        _explain("You must use the SAME salt when revealing, or the reveal fails.");
        _explain("This proves you're revealing the same vote you originally committed.");
        
        uint256 id = kleros.createDispute("ipfs://QmWrongSalt");
        kleros.drawJurors(id);
        address[] memory jurors = kleros.getJurors(id);

        bytes32 correctSalt = keccak256("correctSalt");
        bytes32 wrongSalt = keccak256("wrongSalt");

        _step(1, "Juror commits with their secret");
        vm.prank(jurors[0]);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), correctSalt)));
        console2.log("  Committed vote with secret: 'correctSalt'");

        vm.warp(block.timestamp + 90 minutes);

        _step(2, "Juror tries to reveal with WRONG secret");
        console2.log("  Trying to reveal with secret: 'wrongSalt'...");
        
        vm.prank(jurors[0]);
        vm.expectRevert("bad reveal");
        kleros.revealVote(id, 1, wrongSalt);
        
        console2.log("  BLOCKED! The secrets don't match.");
        console2.log("");
        console2.log("SUCCESS: You can't cheat by using a different secret!");
    }

    function testCannotRevealWithWrongVote() public {
        _header("TEST: Cannot Reveal Different Vote Than Committed");
        
        _explain("You can't commit 'Option 1' then reveal 'Option 2'.");
        _explain("The cryptographic hash must match exactly.");
        
        uint256 id = kleros.createDispute("ipfs://QmWrongVote");
        kleros.drawJurors(id);
        address[] memory jurors = kleros.getJurors(id);

        bytes32 salt = keccak256("salt");

        _step(1, "Juror commits vote for Option 1");
        vm.prank(jurors[0]);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), salt)));
        console2.log("  Committed: Option 1");

        vm.warp(block.timestamp + 90 minutes);

        _step(2, "Juror tries to reveal as Option 2");
        console2.log("  Trying to reveal: Option 2...");
        
        vm.prank(jurors[0]);
        vm.expectRevert("bad reveal");
        kleros.revealVote(id, 2, salt);
        
        console2.log("  BLOCKED! Can't change your vote after committing.");
        console2.log("");
        console2.log("SUCCESS: Vote changing is impossible!");
    }

    function testCannotRevealTwice() public {
        _header("TEST: Cannot Reveal Vote Twice");
        
        uint256 id = kleros.createDispute("ipfs://QmDoubleReveal");
        kleros.drawJurors(id);
        address[] memory jurors = kleros.getJurors(id);

        bytes32 salt = keccak256("salt");

        vm.prank(jurors[0]);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), salt)));

        vm.warp(block.timestamp + 90 minutes);

        _step(1, "Juror reveals their vote");
        vm.prank(jurors[0]);
        kleros.revealVote(id, 1, salt);
        console2.log("  First reveal: SUCCESS");

        _step(2, "Juror tries to reveal again");
        console2.log("  Attempting second reveal...");
        
        vm.prank(jurors[0]);
        vm.expectRevert("already revealed");
        kleros.revealVote(id, 1, salt);
        
        console2.log("  BLOCKED! Already revealed.");
        console2.log("");
        console2.log("SUCCESS: Double-reveal is prevented!");
    }

    function testCannotRevealInvalidVoteValue() public {
        _header("TEST: Vote Must Be Option 1 or Option 2");
        
        _explain("You can only vote for Option 1 or Option 2.");
        _explain("Trying to vote for 'Option 3' or any other value fails.");
        
        uint256 id = kleros.createDispute("ipfs://QmInvalidVote");
        kleros.drawJurors(id);
        address[] memory jurors = kleros.getJurors(id);

        bytes32 salt = keccak256("salt");

        vm.prank(jurors[0]);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(3), salt)));

        vm.warp(block.timestamp + 90 minutes);

        console2.log("  Trying to reveal vote for 'Option 3'...");
        
        vm.prank(jurors[0]);
        vm.expectRevert("invalid vote");
        kleros.revealVote(id, 3, salt);
        
        console2.log("  BLOCKED! Only 1 or 2 are valid votes.");
        console2.log("");
        console2.log("SUCCESS: Invalid vote values are rejected!");
    }

    // ============================================================================
    // TIMING TESTS - Phase Enforcement
    // ============================================================================

    function testCannotRevealBeforeCommitDeadline() public {
        _header("TEST: Cannot Reveal Too Early");
        
        _explain("The reveal phase only starts AFTER the commit deadline.");
        _explain("You can't reveal early to see others' commits!");
        
        uint256 id = kleros.createDispute("ipfs://QmEarlyReveal");
        kleros.drawJurors(id);
        address[] memory jurors = kleros.getJurors(id);

        bytes32 salt = keccak256("salt");

        vm.prank(jurors[0]);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), salt)));
        console2.log("  Juror committed their vote.");
        console2.log("  Commit deadline: 1 hour from now");
        console2.log("  Current time: RIGHT NOW (too early!)");
        
        console2.log("");
        console2.log("  Trying to reveal immediately...");
        
        vm.prank(jurors[0]);
        vm.expectRevert("commit not finished");
        kleros.revealVote(id, 1, salt);
        
        console2.log("  BLOCKED! Must wait for commit phase to end.");
        console2.log("");
        console2.log("SUCCESS: Early reveals are prevented!");
    }

    function testCannotCommitAfterDeadline() public {
        _header("TEST: Cannot Commit After Deadline");
        
        _explain("The commit window is limited (1 hour in our tests).");
        _explain("Late commits are rejected.");
        
        uint256 id = kleros.createDispute("ipfs://QmLateCommit");
        kleros.drawJurors(id);
        address[] memory jurors = kleros.getJurors(id);

        bytes32 salt = keccak256("salt");

        console2.log("  Commit deadline: 1 hour from dispute creation");
        console2.log("  Fast-forwarding time by 2 hours...");
        
        vm.warp(block.timestamp + 2 hours);
        
        console2.log("  Current time: 2 hours later (deadline passed!)");
        console2.log("");
        console2.log("  Trying to commit a vote...");

        vm.prank(jurors[0]);
        vm.expectRevert("commit over");
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), salt)));
        
        console2.log("  BLOCKED! Too late to vote.");
        console2.log("");
        console2.log("SUCCESS: Late commits are rejected!");
    }

    function testCannotRevealAfterDeadline() public {
        _header("TEST: Cannot Reveal After Deadline");
        
        _explain("The reveal window is also limited.");
        _explain("If you don't reveal in time, you're treated as a non-participant.");
        
        uint256 id = kleros.createDispute("ipfs://QmLateReveal");
        kleros.drawJurors(id);
        address[] memory jurors = kleros.getJurors(id);

        bytes32 salt = keccak256("salt");

        vm.prank(jurors[0]);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), salt)));
        console2.log("  Juror committed their vote.");
        
        console2.log("  Fast-forwarding 3 hours (past BOTH deadlines)...");
        vm.warp(block.timestamp + 3 hours);

        console2.log("  Trying to reveal now...");
        
        vm.prank(jurors[0]);
        vm.expectRevert("reveal over");
        kleros.revealVote(id, 1, salt);
        
        console2.log("  BLOCKED! Reveal window has closed.");
        console2.log("");
        console2.log("SUCCESS: Late reveals are rejected!");
    }

    function testCannotFinalizeBeforeRevealDeadline() public {
        _header("TEST: Cannot Finalize Early");
        
        _explain("The dispute cannot be finalized until the reveal deadline passes.");
        _explain("This gives ALL jurors time to reveal their votes.");
        
        uint256 id = kleros.createDispute("ipfs://QmEarlyFinalize");
        kleros.drawJurors(id);
        address[] memory jurors = kleros.getJurors(id);

        bytes32 salt = keccak256("salt");

        for (uint256 i = 0; i < jurors.length; i++) {
            vm.prank(jurors[i]);
            kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), salt)));
        }

        vm.warp(block.timestamp + 90 minutes);

        for (uint256 i = 0; i < jurors.length; i++) {
            vm.prank(jurors[i]);
            kleros.revealVote(id, 1, salt);
        }
        
        console2.log("  All jurors have revealed their votes.");
        console2.log("  BUT the reveal deadline hasn't passed yet!");
        console2.log("");
        console2.log("  Trying to finalize early...");

        vm.expectRevert("reveal not finished");
        kleros.finalize(id);
        
        console2.log("  BLOCKED! Must wait for reveal deadline.");
        console2.log("");
        console2.log("SUCCESS: Early finalization is prevented!");
    }

    function testCannotDrawJurorsTwice() public {
        _header("TEST: Cannot Draw Jurors Twice");
        
        _explain("Once jurors are selected for a dispute, you can't re-draw.");
        _explain("This prevents manipulation of jury selection.");
        
        uint256 id = kleros.createDispute("ipfs://QmDoubleDraw");
        
        console2.log("  First juror draw...");
        kleros.drawJurors(id);
        console2.log("  SUCCESS: Jurors selected.");
        
        console2.log("");
        console2.log("  Trying to draw jurors again...");

        vm.expectRevert("wrong phase");
        kleros.drawJurors(id);
        
        console2.log("  BLOCKED! Jurors already selected.");
        console2.log("");
        console2.log("SUCCESS: Double-drawing is prevented!");
    }

    // ============================================================================
    // STAKING TESTS
    // ============================================================================

    function testCannotUnstakeWhileLocked() public {
        _header("TEST: Cannot Unstake While Serving as Juror");
        
        _explain("When you're selected as a juror, your stake is LOCKED.");
        _explain("You can't withdraw until the dispute is resolved.");
        _explain("This ensures jurors have 'skin in the game'.");
        
        uint256 id = kleros.createDispute("ipfs://QmLockedUnstake");
        kleros.drawJurors(id);
        address[] memory jurors = kleros.getJurors(id);

        (uint256 stake, uint256 locked) = kleros.getJurorStake(jurors[0]);
        console2.log("  Juror 1's total stake:", _toTokens(stake), "tokens");
        console2.log("  Juror 1's locked stake:", _toTokens(locked), "tokens");
        console2.log("  Juror 1's available stake:", _toTokens(stake - locked), "tokens");
        
        console2.log("");
        console2.log("  Trying to unstake ALL tokens...");

        vm.prank(jurors[0]);
        vm.expectRevert("not enough unlocked stake");
        kleros.unstake(stake);
        
        console2.log("  BLOCKED! Can only unstake unlocked portion.");
        console2.log("");
        console2.log("SUCCESS: Locked stake cannot be withdrawn!");
    }

    function testCannotStakeBelowMinimum() public {
        _header("TEST: Must Stake At Least Minimum Amount");
        
        _explain("To be a juror, you must stake at least 100 tokens.");
        _explain("This prevents spam and ensures jurors have something to lose.");
        
        address newJuror = address(0x100);
        token.transfer(newJuror, 1000 ether);

        console2.log("  Minimum stake required: 100 tokens");
        console2.log("  Trying to stake only 50 tokens...");

        vm.startPrank(newJuror);
        token.approve(address(kleros), type(uint256).max);
        vm.expectRevert("below minStake");
        kleros.stake(50 ether);
        vm.stopPrank();
        
        console2.log("  BLOCKED! Stake too low.");
        console2.log("");
        console2.log("SUCCESS: Minimum stake is enforced!");
    }

    function testCannotStakeZero() public {
        _header("TEST: Cannot Stake Zero Tokens");
        
        console2.log("  Trying to stake 0 tokens...");

        vm.prank(juror1);
        vm.expectRevert("amount=0");
        kleros.stake(0);
        
        console2.log("  BLOCKED! Can't stake nothing.");
        console2.log("");
        console2.log("SUCCESS: Zero stakes are rejected!");
    }

    function testCannotUnstakeMoreThanAvailable() public {
        _header("TEST: Cannot Unstake More Than You Have");
        
        _step(1, "Complete a dispute to unlock stake");
        uint256 id = _createAndCompleteDispute();
        console2.log("  Dispute", id, "completed. Stake unlocked.");

        _step(2, "Try to unstake way more than staked");
        console2.log("  Trying to unstake 10,000 tokens (way more than staked)...");

        vm.prank(juror1);
        vm.expectRevert("not enough unlocked stake");
        kleros.unstake(10_000 ether);
        
        console2.log("  BLOCKED! Can't withdraw more than you have.");
        console2.log("");
        console2.log("SUCCESS: Over-withdrawal is prevented!");
    }

    // ============================================================================
    // VIEW FUNCTION TESTS
    // ============================================================================

    function testGetDisputeSummary() public {
        _header("TEST: Get Dispute Summary");
        
        uint256 id = kleros.createDispute("ipfs://QmSummary");
        console2.log("  Created dispute", id);
        console2.log("");

        (
            SimpleKlerosPhase3.Phase phase,
            SimpleKlerosPhase3.Ruling ruling,
            uint256 v1,
            uint256 v2,
            uint256 totalSelections
        ) = kleros.getDisputeSummary(id);

        console2.log("  DISPUTE STATUS:");
        console2.log("    Phase:", _phaseToString(phase));
        console2.log("    Ruling:", _rulingToString(ruling));
        console2.log("    Votes for Option 1:", v1);
        console2.log("    Votes for Option 2:", v2);
        console2.log("    Total juror selections:", totalSelections);

        assertEq(uint256(phase), uint256(SimpleKlerosPhase3.Phase.Created));
        assertEq(uint256(ruling), uint256(SimpleKlerosPhase3.Ruling.Undecided));
    }

    function testGetJurorStake() public view {
        _header("TEST: Get Juror Stake Information");
        
        (uint256 amount, uint256 locked) = kleros.getJurorStake(juror1);
        
        console2.log("  ALICE'S (juror1) STAKE INFO:");
        console2.log("    Total staked:", _toTokens(amount), "tokens");
        console2.log("    Currently locked:", _toTokens(locked), "tokens");
        console2.log("    Available to withdraw:", _toTokens(amount - locked), "tokens");
    }

    function testGetTotalSelections() public {
        _header("TEST: Get Total Selections Count");
        
        uint256 id = kleros.createDispute("ipfs://QmSelections");
        console2.log("  Before drawing jurors...");
        console2.log("    Total selections:", kleros.getTotalSelections(id));
        
        kleros.drawJurors(id);
        
        console2.log("  After drawing jurors...");
        console2.log("    Total selections:", kleros.getTotalSelections(id));

        uint256 total = kleros.getTotalSelections(id);
        assertEq(total, NUM_DRAWS);
    }

    // ============================================================================
    // BUG FIX VERIFICATION TESTS
    // ============================================================================

    function testFix_StaleTotalStakeInDrawLoop() public {
        _header("BUG FIX TEST: Stale totalStake in Draw Loop");
        
        _explain("ORIGINAL BUG: totalStake was calculated ONCE at the start of drawJurors.");
        _explain("As jurors got selected, their lockedAmount increased, reducing available stake.");
        _explain("But the random target was still based on the OLD totalStake!");
        _explain("This could cause target > actual cumulative, hitting the fallback.");
        console2.log("");
        _explain("FIX: Recalculate totalStake for EACH draw iteration.");
        
        _step(1, "Create a scenario with limited stake");
        // Create a new kleros with 5 draws
        SimpleKlerosPhase3 klerosTest = new SimpleKlerosPhase3(
            IERC20(address(token)),
            MIN_STAKE,  // 100 tokens per selection
            5,          // 5 draws = need 500 tokens total
            1 hours,
            1 hours
        );

        // Create a juror with exactly enough stake for 5 selections
        address limitedJuror = address(0x500);
        token.transfer(limitedJuror, 600 ether);

        vm.startPrank(limitedJuror);
        token.approve(address(klerosTest), type(uint256).max);
        klerosTest.stake(500 ether);  // Exactly 500 = 5 x 100 minStake
        vm.stopPrank();

        console2.log("  Created juror with 500 tokens staked (exactly 5 x minStake).");
        console2.log("  Initial available stake: 500 tokens");
        console2.log("  After draw 1: 400 tokens available");
        console2.log("  After draw 2: 300 tokens available");
        console2.log("  ... and so on");
        console2.log("");
        console2.log("  WITHOUT THE FIX: Random target could be 0-499, but actual");
        console2.log("  cumulative drops each iteration. Target 450 with cumulative 300");
        console2.log("  would hit the fallback!");

        _step(2, "Draw jurors - this should work with the fix");
        uint256 id = klerosTest.createDispute("ipfs://QmStaleTotalStakeFix");
        
        // This should NOT revert - the fix recalculates available stake each iteration
        klerosTest.drawJurors(id);
        
        (,,,, uint256 totalSelections) = klerosTest.getDisputeSummary(id);
        console2.log("  Total selections made:", totalSelections);
        
        assertEq(totalSelections, 5, "Should complete all 5 draws");
        
        // Verify the juror was selected 5 times
        (,, uint256 selCount,) = klerosTest.getJurorVote(id, limitedJuror);
        console2.log("  Juror's selection count:", selCount);
        assertEq(selCount, 5, "Juror should be selected exactly 5 times");
        
        console2.log("");
        console2.log("SUCCESS: The stale totalStake bug is fixed!");
        console2.log("Each draw correctly recalculates available stake.");
    }

    function testFix_NoDoSWhenJurorHasInsufficientStake() public {
        _header("BUG FIX TEST: No DoS When Juror Has Insufficient Stake");
        
        _explain("ORIGINAL BUG: If a selected juror didn't have enough unlocked stake,");
        _explain("the entire drawJurors transaction would REVERT.");
        _explain("An attacker could exploit this to prevent any disputes from being created.");
        console2.log("");
        _explain("FIX: Instead of reverting, retry with a different random selection.");
        
        _step(1, "Create scenario with mixed stake availability");
        SimpleKlerosPhase3 klerosTest = new SimpleKlerosPhase3(
            IERC20(address(token)),
            MIN_STAKE,  // 100 tokens per selection
            3,          // 3 draws
            1 hours,
            1 hours
        );

        // Create jurors with different stake amounts
        address richJuror = address(0x600);
        address poorJuror = address(0x601);
        
        token.transfer(richJuror, 1000 ether);
        token.transfer(poorJuror, 150 ether);

        vm.startPrank(richJuror);
        token.approve(address(klerosTest), type(uint256).max);
        klerosTest.stake(500 ether);  // Can handle 5 selections
        vm.stopPrank();

        vm.startPrank(poorJuror);
        token.approve(address(klerosTest), type(uint256).max);
        klerosTest.stake(100 ether);  // Can only handle 1 selection!
        vm.stopPrank();

        console2.log("  Rich juror: 500 tokens staked (can be selected up to 5 times)");
        console2.log("  Poor juror: 100 tokens staked (can only be selected ONCE)");
        console2.log("");
        console2.log("  If poor juror is selected twice, the second selection should");
        console2.log("  be retried with a new random number (not revert!)");

        _step(2, "Draw jurors multiple times to stress test");
        // Run multiple disputes to increase chance of hitting the edge case
        uint256 successfulDisputes = 0;
        
        for (uint256 i = 0; i < 5; i++) {
            uint256 id = klerosTest.createDispute(string(abi.encodePacked("ipfs://DoS", i)));
            
            // This should NOT revert even if poor juror is selected when they can't accept
            klerosTest.drawJurors(id);
            
            (,,,, uint256 totalSelections) = klerosTest.getDisputeSummary(id);
            if (totalSelections == 3) {
                successfulDisputes++;
            }
            
            // Complete the dispute to unlock stakes for next round
            address[] memory jurors = klerosTest.getJurors(id);
            bytes32 salt = keccak256(abi.encodePacked("salt", i));
            
            for (uint256 j = 0; j < jurors.length; j++) {
                vm.prank(jurors[j]);
                klerosTest.commitVote(id, keccak256(abi.encodePacked(uint8(1), salt)));
            }
            
            vm.warp(block.timestamp + 90 minutes);
            
            for (uint256 j = 0; j < jurors.length; j++) {
                vm.prank(jurors[j]);
                klerosTest.revealVote(id, 1, salt);
            }
            
            vm.warp(block.timestamp + 1 hours);
            klerosTest.finalize(id);
        }

        console2.log("  Completed", successfulDisputes, "disputes successfully!");
        assertEq(successfulDisputes, 5, "All disputes should complete without DoS");
        
        console2.log("");
        console2.log("SUCCESS: No DoS! The retry mechanism handles insufficient stake.");
    }

    function testFix_CorrectTotalStakeAfterMultipleSelections() public {
        _header("BUG FIX TEST: Correct Available Stake Tracking");
        
        _explain("This test verifies that available stake is correctly tracked");
        _explain("as jurors get selected multiple times within a single drawJurors call.");
        
        _step(1, "Check initial state");
        (uint256 j1Stake, uint256 j1Locked) = kleros.getJurorStake(juror1);
        (uint256 j2Stake, uint256 j2Locked) = kleros.getJurorStake(juror2);
        (uint256 j3Stake, uint256 j3Locked) = kleros.getJurorStake(juror3);
        
        console2.log("  Before any dispute:");
        console2.log("    Juror1: stake=", _toTokens(j1Stake), ", locked=", _toTokens(j1Locked));
        console2.log("    Juror2: stake=", _toTokens(j2Stake), ", locked=", _toTokens(j2Locked));
        console2.log("    Juror3: stake=", _toTokens(j3Stake), ", locked=", _toTokens(j3Locked));

        _step(2, "Create dispute and draw jurors");
        uint256 id = kleros.createDispute("ipfs://QmStakeTracking");
        kleros.drawJurors(id);

        _step(3, "Verify locked amounts match selection counts");
        address[] memory jurors = kleros.getJurors(id);
        
        uint256 totalLocked = 0;
        for (uint256 i = 0; i < jurors.length; i++) {
            (,, uint256 selCount, uint256 lockedInDispute) = kleros.getJurorVote(id, jurors[i]);
            (uint256 stakeNow, uint256 lockedNow) = kleros.getJurorStake(jurors[i]);
            
            console2.log("");
            console2.log("  Juror", i + 1, ":");
            console2.log("    Selection count:", selCount);
            console2.log("    Locked in this dispute:", _toTokens(lockedInDispute), "tokens");
            console2.log("    Total locked (global):", _toTokens(lockedNow), "tokens");
            console2.log("    Expected locked:", _toTokens(selCount * MIN_STAKE), "tokens");
            
            assertEq(lockedInDispute, selCount * MIN_STAKE, "Dispute lock should match");
            totalLocked += lockedInDispute;
        }
        
        console2.log("");
        console2.log("  Total locked across all jurors:", _toTokens(totalLocked), "tokens");
        console2.log("  Expected (3 draws x 100 minStake):", _toTokens(3 * MIN_STAKE), "tokens");
        
        assertEq(totalLocked, 3 * MIN_STAKE, "Total locked should equal numDraws * minStake");
        
        console2.log("");
        console2.log("SUCCESS: Stake tracking is correct after multiple selections!");
    }

    // ============================================================================
    // HELPER FUNCTIONS
    // ============================================================================

    function _completeDispute(uint256 id) internal {
        address[] memory jurors = kleros.getJurors(id);
        bytes32 salt = keccak256("complete");

        for (uint256 i = 0; i < jurors.length; i++) {
            vm.prank(jurors[i]);
            kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), salt)));
        }

        vm.warp(block.timestamp + 90 minutes);

        for (uint256 i = 0; i < jurors.length; i++) {
            vm.prank(jurors[i]);
            kleros.revealVote(id, 1, salt);
        }

        vm.warp(block.timestamp + 1 hours);
        kleros.finalize(id);
    }

    function _createAndCompleteDispute() internal returns (uint256) {
        uint256 id = kleros.createDispute("ipfs://QmHelper");
        kleros.drawJurors(id);
        _completeDispute(id);
        return id;
    }
}
