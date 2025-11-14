// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/TestToken.sol";
import "../src/SimpleKlerosPhase1.sol";

contract SimpleKlerosPhase1Test is Test {
    TestToken token;
    SimpleKlerosPhase1 kleros;

    address juror1 = address(0x1);
    address juror2 = address(0x2);
    address juror3 = address(0x3);

    function setUp() public {
        // Deploy test token with large supply
        token = new TestToken(1_000_000 ether);

        // Fund jurors with DIFFERENT balances to test weighted voting
        token.transfer(juror1, 500 ether);  // juror1 has 500 tokens (50% weight)
        token.transfer(juror2, 300 ether);  // juror2 has 300 tokens (30% weight)
        token.transfer(juror3, 200 ether);  // juror3 has 200 tokens (20% weight)

        // Deploy SimpleKlerosPhase1
        kleros = new SimpleKlerosPhase1(
            IERC20(address(token)),
            100 ether,  // minBalance
            3,          // jurorsPerDispute
            1 hours,    // commitDuration
            1 hours     // revealDuration
        );

        // Jurors register (NO staking in Phase 1, just registration)
        vm.prank(juror1);
        kleros.registerAsJuror();

        vm.prank(juror2);
        kleros.registerAsJuror();

        vm.prank(juror3);
        kleros.registerAsJuror();
    }

    function testPhase1TokenWeightedVoting() public {
        // 1. Create dispute
        uint256 id = kleros.createDispute("ipfs://QmExample");

        // 2. Select jurors
        kleros.selectJurors(id);
        address[] memory jurors = kleros.getJurors(id);
        assertEq(jurors.length, 3, "must have 3 jurors");

        // 3. Prepare salts
        bytes32 salt0 = keccak256("salt0");
        bytes32 salt1 = keccak256("salt1");
        bytes32 salt2 = keccak256("salt2");

        // Find which juror is which based on balance
        address bigJuror;    // 500 tokens
        address medJuror;    // 300 tokens
        address smallJuror;  // 200 tokens

        for (uint256 i = 0; i < 3; i++) {
            uint256 bal = token.balanceOf(jurors[i]);
            if (bal == 500 ether) bigJuror = jurors[i];
            else if (bal == 300 ether) medJuror = jurors[i];
            else if (bal == 200 ether) smallJuror = jurors[i];
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

        // Verify weights are correct
        (bool revealed1, uint8 vote1, uint256 weight1) = kleros.getJurorVote(id, bigJuror);
        assertTrue(revealed1, "bigJuror should have revealed");
        assertEq(weight1, 500 ether, "bigJuror weight wrong");
        assertEq(vote1, 2, "bigJuror vote wrong");

        (bool revealed2, uint8 vote2, uint256 weight2) = kleros.getJurorVote(id, medJuror);
        assertTrue(revealed2, "medJuror should have revealed");
        assertEq(weight2, 300 ether, "medJuror weight wrong");
        assertEq(vote2, 1, "medJuror vote wrong");

        // Move beyond revealDeadline, then finalize
        vm.warp(block.timestamp + 2 hours);
        kleros.finalize(id);

        // Check final results
        (, SimpleKlerosPhase1.Ruling ruling, uint256 v1, uint256 v2) = kleros.getDisputeSummary(id);

        // Option1: 300 + 200 = 500
        // Option2: 500
        // Should be Undecided (tie)
        assertEq(uint256(ruling), uint256(SimpleKlerosPhase1.Ruling.Undecided), "should be tie");
        assertEq(v1, 500 ether, "Option1 weighted votes should be 500");
        assertEq(v2, 500 ether, "Option2 weighted votes should be 500");
    }

    function testPhase1MajorityWins() public {
        // Create dispute
        uint256 id = kleros.createDispute("ipfs://QmExample2");
        kleros.selectJurors(id);
        address[] memory jurors = kleros.getJurors(id);

        bytes32 salt0 = keccak256("salt0");
        bytes32 salt1 = keccak256("salt1");
        bytes32 salt2 = keccak256("salt2");

        // Find jurors by balance
        address bigJuror;
        address medJuror;
        address smallJuror;

        for (uint256 i = 0; i < 3; i++) {
            uint256 bal = token.balanceOf(jurors[i]);
            if (bal == 500 ether) bigJuror = jurors[i];
            else if (bal == 300 ether) medJuror = jurors[i];
            else if (bal == 200 ether) smallJuror = jurors[i];
        }

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

        // Check results separately to avoid stack issues
        (, SimpleKlerosPhase1.Ruling ruling,,) = kleros.getDisputeSummary(id);
        assertEq(uint256(ruling), uint256(SimpleKlerosPhase1.Ruling.Option1), "Option1 should win");

        (,, uint256 v1, uint256 v2) = kleros.getDisputeSummary(id);
        assertEq(v1, 800 ether, "Option1 weighted votes");
        assertEq(v2, 200 ether, "Option2 weighted votes");
    }

    function testCannotVoteWithoutSufficientBalance() public {
        // Create a new juror with insufficient balance
        address poorJuror = address(0x99);
        token.transfer(poorJuror, 50 ether); // Below minBalance of 100

        vm.prank(poorJuror);
        vm.expectRevert("insufficient balance");
        kleros.registerAsJuror();
    }

    function testCannotDoubleCommit() public {
        uint256 id = kleros.createDispute("ipfs://QmExample3");
        kleros.selectJurors(id);
        address[] memory jurors = kleros.getJurors(id);

        bytes32 commit = keccak256(abi.encodePacked(uint8(1), keccak256("salt")));

        vm.startPrank(jurors[0]);
        kleros.commitVote(id, commit);
        
        vm.expectRevert("already committed");
        kleros.commitVote(id, commit);
        vm.stopPrank();
    }

    function testCannotRevealWithWrongSalt() public {
        uint256 id = kleros.createDispute("ipfs://QmExample4");
        kleros.selectJurors(id);
        address[] memory jurors = kleros.getJurors(id);

        bytes32 correctSalt = keccak256("correct");
        bytes32 wrongSalt = keccak256("wrong");

        // Commit with correct salt
        vm.prank(jurors[0]);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), correctSalt)));

        vm.warp(block.timestamp + 2 hours);

        // Try to reveal with wrong salt
        vm.prank(jurors[0]);
        vm.expectRevert("bad reveal");
        kleros.revealVote(id, 1, wrongSalt);
    }

    function testCommitRevealSecrecy() public {
        // This test demonstrates that commits are hidden until reveal
        uint256 id = kleros.createDispute("ipfs://QmExample5");
        kleros.selectJurors(id);
        address[] memory jurors = kleros.getJurors(id);

        bytes32 salt = keccak256("secret");
        
        // Juror commits
        vm.prank(jurors[0]);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), salt)));

        // Before reveal, vote should not be visible
        (bool revealed, uint8 vote, uint256 weight) = kleros.getJurorVote(id, jurors[0]);
        assertFalse(revealed, "should not be revealed yet");
        assertEq(vote, 0, "vote should be 0 before reveal");
        assertEq(weight, 0, "weight should be 0 before reveal");

        // After reveal, vote becomes visible
        vm.warp(block.timestamp + 2 hours);
        vm.prank(jurors[0]);
        kleros.revealVote(id, 1, salt);

        (revealed, vote, weight) = kleros.getJurorVote(id, jurors[0]);
        assertTrue(revealed, "should be revealed now");
        assertEq(vote, 1, "vote should be 1");
        assertTrue(weight > 0, "weight should be > 0");
    }
}