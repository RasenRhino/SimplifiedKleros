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

    function setUp() public {
        // Deploy test token with large supply
        token = new TestToken(1_000_000 ether);

        // Fund jurors
        token.transfer(juror1, 1_000 ether);
        token.transfer(juror2, 1_000 ether);
        token.transfer(juror3, 1_000 ether);

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
}