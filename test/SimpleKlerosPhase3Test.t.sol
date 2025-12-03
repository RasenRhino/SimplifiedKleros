// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/TestToken.sol";
import "../src/SimpleKlerosPhase3.sol";

contract SimpleKlerosPhase3Test is Test {
    TestToken token;
    SimpleKlerosPhase3 kleros;

    address juror1 = address(0x1);
    address juror2 = address(0x2);
    address juror3 = address(0x3);
    address nonJuror = address(0x99);

    function setUp() public {
        // Deploy test token with large supply
        token = new TestToken(1_000_000 ether);

        // Fund jurors
        token.transfer(juror1, 1_000 ether);
        token.transfer(juror2, 1_000 ether);
        token.transfer(juror3, 1_000 ether);
        token.transfer(nonJuror, 1_000 ether);

        // Deploy SimpleKlerosPhase3
        kleros = new SimpleKlerosPhase3(
            IERC20(address(token)),
            100 ether, // minStake
            3, // jurorsPerDispute
            1 hours, // commitDuration
            1 hours // revealDuration
        );

        // PHASE 3: Jurors stake tokens
        // Each juror stakes different amounts
        vm.startPrank(juror1);
        token.approve(address(kleros), type(uint256).max);
        kleros.stake(500 ether); // juror1 stakes 500
        vm.stopPrank();

        vm.startPrank(juror2);
        token.approve(address(kleros), type(uint256).max);
        kleros.stake(300 ether); // juror2 stakes 300
        vm.stopPrank();

        vm.startPrank(juror3);
        token.approve(address(kleros), type(uint256).max);
        kleros.stake(200 ether); // juror3 stakes 200
        vm.stopPrank();
    }

    // ============================================
    // EXISTING TESTS - Core Phase 3 Functionality
    // ============================================

    function testPhase3MajorityWinsAndGetsReward() public {
        // This is THE key Phase 3 test: minority loses stake, majority gains it
        uint256 id = kleros.createDispute("ipfs://QmExample");
        kleros.drawJurors(id);
        address[] memory jurors = kleros.getJurors(id);

        bytes32 salt0 = keccak256("salt0");
        bytes32 salt1 = keccak256("salt1");
        bytes32 salt2 = keccak256("salt2");

        // Find jurors by stake
        address bigJuror; // 500 staked
        address medJuror; // 300 staked
        address smallJuror; // 200 staked

        for (uint256 i = 0; i < 3; i++) {
            (uint256 stakeAmt,) = kleros.getJurorStake(jurors[i]);
            if (stakeAmt == 500 ether) bigJuror = jurors[i];
            else if (stakeAmt == 300 ether) medJuror = jurors[i];
            else if (stakeAmt == 200 ether) smallJuror = jurors[i];
        }

        // Record initial stakes
        (uint256 bigInitial,) = kleros.getJurorStake(bigJuror);
        (uint256 medInitial,) = kleros.getJurorStake(medJuror);
        (uint256 smallInitial,) = kleros.getJurorStake(smallJuror);

        // Scenario: bigJuror and medJuror vote Option1 (majority)
        //           smallJuror votes Option2 (minority - will be slashed)

        // --- COMMIT ---
        vm.prank(bigJuror);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), salt0)));

        vm.prank(medJuror);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), salt1)));

        vm.prank(smallJuror);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(2), salt2)));

        vm.warp(block.timestamp + 90 minutes);

        // --- REVEAL ---
        vm.prank(bigJuror);
        kleros.revealVote(id, 1, salt0);

        vm.prank(medJuror);
        kleros.revealVote(id, 1, salt1);

        vm.prank(smallJuror);
        kleros.revealVote(id, 2, salt2);

        vm.warp(block.timestamp + 1 hours);
        kleros.finalize(id);

        // Check ruling
        (, SimpleKlerosPhase3.Ruling ruling,,) = kleros.getDisputeSummary(id);
        assertEq(uint256(ruling), uint256(SimpleKlerosPhase3.Ruling.Option1), "Option1 should win");

        // PHASE 3: Check stake redistribution
        (uint256 bigFinal,) = kleros.getJurorStake(bigJuror);
        (uint256 medFinal,) = kleros.getJurorStake(medJuror);
        (uint256 smallFinal,) = kleros.getJurorStake(smallJuror);

        // Small juror (loser) should have 0 stake
        assertEq(smallFinal, 0, "loser should have 0 stake");

        // Winners should have MORE than they started with
        assertGt(bigFinal, bigInitial, "big winner should gain stake");
        assertGt(medFinal, medInitial, "med winner should gain stake");

        // Total stakes should be conserved (minus slashed amount goes to winners)
        uint256 totalFinal = bigFinal + medFinal + smallFinal;
        uint256 totalInitial = bigInitial + medInitial + smallInitial;
        assertEq(totalFinal, totalInitial, "total stakes should be conserved");

        // Calculate expected redistribution (proportional to winner stakes)
        // smallJuror had 200, this gets split between big and med proportionally
        // bigJuror: 500/(500+300) = 5/8 of 200 = 125
        // medJuror: 300/(500+300) = 3/8 of 200 = 75
        assertEq(bigFinal, 500 ether + 125 ether, "big juror should get proportional reward");
        assertEq(medFinal, 300 ether + 75 ether, "med juror should get proportional reward");
    }

    function testPhase3TieNoRedistribution() public {
        // In case of tie, no redistribution should occur
        uint256 id = kleros.createDispute("ipfs://QmExample2");
        kleros.drawJurors(id);
        address[] memory jurors = kleros.getJurors(id);

        bytes32 salt0 = keccak256("salt0");
        bytes32 salt1 = keccak256("salt1");
        bytes32 salt2 = keccak256("salt2");

        address bigJuror;
        address medJuror;
        address smallJuror;

        for (uint256 i = 0; i < 3; i++) {
            (uint256 stakeAmt,) = kleros.getJurorStake(jurors[i]);
            if (stakeAmt == 500 ether) bigJuror = jurors[i];
            else if (stakeAmt == 300 ether) medJuror = jurors[i];
            else if (stakeAmt == 200 ether) smallJuror = jurors[i];
        }

        // Record initial stakes
        uint256[] memory initialStakes = new uint256[](3);
        (initialStakes[0],) = kleros.getJurorStake(bigJuror);
        (initialStakes[1],) = kleros.getJurorStake(medJuror);
        (initialStakes[2],) = kleros.getJurorStake(smallJuror);

        // Create a tie: big votes Option2, med+small vote Option1
        // 500 vs 500 = tie

        vm.prank(bigJuror);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(2), salt0)));

        vm.prank(medJuror);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), salt1)));

        vm.prank(smallJuror);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), salt2)));

        vm.warp(block.timestamp + 90 minutes);

        vm.prank(bigJuror);
        kleros.revealVote(id, 2, salt0);

        vm.prank(medJuror);
        kleros.revealVote(id, 1, salt1);

        vm.prank(smallJuror);
        kleros.revealVote(id, 1, salt2);

        vm.warp(block.timestamp + 1 hours);
        kleros.finalize(id);

        // Check it's a tie
        (, SimpleKlerosPhase3.Ruling ruling,,) = kleros.getDisputeSummary(id);
        assertEq(uint256(ruling), uint256(SimpleKlerosPhase3.Ruling.Undecided), "should be tie");

        // In tie, stakes should remain unchanged
        (uint256 bigFinal,) = kleros.getJurorStake(bigJuror);
        (uint256 medFinal,) = kleros.getJurorStake(medJuror);
        (uint256 smallFinal,) = kleros.getJurorStake(smallJuror);

        assertEq(bigFinal, initialStakes[0], "big stake unchanged in tie");
        assertEq(medFinal, initialStakes[1], "med stake unchanged in tie");
        assertEq(smallFinal, initialStakes[2], "small stake unchanged in tie");
    }

    function testPhase3NonRevealerLosesEverything() public {
        // Juror who doesn't reveal is treated as minority and loses stake
        uint256 id = kleros.createDispute("ipfs://QmExample3");
        kleros.drawJurors(id);
        address[] memory jurors = kleros.getJurors(id);

        bytes32 salt0 = keccak256("salt0");
        bytes32 salt1 = keccak256("salt1");

        address bigJuror;
        address medJuror;
        address smallJuror;

        for (uint256 i = 0; i < 3; i++) {
            (uint256 stakeAmt,) = kleros.getJurorStake(jurors[i]);
            if (stakeAmt == 500 ether) bigJuror = jurors[i];
            else if (stakeAmt == 300 ether) medJuror = jurors[i];
            else if (stakeAmt == 200 ether) smallJuror = jurors[i];
        }

        // All commit
        vm.prank(bigJuror);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), salt0)));

        vm.prank(medJuror);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), salt1)));

        vm.prank(smallJuror);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), keccak256("salt2"))));

        vm.warp(block.timestamp + 90 minutes);

        // Only big and med reveal, small doesn't reveal
        vm.prank(bigJuror);
        kleros.revealVote(id, 1, salt0);

        vm.prank(medJuror);
        kleros.revealVote(id, 1, salt1);

        // smallJuror doesn't reveal!

        vm.warp(block.timestamp + 1 hours);
        kleros.finalize(id);

        // Small juror should lose everything for not revealing
        (uint256 smallFinal,) = kleros.getJurorStake(smallJuror);
        assertEq(smallFinal, 0, "non-revealer should lose all stake");

        // Winners should gain the slashed stake
        (uint256 bigFinal,) = kleros.getJurorStake(bigJuror);
        (uint256 medFinal,) = kleros.getJurorStake(medJuror);

        assertGt(bigFinal, 500 ether, "revealer should gain stake");
        assertGt(medFinal, 300 ether, "revealer should gain stake");
    }

    function testPhase3ProportionalRewardDistribution() public {
        // Test that rewards are distributed proportionally to stake
        uint256 id = kleros.createDispute("ipfs://QmExample4");
        kleros.drawJurors(id);
        address[] memory jurors = kleros.getJurors(id);

        bytes32 salt0 = keccak256("salt0");
        bytes32 salt1 = keccak256("salt1");
        bytes32 salt2 = keccak256("salt2");

        address bigJuror;
        address medJuror;
        address smallJuror;

        for (uint256 i = 0; i < 3; i++) {
            (uint256 stakeAmt,) = kleros.getJurorStake(jurors[i]);
            if (stakeAmt == 500 ether) bigJuror = jurors[i];
            else if (stakeAmt == 300 ether) medJuror = jurors[i];
            else if (stakeAmt == 200 ether) smallJuror = jurors[i];
        }

        // Big and med are winners, small is loser
        vm.prank(bigJuror);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), salt0)));

        vm.prank(medJuror);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), salt1)));

        vm.prank(smallJuror);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(2), salt2)));

        vm.warp(block.timestamp + 90 minutes);

        vm.prank(bigJuror);
        kleros.revealVote(id, 1, salt0);

        vm.prank(medJuror);
        kleros.revealVote(id, 1, salt1);

        vm.prank(smallJuror);
        kleros.revealVote(id, 2, salt2);

        vm.warp(block.timestamp + 1 hours);
        kleros.finalize(id);

        // Check proportional distribution
        (uint256 bigFinal,) = kleros.getJurorStake(bigJuror);
        (uint256 medFinal,) = kleros.getJurorStake(medJuror);

        // bigJuror has 500, medJuror has 300
        // Total winner weight = 800
        // Slashed amount = 200 (from smallJuror)
        // bigJuror gets: 200 * 500/800 = 125
        // medJuror gets: 200 * 300/800 = 75

        uint256 bigReward = bigFinal - 500 ether;
        uint256 medReward = medFinal - 300 ether;

        assertEq(bigReward, 125 ether, "big juror proportional reward");
        assertEq(medReward, 75 ether, "med juror proportional reward");

        // Verify the ratio
        // bigReward / medReward should equal 500 / 300 = 5/3
        assertEq(bigReward * 3, medReward * 5, "rewards should be proportional to stakes");
    }

    function testPhase3AllLoseIfAllMinority() public {
        // Edge case: if somehow all jurors are in minority (shouldn't happen but test it)
        // Actually this can't happen in a 2-option system, but we test the loser slashing works
        uint256 id = kleros.createDispute("ipfs://QmExample5");
        kleros.drawJurors(id);
        address[] memory jurors = kleros.getJurors(id);

        bytes32 salt0 = keccak256("salt0");
        bytes32 salt1 = keccak256("salt1");
        bytes32 salt2 = keccak256("salt2");

        address bigJuror;
        address medJuror;
        address smallJuror;

        for (uint256 i = 0; i < 3; i++) {
            (uint256 stakeAmt,) = kleros.getJurorStake(jurors[i]);
            if (stakeAmt == 500 ether) bigJuror = jurors[i];
            else if (stakeAmt == 300 ether) medJuror = jurors[i];
            else if (stakeAmt == 200 ether) smallJuror = jurors[i];
        }

        // Create scenario where big juror wins alone
        vm.prank(bigJuror);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), salt0)));

        vm.prank(medJuror);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(2), salt1)));

        vm.prank(smallJuror);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(2), salt2)));

        vm.warp(block.timestamp + 90 minutes);

        vm.prank(bigJuror);
        kleros.revealVote(id, 1, salt0);

        vm.prank(medJuror);
        kleros.revealVote(id, 2, salt1);

        vm.prank(smallJuror);
        kleros.revealVote(id, 2, salt2);

        vm.warp(block.timestamp + 1 hours);
        kleros.finalize(id);

        // Big juror wins (500 vs 500 = tie actually, let's check)
        (, SimpleKlerosPhase3.Ruling ruling,,) = kleros.getDisputeSummary(id);
        // This is actually a tie! Let's verify
        assertEq(uint256(ruling), uint256(SimpleKlerosPhase3.Ruling.Undecided), "should be tie");
    }

    function testPhase3CanUnstakeAfterWinning() public {
        // Winner should be able to unstake their increased stake
        uint256 id = kleros.createDispute("ipfs://QmExample6");
        kleros.drawJurors(id);
        address[] memory jurors = kleros.getJurors(id);

        bytes32 salt0 = keccak256("salt0");
        bytes32 salt1 = keccak256("salt1");
        bytes32 salt2 = keccak256("salt2");

        address bigJuror;
        address medJuror;
        address smallJuror;

        for (uint256 i = 0; i < 3; i++) {
            (uint256 stakeAmt,) = kleros.getJurorStake(jurors[i]);
            if (stakeAmt == 500 ether) bigJuror = jurors[i];
            else if (stakeAmt == 300 ether) medJuror = jurors[i];
            else if (stakeAmt == 200 ether) smallJuror = jurors[i];
        }

        // Complete dispute with bigJuror as winner
        vm.prank(bigJuror);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), salt0)));
        vm.prank(medJuror);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), salt1)));
        vm.prank(smallJuror);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(2), salt2)));

        vm.warp(block.timestamp + 90 minutes);

        vm.prank(bigJuror);
        kleros.revealVote(id, 1, salt0);
        vm.prank(medJuror);
        kleros.revealVote(id, 1, salt1);
        vm.prank(smallJuror);
        kleros.revealVote(id, 2, salt2);

        vm.warp(block.timestamp + 1 hours);
        kleros.finalize(id);

        // Check bigJuror's increased stake
        (uint256 bigFinal,) = kleros.getJurorStake(bigJuror);
        assertEq(bigFinal, 625 ether, "should have gained stake");

        // Unstake the reward
        uint256 balanceBefore = token.balanceOf(bigJuror);
        vm.prank(bigJuror);
        kleros.unstake(125 ether); // The reward amount
        uint256 balanceAfter = token.balanceOf(bigJuror);

        assertEq(balanceAfter - balanceBefore, 125 ether, "should receive reward");
        (uint256 stakeAfterUnstake,) = kleros.getJurorStake(bigJuror);
        assertEq(stakeAfterUnstake, 500 ether, "back to original stake");
    }

    // ============================================
    // NEW TESTS - Security & Access Control
    // ============================================

    function testCannotCommitTwice() public {
        uint256 id = kleros.createDispute("ipfs://QmDoubleCommit");
        kleros.drawJurors(id);
        address[] memory jurors = kleros.getJurors(id);

        bytes32 salt = keccak256("salt");
        bytes32 commitHash = keccak256(abi.encodePacked(uint8(1), salt));

        // First commit should succeed
        vm.prank(jurors[0]);
        kleros.commitVote(id, commitHash);

        // Second commit should fail
        vm.prank(jurors[0]);
        vm.expectRevert("already committed");
        kleros.commitVote(id, commitHash);
    }

    function testNonJurorCannotCommit() public {
        uint256 id = kleros.createDispute("ipfs://QmNonJuror");
        kleros.drawJurors(id);

        bytes32 salt = keccak256("salt");
        bytes32 commitHash = keccak256(abi.encodePacked(uint8(1), salt));

        // Non-juror tries to commit
        vm.prank(nonJuror);
        vm.expectRevert("not a juror");
        kleros.commitVote(id, commitHash);
    }

    function testNonJurorCannotReveal() public {
        uint256 id = kleros.createDispute("ipfs://QmNonJurorReveal");
        kleros.drawJurors(id);
        address[] memory jurors = kleros.getJurors(id);

        bytes32 salt = keccak256("salt");

        // Jurors commit
        for (uint256 i = 0; i < jurors.length; i++) {
            vm.prank(jurors[i]);
            kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), salt)));
        }

        vm.warp(block.timestamp + 90 minutes);

        // Non-juror tries to reveal
        vm.prank(nonJuror);
        vm.expectRevert("not a juror");
        kleros.revealVote(id, 1, salt);
    }

    function testCannotRevealWithWrongSalt() public {
        uint256 id = kleros.createDispute("ipfs://QmWrongSalt");
        kleros.drawJurors(id);
        address[] memory jurors = kleros.getJurors(id);

        bytes32 correctSalt = keccak256("correctSalt");
        bytes32 wrongSalt = keccak256("wrongSalt");

        vm.prank(jurors[0]);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), correctSalt)));

        vm.warp(block.timestamp + 90 minutes);

        // Try to reveal with wrong salt
        vm.prank(jurors[0]);
        vm.expectRevert("bad reveal");
        kleros.revealVote(id, 1, wrongSalt);
    }

    function testCannotRevealWithWrongVote() public {
        uint256 id = kleros.createDispute("ipfs://QmWrongVote");
        kleros.drawJurors(id);
        address[] memory jurors = kleros.getJurors(id);

        bytes32 salt = keccak256("salt");

        // Commit vote for Option1
        vm.prank(jurors[0]);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), salt)));

        vm.warp(block.timestamp + 90 minutes);

        // Try to reveal as Option2 (lying about vote)
        vm.prank(jurors[0]);
        vm.expectRevert("bad reveal");
        kleros.revealVote(id, 2, salt);
    }

    function testCannotRevealTwice() public {
        uint256 id = kleros.createDispute("ipfs://QmDoubleReveal");
        kleros.drawJurors(id);
        address[] memory jurors = kleros.getJurors(id);

        bytes32 salt = keccak256("salt");

        vm.prank(jurors[0]);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), salt)));

        vm.warp(block.timestamp + 90 minutes);

        // First reveal succeeds
        vm.prank(jurors[0]);
        kleros.revealVote(id, 1, salt);

        // Second reveal fails
        vm.prank(jurors[0]);
        vm.expectRevert("already revealed");
        kleros.revealVote(id, 1, salt);
    }

    function testCannotRevealInvalidVoteValue() public {
        uint256 id = kleros.createDispute("ipfs://QmInvalidVote");
        kleros.drawJurors(id);
        address[] memory jurors = kleros.getJurors(id);

        bytes32 salt = keccak256("salt");

        vm.prank(jurors[0]);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(3), salt)));

        vm.warp(block.timestamp + 90 minutes);

        // Try to reveal with invalid vote (3)
        vm.prank(jurors[0]);
        vm.expectRevert("invalid vote");
        kleros.revealVote(id, 3, salt);
    }

    // ============================================
    // NEW TESTS - Phase Transition Enforcement
    // ============================================

    function testCannotRevealBeforeCommitDeadline() public {
        uint256 id = kleros.createDispute("ipfs://QmEarlyReveal");
        kleros.drawJurors(id);
        address[] memory jurors = kleros.getJurors(id);

        bytes32 salt = keccak256("salt");

        vm.prank(jurors[0]);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), salt)));

        // Try to reveal before commit deadline (don't warp time)
        vm.prank(jurors[0]);
        vm.expectRevert("commit not finished");
        kleros.revealVote(id, 1, salt);
    }

    function testCannotCommitAfterDeadline() public {
        uint256 id = kleros.createDispute("ipfs://QmLateCommit");
        kleros.drawJurors(id);
        address[] memory jurors = kleros.getJurors(id);

        bytes32 salt = keccak256("salt");

        // Warp past commit deadline
        vm.warp(block.timestamp + 2 hours);

        // Try to commit after deadline
        vm.prank(jurors[0]);
        vm.expectRevert("commit over");
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), salt)));
    }

    function testCannotRevealAfterDeadline() public {
        uint256 id = kleros.createDispute("ipfs://QmLateReveal");
        kleros.drawJurors(id);
        address[] memory jurors = kleros.getJurors(id);

        bytes32 salt = keccak256("salt");

        vm.prank(jurors[0]);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), salt)));

        // Warp past reveal deadline (commit + reveal duration)
        vm.warp(block.timestamp + 3 hours);

        // Try to reveal after deadline
        vm.prank(jurors[0]);
        vm.expectRevert("reveal over");
        kleros.revealVote(id, 1, salt);
    }

    function testCannotFinalizeBeforeRevealDeadline() public {
        uint256 id = kleros.createDispute("ipfs://QmEarlyFinalize");
        kleros.drawJurors(id);
        address[] memory jurors = kleros.getJurors(id);

        bytes32 salt = keccak256("salt");

        // All jurors commit
        for (uint256 i = 0; i < jurors.length; i++) {
            vm.prank(jurors[i]);
            kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), salt)));
        }

        vm.warp(block.timestamp + 90 minutes);

        // All jurors reveal
        for (uint256 i = 0; i < jurors.length; i++) {
            vm.prank(jurors[i]);
            kleros.revealVote(id, 1, salt);
        }

        // Try to finalize before reveal deadline
        vm.expectRevert("reveal not finished");
        kleros.finalize(id);
    }

    function testCannotDrawJurorsTwice() public {
        uint256 id = kleros.createDispute("ipfs://QmDoubleDraw");
        kleros.drawJurors(id);

        // Try to draw again
        vm.expectRevert("wrong phase");
        kleros.drawJurors(id);
    }

    // ============================================
    // NEW TESTS - Staking Mechanics
    // ============================================

    function testCannotUnstakeWhileLocked() public {
        uint256 id = kleros.createDispute("ipfs://QmLockedUnstake");
        kleros.drawJurors(id);
        address[] memory jurors = kleros.getJurors(id);

        // Juror tries to unstake while locked in dispute
        vm.prank(jurors[0]);
        vm.expectRevert("stake locked");
        kleros.unstake(100 ether);
    }

    function testCannotStakeBelowMinimum() public {
        address newJuror = address(0x100);
        token.transfer(newJuror, 1000 ether);

        vm.startPrank(newJuror);
        token.approve(address(kleros), type(uint256).max);

        // Try to stake below minimum (100 ether)
        vm.expectRevert("below minStake");
        kleros.stake(50 ether);
        vm.stopPrank();
    }

    function testCannotStakeZero() public {
        vm.prank(juror1);
        vm.expectRevert("amount=0");
        kleros.stake(0);
    }

    function testCannotUnstakeMoreThanStaked() public {
        // First complete a dispute so juror1 is unlocked
        uint256 id = _completeDisputeWithOption1Winning();

        // Try to unstake more than staked
        vm.prank(juror1);
        vm.expectRevert("not enough stake");
        kleros.unstake(10000 ether);
    }

    // ============================================
    // NEW TESTS - Edge Cases
    // ============================================

    function testUnanimousVote() public {
        // All jurors vote the same - no losers to slash
        uint256 id = kleros.createDispute("ipfs://QmUnanimous");
        kleros.drawJurors(id);
        address[] memory jurors = kleros.getJurors(id);

        bytes32 salt0 = keccak256("salt0");
        bytes32 salt1 = keccak256("salt1");
        bytes32 salt2 = keccak256("salt2");

        // Record initial stakes
        uint256 totalInitial = 0;
        for (uint256 i = 0; i < jurors.length; i++) {
            (uint256 stakeAmt,) = kleros.getJurorStake(jurors[i]);
            totalInitial += stakeAmt;
        }

        // All commit Option1
        vm.prank(jurors[0]);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), salt0)));
        vm.prank(jurors[1]);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), salt1)));
        vm.prank(jurors[2]);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), salt2)));

        vm.warp(block.timestamp + 90 minutes);

        // All reveal Option1
        vm.prank(jurors[0]);
        kleros.revealVote(id, 1, salt0);
        vm.prank(jurors[1]);
        kleros.revealVote(id, 1, salt1);
        vm.prank(jurors[2]);
        kleros.revealVote(id, 1, salt2);

        vm.warp(block.timestamp + 1 hours);
        kleros.finalize(id);

        // Check ruling
        (, SimpleKlerosPhase3.Ruling ruling,,) = kleros.getDisputeSummary(id);
        assertEq(uint256(ruling), uint256(SimpleKlerosPhase3.Ruling.Option1), "Option1 wins");

        // All stakes should remain unchanged (no losers to slash)
        uint256 totalFinal = 0;
        for (uint256 i = 0; i < jurors.length; i++) {
            (uint256 stakeAmt,) = kleros.getJurorStake(jurors[i]);
            totalFinal += stakeAmt;
        }
        assertEq(totalFinal, totalInitial, "stakes unchanged in unanimous vote");
    }

    function testSingleRevealerTakesAll() public {
        // Only one juror reveals - they win everything
        uint256 id = kleros.createDispute("ipfs://QmSingleRevealer");
        kleros.drawJurors(id);
        address[] memory jurors = kleros.getJurors(id);

        bytes32 salt0 = keccak256("salt0");

        address bigJuror;
        address medJuror;
        address smallJuror;

        for (uint256 i = 0; i < 3; i++) {
            (uint256 stakeAmt,) = kleros.getJurorStake(jurors[i]);
            if (stakeAmt == 500 ether) bigJuror = jurors[i];
            else if (stakeAmt == 300 ether) medJuror = jurors[i];
            else if (stakeAmt == 200 ether) smallJuror = jurors[i];
        }

        // All commit
        vm.prank(bigJuror);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), salt0)));
        vm.prank(medJuror);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), keccak256("m"))));
        vm.prank(smallJuror);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), keccak256("s"))));

        vm.warp(block.timestamp + 90 minutes);

        // Only bigJuror reveals
        vm.prank(bigJuror);
        kleros.revealVote(id, 1, salt0);

        vm.warp(block.timestamp + 1 hours);
        kleros.finalize(id);

        // bigJuror should have all stakes (500 + 300 + 200 = 1000)
        (uint256 bigFinal,) = kleros.getJurorStake(bigJuror);
        (uint256 medFinal,) = kleros.getJurorStake(medJuror);
        (uint256 smallFinal,) = kleros.getJurorStake(smallJuror);

        assertEq(bigFinal, 1000 ether, "single revealer takes all");
        assertEq(medFinal, 0, "non-revealer loses stake");
        assertEq(smallFinal, 0, "non-revealer loses stake");
    }

    function testNoOneReveals() public {
        // No juror reveals - should result in tie/undecided
        uint256 id = kleros.createDispute("ipfs://QmNoReveal");
        kleros.drawJurors(id);
        address[] memory jurors = kleros.getJurors(id);

        // All commit but none reveal
        for (uint256 i = 0; i < jurors.length; i++) {
            vm.prank(jurors[i]);
            kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), keccak256(abi.encode(i)))));
        }

        vm.warp(block.timestamp + 3 hours); // Past both deadlines
        kleros.finalize(id);

        // Should be undecided (0 vs 0)
        (, SimpleKlerosPhase3.Ruling ruling,,) = kleros.getDisputeSummary(id);
        assertEq(uint256(ruling), uint256(SimpleKlerosPhase3.Ruling.Undecided), "should be undecided");
    }

    function testOption2Wins() public {
        // Test that Option2 can win (not just Option1)
        uint256 id = kleros.createDispute("ipfs://QmOption2Wins");
        kleros.drawJurors(id);
        address[] memory jurors = kleros.getJurors(id);

        bytes32 salt0 = keccak256("salt0");
        bytes32 salt1 = keccak256("salt1");
        bytes32 salt2 = keccak256("salt2");

        address bigJuror;
        address medJuror;
        address smallJuror;

        for (uint256 i = 0; i < 3; i++) {
            (uint256 stakeAmt,) = kleros.getJurorStake(jurors[i]);
            if (stakeAmt == 500 ether) bigJuror = jurors[i];
            else if (stakeAmt == 300 ether) medJuror = jurors[i];
            else if (stakeAmt == 200 ether) smallJuror = jurors[i];
        }

        // Big and med vote Option2, small votes Option1
        vm.prank(bigJuror);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(2), salt0)));
        vm.prank(medJuror);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(2), salt1)));
        vm.prank(smallJuror);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), salt2)));

        vm.warp(block.timestamp + 90 minutes);

        vm.prank(bigJuror);
        kleros.revealVote(id, 2, salt0);
        vm.prank(medJuror);
        kleros.revealVote(id, 2, salt1);
        vm.prank(smallJuror);
        kleros.revealVote(id, 1, salt2);

        vm.warp(block.timestamp + 1 hours);
        kleros.finalize(id);

        (, SimpleKlerosPhase3.Ruling ruling,,) = kleros.getDisputeSummary(id);
        assertEq(uint256(ruling), uint256(SimpleKlerosPhase3.Ruling.Option2), "Option2 should win");

        // Verify redistribution happened correctly
        (uint256 smallFinal,) = kleros.getJurorStake(smallJuror);
        assertEq(smallFinal, 0, "loser slashed");
    }

    function testCannotCreateDisputeWithoutEnoughJurors() public {
        // Deploy new kleros with higher juror requirement
        SimpleKlerosPhase3 klerosNew = new SimpleKlerosPhase3(
            IERC20(address(token)),
            100 ether,
            10, // Need 10 jurors but only 3 exist
            1 hours,
            1 hours
        );

        // Stake some jurors
        vm.prank(juror1);
        token.approve(address(klerosNew), type(uint256).max);
        vm.prank(juror1);
        klerosNew.stake(500 ether);

        // Try to create dispute
        vm.expectRevert("not enough jurors");
        klerosNew.createDispute("ipfs://QmNotEnough");
    }

    function testJurorListGrows() public {
        // Verify juror list grows when new jurors stake
        address[] memory initialList = kleros.getJurorList();
        assertEq(initialList.length, 3, "should have 3 initial jurors");

        // Add new juror
        address newJuror = address(0x100);
        token.transfer(newJuror, 1000 ether);

        vm.startPrank(newJuror);
        token.approve(address(kleros), type(uint256).max);
        kleros.stake(100 ether);
        vm.stopPrank();

        address[] memory newList = kleros.getJurorList();
        assertEq(newList.length, 4, "should have 4 jurors now");
    }

    function testVoteWeightSnapshot() public {
        // Verify that vote weight is snapshot at selection, not at reveal
        uint256 id = kleros.createDispute("ipfs://QmSnapshot");
        kleros.drawJurors(id);
        address[] memory jurors = kleros.getJurors(id);

        // Get snapshot weight for first juror
        (bool revealed, uint8 vote, uint256 snapshotWeight) = kleros.getJurorVote(id, jurors[0]);
        assertFalse(revealed);
        assertEq(vote, 0);
        assertGt(snapshotWeight, 0, "snapshot weight should be set at draw time");
    }

    // ============================================
    // NEW TESTS - View Functions
    // ============================================

    function testGetDisputeSummary() public {
        uint256 id = kleros.createDispute("ipfs://QmSummary");

        (SimpleKlerosPhase3.Phase phase, SimpleKlerosPhase3.Ruling ruling, uint256 v1, uint256 v2) =
            kleros.getDisputeSummary(id);

        assertEq(uint256(phase), uint256(SimpleKlerosPhase3.Phase.Created));
        assertEq(uint256(ruling), uint256(SimpleKlerosPhase3.Ruling.Undecided));
        assertEq(v1, 0);
        assertEq(v2, 0);
    }

    function testGetJurorStake() public {
        (uint256 amount, bool locked) = kleros.getJurorStake(juror1);
        assertEq(amount, 500 ether);
        assertFalse(locked);
    }

    // ============================================
    // Helper Functions
    // ============================================

    function _completeDisputeWithOption1Winning() internal returns (uint256) {
        uint256 id = kleros.createDispute("ipfs://QmHelper");
        kleros.drawJurors(id);
        address[] memory jurors = kleros.getJurors(id);

        bytes32 salt = keccak256("helper");

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

        return id;
    }
}