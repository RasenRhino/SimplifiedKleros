// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/TestToken.sol";
import "../src/SimpleKleros.sol";

contract SimpleKlerosTest is Test {
    TestToken token;
    SimpleKleros kleros;

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

        // Deploy SimpleKleros
        kleros = new SimpleKleros(
            IERC20(address(token)),
            100 ether,  // minStake
            3,          // jurorsPerDispute
            1 hours,    // commitDuration
            1 hours     // revealDuration
        );

        // Jurors stake
        vm.startPrank(juror1);
        token.approve(address(kleros), type(uint256).max);
        kleros.stake(200 ether);
        vm.stopPrank();

        vm.startPrank(juror2);
        token.approve(address(kleros), type(uint256).max);
        kleros.stake(200 ether);
        vm.stopPrank();

        vm.startPrank(juror3);
        token.approve(address(kleros), type(uint256).max);
        kleros.stake(200 ether);
        vm.stopPrank();
    }

    function testCreateDisputeAndCommitReveal() public {
        // 1. Create dispute
        uint256 id = kleros.createDispute("ipfs://QmExample");

        // 2. Draw jurors
        kleros.drawJurors(id);
        address[] memory jurors = kleros.getJurors(id);
        assertEq(jurors.length, 3, "must have 3 jurors");

        // 3. Prepare salts
        bytes32 salt0 = keccak256("salt0");
        bytes32 salt1 = keccak256("salt1");
        bytes32 salt2 = keccak256("salt2");

        // We'll make:
        // - jurors[0] vote Option1
        // - jurors[1] vote Option1
        // - jurors[2] vote Option2

        // --- COMMIT PHASE ---
        vm.startPrank(jurors[0]);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), salt0)));
        vm.stopPrank();

        vm.startPrank(jurors[1]);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), salt1)));
        vm.stopPrank();

        vm.startPrank(jurors[2]);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(2), salt2)));
        vm.stopPrank();

        // Move into reveal phase (after commitDeadline)
        vm.warp(block.timestamp + 2 hours);

        // --- REVEAL PHASE ---
        vm.startPrank(jurors[0]);
        kleros.revealVote(id, 1, salt0);
        vm.stopPrank();

        vm.startPrank(jurors[1]);
        kleros.revealVote(id, 1, salt1);
        vm.stopPrank();

        vm.startPrank(jurors[2]);
        kleros.revealVote(id, 2, salt2);
        vm.stopPrank();

        // Move beyond revealDeadline, then finalize
        vm.warp(block.timestamp + 2 hours);
        kleros.finalize(id);

        (
            SimpleKleros.Phase phase,
            SimpleKleros.Ruling ruling,
            uint256 v1,
            uint256 v2
        ) = kleros.getDisputeSummary(id);

        assertEq(uint256(phase), uint256(SimpleKleros.Phase.Resolved), "wrong phase");
        assertEq(uint256(ruling), uint256(SimpleKleros.Ruling.Option1), "wrong ruling");
        assertEq(v1, 2, "Option1 votes should be 2");
        assertEq(v2, 1, "Option2 votes should be 1");
    }
}
