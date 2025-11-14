// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/TestToken.sol";
import "../src/SimpleKlerosPhase2.sol";

contract SimpleKlerosPhase2Test is Test {
    TestToken token;
    SimpleKlerosPhase2 kleros;

    address juror1 = address(0x1);
    address juror2 = address(0x2);
    address juror3 = address(0x3);

    function setUp() public {
        // Deploy test token with large supply
        token = new TestToken(1_000_000 ether);

        // Fund jurors
        token.transfer(juror1, 1_000 ether);
        token.transfer(juror2, 1_000 ether);
        token.transfer(juror3, 1_000 ether);

        // Deploy SimpleKlerosPhase2
        kleros = new SimpleKlerosPhase2(
            IERC20(address(token)),
            100 ether, // minStake
            3, // jurorsPerDispute
            1 hours, // commitDuration
            1 hours // revealDuration
        );

        // PHASE 2: Jurors must STAKE (not just register)
        // Each juror stakes different amounts to test weighted voting
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

    function testPhase2StakeBasedWeighting() public {
        // 1. Create dispute
        uint256 id = kleros.createDispute("ipfs://QmExample");

        // 2. Draw jurors
        kleros.drawJurors(id);
        address[] memory jurors = kleros.getJurors(id);
        assertEq(jurors.length, 3, "must have 3 jurors");

        // Verify stakes are locked
        for (uint256 i = 0; i < 3; i++) {
            (, bool locked) = kleros.getJurorStake(jurors[i]);
            assertTrue(locked, "stake should be locked");
        }

        // 3. Prepare salts
        bytes32 salt0 = keccak256("salt0");
        bytes32 salt1 = keccak256("salt1");
        bytes32 salt2 = keccak256("salt2");

        // Find which juror is which based on stake
        address bigJuror; // 500 staked
        address medJuror; // 300 staked
        address smallJuror; // 200 staked

        for (uint256 i = 0; i < 3; i++) {
            (uint256 stakeAmt,) = kleros.getJurorStake(jurors[i]);
            if (stakeAmt == 500 ether) bigJuror = jurors[i];
            else if (stakeAmt == 300 ether) medJuror = jurors[i];
            else if (stakeAmt == 200 ether) smallJuror = jurors[i];
        }

        // --- COMMIT PHASE ---
        // Big juror votes Option2
        vm.prank(bigJuror);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(2), salt0)));

        // Med juror votes Option1
        vm.prank(medJuror);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), salt1)));

        // Small juror votes Option1
        vm.prank(smallJuror);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), salt2)));

        // Move into reveal phase
        vm.warp(block.timestamp + 2 hours);

        // --- REVEAL PHASE ---
        vm.prank(bigJuror);
        kleros.revealVote(id, 2, salt0);

        vm.prank(medJuror);
        kleros.revealVote(id, 1, salt1);

        vm.prank(smallJuror);
        kleros.revealVote(id, 1, salt2);

        // Verify weights are based on STAKED amounts
        (bool revealed1, uint8 vote1, uint256 weight1) = kleros.getJurorVote(id, bigJuror);
        assertTrue(revealed1, "bigJuror should have revealed");
        assertEq(weight1, 500 ether, "bigJuror weight should be staked amount");
        assertEq(vote1, 2, "bigJuror vote wrong");

        (bool revealed2, uint8 vote2, uint256 weight2) = kleros.getJurorVote(id, medJuror);
        assertTrue(revealed2, "medJuror should have revealed");
        assertEq(weight2, 300 ether, "medJuror weight should be staked amount");
        assertEq(vote2, 1, "medJuror vote wrong");

        // Move beyond revealDeadline, then finalize
        vm.warp(block.timestamp + 2 hours);
        kleros.finalize(id);

        // Check final results
        (, SimpleKlerosPhase2.Ruling ruling, uint256 v1, uint256 v2) = kleros.getDisputeSummary(id);

        // Option1: 300 + 200 = 500
        // Option2: 500
        // Should be Undecided (tie)
        assertEq(uint256(ruling), uint256(SimpleKlerosPhase2.Ruling.Undecided), "should be tie");
        assertEq(v1, 500 ether, "Option1 weighted votes should be 500");
        assertEq(v2, 500 ether, "Option2 weighted votes should be 500");

        // Verify stakes are unlocked after finalization
        for (uint256 i = 0; i < 3; i++) {
            (, bool locked) = kleros.getJurorStake(jurors[i]);
            assertFalse(locked, "stake should be unlocked after finalization");
        }
    }

    function testPhase2MajorityWins() public {
        uint256 id = kleros.createDispute("ipfs://QmExample2");
        kleros.drawJurors(id);
        address[] memory jurors = kleros.getJurors(id);

        bytes32 salt0 = keccak256("salt0");
        bytes32 salt1 = keccak256("salt1");
        bytes32 salt2 = keccak256("salt2");

        // Find jurors by stake
        address bigJuror;
        address medJuror;
        address smallJuror;

        for (uint256 i = 0; i < 3; i++) {
            (uint256 stakeAmt,) = kleros.getJurorStake(jurors[i]);
            if (stakeAmt == 500 ether) bigJuror = jurors[i];
            else if (stakeAmt == 300 ether) medJuror = jurors[i];
            else if (stakeAmt == 200 ether) smallJuror = jurors[i];
        }

        // This time: juror1 (500) and juror2 (300) vote Option1
        // juror3 (200) votes Option2
        // Option1 should WIN with 800 vs 200

        // --- COMMIT ---
        vm.prank(bigJuror);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), salt0)));

        vm.prank(medJuror);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), salt1)));

        vm.prank(smallJuror);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(2), salt2)));

        vm.warp(block.timestamp + 2 hours);

        // --- REVEAL ---
        vm.prank(bigJuror);
        kleros.revealVote(id, 1, salt0);

        vm.prank(medJuror);
        kleros.revealVote(id, 1, salt1);

        vm.prank(smallJuror);
        kleros.revealVote(id, 2, salt2);

        vm.warp(block.timestamp + 2 hours);
        kleros.finalize(id);

        // Check results
        (, SimpleKlerosPhase2.Ruling ruling,,) = kleros.getDisputeSummary(id);
        assertEq(uint256(ruling), uint256(SimpleKlerosPhase2.Ruling.Option1), "Option1 should win");

        (,, uint256 v1, uint256 v2) = kleros.getDisputeSummary(id);
        assertEq(v1, 800 ether, "Option1 weighted votes");
        assertEq(v2, 200 ether, "Option2 weighted votes");
    }

    function testCannotUnstakeWhileLocked() public {
        // Create dispute and draw jurors
        uint256 id = kleros.createDispute("ipfs://QmExample3");
        kleros.drawJurors(id);

        // Try to unstake while locked in dispute
        vm.prank(juror1);
        vm.expectRevert("stake locked");
        kleros.unstake(100 ether);
    }

    function testCanUnstakeAfterFinalization() public {
        // Create and complete a dispute
        uint256 id = kleros.createDispute("ipfs://QmExample4");
        kleros.drawJurors(id);
        address[] memory jurors = kleros.getJurors(id);

        // Complete the dispute - COMMIT phase
        bytes32 salt = keccak256("salt");
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(jurors[i]);
            kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), salt)));
        }

        // Move time forward by 4 hours (past both deadlines)
        // commitDeadline = 1 hour, revealDeadline = 2 hours
        // But we need to reveal BEFORE revealDeadline, so warp to 1.5 hours first
        vm.warp(block.timestamp + 90 minutes); // 1.5 hours - in reveal window

        // REVEAL phase
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(jurors[i]);
            kleros.revealVote(id, 1, salt);
        }

        // Now warp past reveal deadline (another 1 hour to get to 2.5 hours total)
        vm.warp(block.timestamp + 1 hours);
        kleros.finalize(id);

        // Now jurors should be able to unstake
        uint256 balanceBefore = token.balanceOf(juror1);
        vm.prank(juror1);
        kleros.unstake(100 ether);
        uint256 balanceAfter = token.balanceOf(juror1);

        assertEq(balanceAfter - balanceBefore, 100 ether, "should receive unstaked tokens");

        (uint256 stakeAmt,) = kleros.getJurorStake(juror1);
        assertEq(stakeAmt, 400 ether, "stake should be reduced");
    }

    function testCannotStakeBelowMinimum() public {
        address newJuror = address(0x99);
        token.transfer(newJuror, 1_000 ether);

        vm.startPrank(newJuror);
        token.approve(address(kleros), type(uint256).max);

        // Try to stake below minimum
        vm.expectRevert("below minStake");
        kleros.stake(50 ether);
        vm.stopPrank();
    }

    function testCanStakeMultipleTimes() public {
        address newJuror = address(0x99);
        token.transfer(newJuror, 1_000 ether);

        vm.startPrank(newJuror);
        token.approve(address(kleros), type(uint256).max);

        // First stake
        kleros.stake(100 ether);
        (uint256 stake1,) = kleros.getJurorStake(newJuror);
        assertEq(stake1, 100 ether, "first stake");

        // Second stake
        kleros.stake(50 ether);
        (uint256 stake2,) = kleros.getJurorStake(newJuror);
        assertEq(stake2, 150 ether, "combined stake");

        vm.stopPrank();
    }

    function testCannotUnstakeMoreThanStaked() public {
        vm.prank(juror1);
        vm.expectRevert("not enough stake");
        kleros.unstake(1000 ether); // juror1 only has 500 staked
    }

    function testPhase2NoRedistribution() public {
        // This test verifies that Phase 2 does NOT redistribute stakes
        // (Phase 3 will add that feature)

        uint256 id = kleros.createDispute("ipfs://QmExample5");
        kleros.drawJurors(id);
        address[] memory jurors = kleros.getJurors(id);

        // Record initial stakes
        uint256[] memory initialStakes = new uint256[](3);
        for (uint256 i = 0; i < 3; i++) {
            (initialStakes[i],) = kleros.getJurorStake(jurors[i]);
        }

        // Complete dispute with clear winner
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

        // Majority votes Option1, minority votes Option2
        vm.prank(bigJuror);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), salt0)));
        vm.prank(medJuror);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), salt1)));
        vm.prank(smallJuror);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(2), salt2)));

        vm.warp(block.timestamp + 2 hours);

        vm.prank(bigJuror);
        kleros.revealVote(id, 1, salt0);
        vm.prank(medJuror);
        kleros.revealVote(id, 1, salt1);
        vm.prank(smallJuror);
        kleros.revealVote(id, 2, salt2);

        vm.warp(block.timestamp + 2 hours);
        kleros.finalize(id);

        // PHASE 2: Stakes should remain UNCHANGED (no redistribution)
        for (uint256 i = 0; i < 3; i++) {
            (uint256 finalStake,) = kleros.getJurorStake(jurors[i]);
            assertEq(finalStake, initialStakes[i], "stakes should not change in Phase 2");
        }
    }
}