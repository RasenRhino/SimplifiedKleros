// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "../src/TestToken.sol";
import "../src/SimpleKlerosPhase3.sol";

contract SimpleKlerosPhase3Test is Test {
    TestToken token;
    SimpleKlerosPhase3 kleros;

    address juror1 = address(0x1);
    address juror2 = address(0x2);
    address juror3 = address(0x3);
    address nonJuror = address(0x99);

    uint256 constant TOKEN_UNIT = 1e18; // 1 token = 1e18 wei units

    // ==========================
    // Formatting / logging utils
    // ==========================

    function _toTokens(uint256 weiAmount) internal pure returns (uint256) {
        // Presentation: show whole tokens instead of raw wei
        return weiAmount / TOKEN_UNIT;
    }

    function _phaseToString(SimpleKlerosPhase3.Phase phase)
        internal
        pure
        returns (string memory)
    {
        if (phase == SimpleKlerosPhase3.Phase.None) return "None";
        if (phase == SimpleKlerosPhase3.Phase.Created) return "Created";
        if (phase == SimpleKlerosPhase3.Phase.JurorsDrawn) return "JurorsDrawn";
        if (phase == SimpleKlerosPhase3.Phase.Commit) return "Commit";
        if (phase == SimpleKlerosPhase3.Phase.Reveal) return "Reveal";
        if (phase == SimpleKlerosPhase3.Phase.Resolved) return "Resolved";
        return "Unknown";
    }

    function _rulingToString(SimpleKlerosPhase3.Ruling ruling)
        internal
        pure
        returns (string memory)
    {
        if (ruling == SimpleKlerosPhase3.Ruling.Undecided) return "Undecided";
        if (ruling == SimpleKlerosPhase3.Ruling.Option1) return "Option1";
        if (ruling == SimpleKlerosPhase3.Ruling.Option2) return "Option2";
        return "Unknown";
    }

    function _scenarioHeader(string memory title, string memory description) internal {
        emit log("");
        emit log("============================================================");
        emit log(title);
        emit log("------------------------------------------------------------");
        emit log(description);
        emit log("============================================================");
        emit log("");
    }

    function _step(string memory description) internal {
        emit log(string(abi.encodePacked("STEP: ", description)));
    }

    function _logJurorStake(string memory labelName, address juror) internal {
        (uint256 stakeAmt, bool locked) = kleros.getJurorStake(juror);
        emit log_named_address(string(abi.encodePacked(labelName, " addr")), juror);
        emit log_named_uint(
            string(abi.encodePacked(labelName, " stake (tokens)")),
            _toTokens(stakeAmt)
        );
        emit log_named_uint(
            string(abi.encodePacked(labelName, " locked (0/1)")),
            locked ? 1 : 0
        );
    }

    function _logJurorPanel(address[] memory jurors) internal {
        emit log("");
        emit log("--------- Current Juror Panel (addresses, stake, lock) ---------");
        for (uint256 i = 0; i < jurors.length; i++) {
            (uint256 stakeAmt, bool locked) = kleros.getJurorStake(jurors[i]);
            emit log_named_uint("jurorIndex", i);
            emit log_named_address("juror addr", jurors[i]);
            emit log_named_uint("stake (tokens)", _toTokens(stakeAmt));
            emit log_named_uint("locked (0/1)", locked ? 1 : 0);
        }
        emit log("----------------------------------------------------------------");
        emit log("");
    }

    /// @dev Identify which address has 500 / 300 / 200 tokens staked
    function _classifyJurorsByStake(address[] memory jurors)
        internal
        returns (address bigJuror, address medJuror, address smallJuror)
    {
        emit log("Classifying jurors by stake (big=500, med=300, small=200 tokens)");
        for (uint256 i = 0; i < jurors.length; i++) {
            (uint256 stakeAmt,) = kleros.getJurorStake(jurors[i]);
            emit log_named_address("candidate juror", jurors[i]);
            emit log_named_uint("candidate stake (tokens)", _toTokens(stakeAmt));

            if (stakeAmt == 500 ether) {
                bigJuror = jurors[i];
                console2.log("-> identified bigJuror (500 tokens)");
            } else if (stakeAmt == 300 ether) {
                medJuror = jurors[i];
                console2.log("-> identified medJuror (300 tokens)");
            } else if (stakeAmt == 200 ether) {
                smallJuror = jurors[i];
                console2.log("-> identified smallJuror (200 tokens)");
            }
        }

        emit log_named_address("bigJuror", bigJuror);
        emit log_named_address("medJuror", medJuror);
        emit log_named_address("smallJuror", smallJuror);
    }

    /// @dev Human-readable summary of a completed dispute, including per-juror outcomes.
    function _logDisputeSummary(uint256 id) internal {
        (
            SimpleKlerosPhase3.Phase phase,
            SimpleKlerosPhase3.Ruling ruling,
            uint256 v1,
            uint256 v2
        ) = kleros.getDisputeSummary(id);

        address[] memory jurors = kleros.getJurors(id);

        emit log("");
        emit log("------------------------------------------------------------");
        emit log("               Human-readable Dispute Summary               ");
        emit log("------------------------------------------------------------");

        emit log_named_uint("Dispute ID", id);
        emit log_named_string("Final phase", _phaseToString(phase));
        emit log_named_string("Final ruling", _rulingToString(ruling));
        emit log_named_uint(
            "Total voting weight for Option1 (tokens)",
            _toTokens(v1)
        );
        emit log_named_uint(
            "Total voting weight for Option2 (tokens)",
            _toTokens(v2)
        );

        emit log("");
        emit log("Per-juror breakdown (stake snapshot, final stake, vote, outcome):");

        uint8 winningVote = 0;
        if (ruling == SimpleKlerosPhase3.Ruling.Option1) {
            winningVote = 1;
        } else if (ruling == SimpleKlerosPhase3.Ruling.Option2) {
            winningVote = 2;
        }

        for (uint256 i = 0; i < jurors.length; i++) {
            address juror = jurors[i];

            // Snapshot voting weight and vote info
            (bool revealed, uint8 vote, uint256 snapshotWeightWei) =
                kleros.getJurorVote(id, juror);

            // Final stake after redistribution
            (uint256 finalStakeWei, bool locked) = kleros.getJurorStake(juror);

            string memory voteStr;
            if (!revealed) {
                voteStr = "did NOT reveal (treated as loser)";
            } else if (vote == 1) {
                voteStr = "Option1";
            } else if (vote == 2) {
                voteStr = "Option2";
            } else {
                voteStr = "invalid vote value";
            }

            string memory outcome;
            if (ruling == SimpleKlerosPhase3.Ruling.Undecided) {
                outcome = "no redistribution (tie / undecided)";
            } else if (!revealed) {
                outcome = "loser (did not reveal, stake may be fully slashed)";
            } else if (vote == winningVote) {
                outcome = "winner (voted with the majority and receives stake)";
            } else {
                outcome = "loser (voted against the majority and may be slashed)";
            }

            emit log("");
            emit log_named_uint("Juror index", i);
            emit log_named_address("Juror address", juror);
            emit log_named_uint(
                "Voting weight at selection (tokens)",
                _toTokens(snapshotWeightWei)
            );
            emit log_named_uint(
                "Final stake after dispute (tokens)",
                _toTokens(finalStakeWei)
            );
            emit log_named_uint(
                "Still locked? (0 = no, 1 = yes)",
                locked ? 1 : 0
            );
            emit log_named_uint(
                "Revealed vote? (0 = no, 1 = yes)",
                revealed ? 1 : 0
            );
            emit log_named_string("Vote", voteStr);
            emit log_named_string("Outcome for this juror", outcome);
        }

        emit log("------------------------------------------------------------");
        emit log("");
    }

    // ==========
    // setUp
    // ==========

    function setUp() public {
        _scenarioHeader(
            "Bootstrap Environment",
            "Deploy test ERC20, deploy Kleros Phase 3, and stake three jurors "
            "with different weights (500, 300, 200 tokens)."
        );

        vm.label(juror1, "juror1");
        vm.label(juror2, "juror2");
        vm.label(juror3, "juror3");
        vm.label(nonJuror, "nonJuror");

        _step("Deploy TestToken and fund all participants");
        token = new TestToken(1_000_000 ether);
        vm.label(address(token), "TestToken");

        token.transfer(juror1, 1_000 ether);
        token.transfer(juror2, 1_000 ether);
        token.transfer(juror3, 1_000 ether);
        token.transfer(nonJuror, 1_000 ether);

        emit log_named_uint("totalSupply (tokens)", _toTokens(token.totalSupply()));
        emit log_named_uint("juror1 balance (tokens)", _toTokens(token.balanceOf(juror1)));
        emit log_named_uint("juror2 balance (tokens)", _toTokens(token.balanceOf(juror2)));
        emit log_named_uint("juror3 balance (tokens)", _toTokens(token.balanceOf(juror3)));
        emit log_named_uint("nonJuror balance (tokens)", _toTokens(token.balanceOf(nonJuror)));

        _step("Deploy SimpleKlerosPhase3 with 3 jurors per dispute and 100-token min stake");
        kleros = new SimpleKlerosPhase3(
            IERC20(address(token)),
            100 ether, // minStake
            3,         // jurorsPerDispute
            1 hours,   // commitDuration
            1 hours    // revealDuration
        );
        vm.label(address(kleros), "SimpleKlerosPhase3");

        emit log_named_uint("minStake (tokens)", _toTokens(kleros.minStake()));
        emit log_named_uint("jurorsPerDispute", kleros.jurorsPerDispute());

        _step("Stake juror1=500, juror2=300, juror3=200 tokens");
        vm.startPrank(juror1);
        token.approve(address(kleros), type(uint256).max);
        kleros.stake(500 ether);
        vm.stopPrank();

        vm.startPrank(juror2);
        token.approve(address(kleros), type(uint256).max);
        kleros.stake(300 ether);
        vm.stopPrank();

        vm.startPrank(juror3);
        token.approve(address(kleros), type(uint256).max);
        kleros.stake(200 ether);
        vm.stopPrank();

        emit log("Initial juror stakes (tokens):");
        _logJurorStake("juror1", juror1);
        _logJurorStake("juror2", juror2);
        _logJurorStake("juror3", juror3);
    }

    // ============================================
    // Core Phase 3 behaviour (redistribution, etc.)
    // ============================================

    function testPhase3MajorityWinsAndGetsReward() public {
        _scenarioHeader(
            "Majority Wins and Receives Slashed Stake",
            "Big (500) and medium (300) jurors vote together and defeat small (200). "
            "Small is fully slashed; winners are rewarded proportionally."
        );

        _step("Create a dispute and draw 3 jurors");
        uint256 id = kleros.createDispute("ipfs://QmExample");
        emit log_named_uint("created dispute id", id);

        kleros.drawJurors(id);
        address[] memory jurors = kleros.getJurors(id);
        _logJurorPanel(jurors);

        bytes32 salt0 = keccak256("salt0");
        bytes32 salt1 = keccak256("salt1");
        bytes32 salt2 = keccak256("salt2");

        (address bigJuror, address medJuror, address smallJuror) =
            _classifyJurorsByStake(jurors);

        (uint256 bigInitialWei,) = kleros.getJurorStake(bigJuror);
        (uint256 medInitialWei,) = kleros.getJurorStake(medJuror);
        (uint256 smallInitialWei,) = kleros.getJurorStake(smallJuror);

        emit log("Initial stakes before dispute (tokens):");
        emit log_named_uint("bigInitial", _toTokens(bigInitialWei));
        emit log_named_uint("medInitial", _toTokens(medInitialWei));
        emit log_named_uint("smallInitial", _toTokens(smallInitialWei));

        _step("Commit votes: big+med vote Option1, small votes Option2");
        vm.prank(bigJuror);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), salt0)));
        vm.prank(medJuror);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), salt1)));
        vm.prank(smallJuror);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(2), salt2)));

        vm.warp(block.timestamp + 90 minutes);

        _step("Reveal all votes");
        vm.prank(bigJuror);
        kleros.revealVote(id, 1, salt0);
        vm.prank(medJuror);
        kleros.revealVote(id, 1, salt1);
        vm.prank(smallJuror);
        kleros.revealVote(id, 2, salt2);

        vm.warp(block.timestamp + 1 hours);

        _step("Finalize dispute and trigger stake redistribution");
        kleros.finalize(id);

        _logDisputeSummary(id);

        (, SimpleKlerosPhase3.Ruling ruling,,) = kleros.getDisputeSummary(id);
        assertEq(uint256(ruling), uint256(SimpleKlerosPhase3.Ruling.Option1), "Option1 should win");

        (uint256 bigFinalWei,) = kleros.getJurorStake(bigJuror);
        (uint256 medFinalWei,) = kleros.getJurorStake(medJuror);
        (uint256 smallFinalWei,) = kleros.getJurorStake(smallJuror);

        emit log("Final stakes after dispute (tokens):");
        emit log_named_uint("bigFinal", _toTokens(bigFinalWei));
        emit log_named_uint("medFinal", _toTokens(medFinalWei));
        emit log_named_uint("smallFinal", _toTokens(smallFinalWei));

        uint256 totalInitialWei = bigInitialWei + medInitialWei + smallInitialWei;
        uint256 totalFinalWei = bigFinalWei + medFinalWei + smallFinalWei;
        emit log_named_uint("totalInitial (tokens)", _toTokens(totalInitialWei));
        emit log_named_uint("totalFinal (tokens)", _toTokens(totalFinalWei));

        assertEq(smallFinalWei, 0, "loser (small) should have 0 stake");
        assertGt(bigFinalWei, bigInitialWei, "big winner should gain");
        assertGt(medFinalWei, medInitialWei, "med winner should gain");
        assertEq(totalFinalWei, totalInitialWei, "total stake should be conserved");
        assertEq(bigFinalWei, 625 ether, "bigFinal exact (500 + 125)");
        assertEq(medFinalWei, 375 ether, "medFinal exact (300 + 75)");
    }

    function testPhase3NonRevealerLosesEverything() public {
        _scenarioHeader(
            "Non-Revealer Loses Stake",
            "All jurors commit to the same option, but one never reveals. "
            "The non-revealer is treated as a loser and fully slashed."
        );

        _step("Create dispute and draw jurors");
        uint256 id = kleros.createDispute("ipfs://QmExample3");
        emit log_named_uint("created dispute id", id);

        kleros.drawJurors(id);
        address[] memory jurors = kleros.getJurors(id);
        _logJurorPanel(jurors);

        bytes32 salt0 = keccak256("salt0");
        bytes32 salt1 = keccak256("salt1");

        (address bigJuror, address medJuror, address smallJuror) =
            _classifyJurorsByStake(jurors);

        emit log("All commit Option1, but smallJuror will not reveal later");
        vm.prank(bigJuror);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), salt0)));
        vm.prank(medJuror);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), salt1)));
        vm.prank(smallJuror);
        kleros.commitVote(
            id,
            keccak256(abi.encodePacked(uint8(1), keccak256("salt2")))
        );

        vm.warp(block.timestamp + 90 minutes);

        _step("Only big and med reveal; small stays silent");
        vm.prank(bigJuror);
        kleros.revealVote(id, 1, salt0);
        vm.prank(medJuror);
        kleros.revealVote(id, 1, salt1);
        // smallJuror never reveals

        vm.warp(block.timestamp + 1 hours);
        kleros.finalize(id);

        _logDisputeSummary(id);

        (uint256 smallFinalWei,) = kleros.getJurorStake(smallJuror);
        emit log_named_uint("smallFinal (tokens)", _toTokens(smallFinalWei));
        assertEq(smallFinalWei, 0, "non-revealer should lose all stake");

        (uint256 bigFinalWei,) = kleros.getJurorStake(bigJuror);
        (uint256 medFinalWei,) = kleros.getJurorStake(medJuror);
        emit log_named_uint("bigFinal (tokens)", _toTokens(bigFinalWei));
        emit log_named_uint("medFinal (tokens)", _toTokens(medFinalWei));

        assertGt(bigFinalWei, 500 ether, "big juror gains");
        assertGt(medFinalWei, 300 ether, "med juror gains");
    }

    function testPhase3ProportionalRewardDistribution() public {
        _scenarioHeader(
            "Rewards Are Proportional to Voting Weight",
            "The loser (200 tokens) is slashed and the winners (500 and 300 tokens) "
            "share the slashed stake proportionally to their snapshot weight."
        );

        _step("Create dispute, draw jurors, and show panel");
        uint256 id = kleros.createDispute("ipfs://QmExample4");
        emit log_named_uint("created dispute id", id);

        kleros.drawJurors(id);
        address[] memory jurors = kleros.getJurors(id);
        _logJurorPanel(jurors);

        bytes32 salt0 = keccak256("salt0");
        bytes32 salt1 = keccak256("salt1");
        bytes32 salt2 = keccak256("salt2");

        (address bigJuror, address medJuror, address smallJuror) =
            _classifyJurorsByStake(jurors);

        _step("Commit: big+med vote Option1, small votes Option2");
        vm.prank(bigJuror);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), salt0)));
        vm.prank(medJuror);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), salt1)));
        vm.prank(smallJuror);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(2), salt2)));

        vm.warp(block.timestamp + 90 minutes);

        _step("Reveal all votes and finalize");
        vm.prank(bigJuror);
        kleros.revealVote(id, 1, salt0);
        vm.prank(medJuror);
        kleros.revealVote(id, 1, salt1);
        vm.prank(smallJuror);
        kleros.revealVote(id, 2, salt2);

        vm.warp(block.timestamp + 1 hours);
        kleros.finalize(id);

        _logDisputeSummary(id);

        (uint256 bigFinalWei,) = kleros.getJurorStake(bigJuror);
        (uint256 medFinalWei,) = kleros.getJurorStake(medJuror);

        uint256 bigRewardWei = bigFinalWei - 500 ether;
        uint256 medRewardWei = medFinalWei - 300 ether;

        emit log_named_uint("bigReward (tokens)", _toTokens(bigRewardWei));
        emit log_named_uint("medReward (tokens)", _toTokens(medRewardWei));

        assertEq(bigRewardWei, 125 ether, "big reward exact");
        assertEq(medRewardWei, 75 ether, "med reward exact");
        assertEq(bigRewardWei * 3, medRewardWei * 5, "rewards proportional 5:3");
    }

    function testPhase3AllLoseIfAllMinority() public {
        _scenarioHeader(
            "Tie: No Redistribution, Ruling Undecided",
            "Weights for Option1 and Option2 are equal (500 vs 500). "
            "The system declares the ruling 'Undecided' and no stake is redistributed."
        );

        _step("Create dispute and draw jurors");
        uint256 id = kleros.createDispute("ipfs://QmExample5");
        emit log_named_uint("created dispute id", id);

        kleros.drawJurors(id);
        address[] memory jurors = kleros.getJurors(id);
        _logJurorPanel(jurors);

        bytes32 salt0 = keccak256("salt0");
        bytes32 salt1 = keccak256("salt1");
        bytes32 salt2 = keccak256("salt2");

        (address bigJuror, address medJuror, address smallJuror) =
            _classifyJurorsByStake(jurors);

        _step("Commit: big->Option1 (500), med+small->Option2 (300+200)");
        vm.prank(bigJuror);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), salt0)));
        vm.prank(medJuror);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(2), salt1)));
        vm.prank(smallJuror);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(2), salt2)));

        vm.warp(block.timestamp + 90 minutes);

        _step("Reveal all votes and finalize");
        vm.prank(bigJuror);
        kleros.revealVote(id, 1, salt0);
        vm.prank(medJuror);
        kleros.revealVote(id, 2, salt1);
        vm.prank(smallJuror);
        kleros.revealVote(id, 2, salt2);

        vm.warp(block.timestamp + 1 hours);
        kleros.finalize(id);

        _logDisputeSummary(id);

        (, SimpleKlerosPhase3.Ruling ruling,,) = kleros.getDisputeSummary(id);
        assertEq(uint256(ruling), uint256(SimpleKlerosPhase3.Ruling.Undecided), "should be tie");
    }

    function testPhase3CanUnstakeAfterWinning() public {
        _scenarioHeader(
            "Winner Can Unstake Rewards After Dispute",
            "After winning and receiving rewards, a juror can unstake some tokens "
            "and withdraw them as liquid balance."
        );

        _step("Create dispute, draw jurors and show panel");
        uint256 id = kleros.createDispute("ipfs://QmExample6");
        emit log_named_uint("created dispute id", id);

        kleros.drawJurors(id);
        address[] memory jurors = kleros.getJurors(id);
        _logJurorPanel(jurors);

        bytes32 salt0 = keccak256("salt0");
        bytes32 salt1 = keccak256("salt1");
        bytes32 salt2 = keccak256("salt2");

        (address bigJuror, address medJuror, address smallJuror) =
            _classifyJurorsByStake(jurors);

        _step("Commit: big+med vote Option1, small votes Option2");
        vm.prank(bigJuror);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), salt0)));
        vm.prank(medJuror);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), salt1)));
        vm.prank(smallJuror);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(2), salt2)));

        vm.warp(block.timestamp + 90 minutes);

        _step("Reveal all votes and finalize");
        vm.prank(bigJuror);
        kleros.revealVote(id, 1, salt0);
        vm.prank(medJuror);
        kleros.revealVote(id, 1, salt1);
        vm.prank(smallJuror);
        kleros.revealVote(id, 2, salt2);

        vm.warp(block.timestamp + 1 hours);
        kleros.finalize(id);

        _logDisputeSummary(id);

        (uint256 bigFinalWei,) = kleros.getJurorStake(bigJuror);
        emit log_named_uint("bigFinal (tokens)", _toTokens(bigFinalWei));
        assertEq(bigFinalWei, 625 ether, "big gained 125 tokens");

        _step("Winner unstake 125 tokens (the reward) and check balances");
        uint256 balanceBefore = token.balanceOf(bigJuror);
        emit log_named_uint("big balanceBefore (tokens)", _toTokens(balanceBefore));

        vm.prank(bigJuror);
        kleros.unstake(125 ether);

        uint256 balanceAfter = token.balanceOf(bigJuror);
        emit log_named_uint("big balanceAfter (tokens)", _toTokens(balanceAfter));

        assertEq(balanceAfter - balanceBefore, 125 ether, "received 125 tokens");
        (uint256 stakeAfterWei,) = kleros.getJurorStake(bigJuror);
        emit log_named_uint("stakeAfter (tokens)", _toTokens(stakeAfterWei));
        assertEq(stakeAfterWei, 500 ether, "back to original 500 stake");
    }

    // ============================================
    // Security / access control tests
    // ============================================

    function testCannotCommitTwice() public {
        _scenarioHeader(
            "Double Commit Forbidden",
            "A juror who has already committed a vote cannot commit again for the same dispute."
        );

        uint256 id = kleros.createDispute("ipfs://QmDoubleCommit");
        kleros.drawJurors(id);
        address[] memory jurors = kleros.getJurors(id);

        bytes32 salt = keccak256("salt");
        bytes32 commitHash = keccak256(abi.encodePacked(uint8(1), salt));

        _step("First commit succeeds");
        vm.prank(jurors[0]);
        kleros.commitVote(id, commitHash);

        _step("Second commit from same juror must revert with 'already committed'");
        vm.prank(jurors[0]);
        vm.expectRevert("already committed");
        kleros.commitVote(id, commitHash);
    }

    function testNonJurorCannotCommit() public {
        _scenarioHeader(
            "Non-Juror Cannot Commit",
            "An address that was not selected as juror cannot participate in commit."
        );

        uint256 id = kleros.createDispute("ipfs://QmNonJuror");
        kleros.drawJurors(id);

        bytes32 salt = keccak256("salt");
        bytes32 commitHash = keccak256(abi.encodePacked(uint8(1), salt));

        _step("nonJuror attempts to commit and should revert");
        vm.prank(nonJuror);
        vm.expectRevert("not a juror");
        kleros.commitVote(id, commitHash);
    }

    function testNonJurorCannotReveal() public {
        _scenarioHeader(
            "Non-Juror Cannot Reveal",
            "Only selected jurors can reveal; non-jurors are rejected."
        );

        uint256 id = kleros.createDispute("ipfs://QmNonJurorReveal");
        kleros.drawJurors(id);
        address[] memory jurors = kleros.getJurors(id);

        bytes32 salt = keccak256("salt");

        _step("All jurors commit a vote");
        for (uint256 i = 0; i < jurors.length; i++) {
            vm.prank(jurors[i]);
            kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), salt)));
        }

        vm.warp(block.timestamp + 90 minutes);

        _step("nonJuror tries to reveal and must revert");
        vm.prank(nonJuror);
        vm.expectRevert("not a juror");
        kleros.revealVote(id, 1, salt);
    }

    function testCannotRevealWithWrongSalt() public {
        _scenarioHeader(
            "Reveal Fails with Wrong Salt",
            "Commitment binding: revealing with a different salt than used in commit causes revert."
        );

        uint256 id = kleros.createDispute("ipfs://QmWrongSalt");
        kleros.drawJurors(id);
        address[] memory jurors = kleros.getJurors(id);

        bytes32 correctSalt = keccak256("correctSalt");
        bytes32 wrongSalt = keccak256("wrongSalt");

        vm.prank(jurors[0]);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), correctSalt)));

        vm.warp(block.timestamp + 90 minutes);

        _step("Reveal with wrong salt must fail with 'bad reveal'");
        vm.prank(jurors[0]);
        vm.expectRevert("bad reveal");
        kleros.revealVote(id, 1, wrongSalt);
    }

    function testCannotRevealWithWrongVote() public {
        _scenarioHeader(
            "Reveal Fails with Wrong Vote",
            "Commitment binding: revealing with a different vote than in the commit causes revert."
        );

        uint256 id = kleros.createDispute("ipfs://QmWrongVote");
        kleros.drawJurors(id);
        address[] memory jurors = kleros.getJurors(id);

        bytes32 salt = keccak256("salt");

        vm.prank(jurors[0]);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), salt)));

        vm.warp(block.timestamp + 90 minutes);

        _step("Reveal with vote=2 while commit was for vote=1 must fail");
        vm.prank(jurors[0]);
        vm.expectRevert("bad reveal");
        kleros.revealVote(id, 2, salt);
    }

    function testCannotRevealTwice() public {
        _scenarioHeader(
            "Double Reveal Forbidden",
            "A juror may reveal only once for each dispute."
        );

        uint256 id = kleros.createDispute("ipfs://QmDoubleReveal");
        kleros.drawJurors(id);
        address[] memory jurors = kleros.getJurors(id);

        bytes32 salt = keccak256("salt");

        vm.prank(jurors[0]);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), salt)));

        vm.warp(block.timestamp + 90 minutes);

        _step("First reveal succeeds");
        vm.prank(jurors[0]);
        kleros.revealVote(id, 1, salt);

        _step("Second reveal must revert with 'already revealed'");
        vm.prank(jurors[0]);
        vm.expectRevert("already revealed");
        kleros.revealVote(id, 1, salt);
    }

    function testCannotRevealInvalidVoteValue() public {
        _scenarioHeader(
            "Invalid Vote Values Rejected",
            "Only vote values 1 or 2 are accepted at reveal time."
        );

        uint256 id = kleros.createDispute("ipfs://QmInvalidVote");
        kleros.drawJurors(id);
        address[] memory jurors = kleros.getJurors(id);

        bytes32 salt = keccak256("salt");

        vm.prank(jurors[0]);
        // Commit uses '3' but that's irrelevant; reveal will check 'vote' param
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(3), salt)));

        vm.warp(block.timestamp + 90 minutes);

        _step("Reveal with vote=3 must revert with 'invalid vote'");
        vm.prank(jurors[0]);
        vm.expectRevert("invalid vote");
        kleros.revealVote(id, 3, salt);
    }

    // ============================================
    // Phase transition enforcement
    // ============================================

    function testCannotRevealBeforeCommitDeadline() public {
        _scenarioHeader(
            "Cannot Reveal Before Commit Phase Ends",
            "Reveal phase only starts after the commit deadline has passed."
        );

        uint256 id = kleros.createDispute("ipfs://QmEarlyReveal");
        kleros.drawJurors(id);
        address[] memory jurors = kleros.getJurors(id);

        bytes32 salt = keccak256("salt");

        _step("Commit a vote");
        vm.prank(jurors[0]);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), salt)));

        _step("Attempt to reveal immediately must revert with 'commit not finished'");
        vm.prank(jurors[0]);
        vm.expectRevert("commit not finished");
        kleros.revealVote(id, 1, salt);
    }

    function testCannotCommitAfterDeadline() public {
        _scenarioHeader(
            "Cannot Commit After Commit Deadline",
            "Once the commit window is closed, further commits are rejected."
        );

        uint256 id = kleros.createDispute("ipfs://QmLateCommit");
        kleros.drawJurors(id);
        address[] memory jurors = kleros.getJurors(id);

        bytes32 salt = keccak256("salt");

        vm.warp(block.timestamp + 2 hours);

        _step("Commit after deadline must revert with 'commit over'");
        vm.prank(jurors[0]);
        vm.expectRevert("commit over");
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), salt)));
    }

    function testCannotRevealAfterDeadline() public {
        _scenarioHeader(
            "Cannot Reveal After Reveal Deadline",
            "Reveal attempts after the reveal window are rejected."
        );

        uint256 id = kleros.createDispute("ipfs://QmLateReveal");
        kleros.drawJurors(id);
        address[] memory jurors = kleros.getJurors(id);

        bytes32 salt = keccak256("salt");

        _step("Commit within time");
        vm.prank(jurors[0]);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), salt)));

        vm.warp(block.timestamp + 3 hours);

        _step("Reveal after both commit and reveal windows must revert with 'reveal over'");
        vm.prank(jurors[0]);
        vm.expectRevert("reveal over");
        kleros.revealVote(id, 1, salt);
    }

    function testCannotFinalizeBeforeRevealDeadline() public {
        _scenarioHeader(
            "Cannot Finalize Before Reveal Deadline",
            "Even if all votes are revealed early, the contract enforces the full reveal period."
        );

        uint256 id = kleros.createDispute("ipfs://QmEarlyFinalize");
        kleros.drawJurors(id);
        address[] memory jurors = kleros.getJurors(id);

        bytes32 salt = keccak256("salt");

        _step("All jurors commit vote=1");
        for (uint256 i = 0; i < jurors.length; i++) {
            vm.prank(jurors[i]);
            kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), salt)));
        }

        vm.warp(block.timestamp + 90 minutes);

        _step("All jurors reveal early");
        for (uint256 i = 0; i < jurors.length; i++) {
            vm.prank(jurors[i]);
            kleros.revealVote(id, 1, salt);
        }

        _step("Attempt to finalize before reveal deadline must revert");
        vm.expectRevert("reveal not finished");
        kleros.finalize(id);
    }

    function testCannotDrawJurorsTwice() public {
        _scenarioHeader(
            "Cannot Draw Jurors Twice",
            "Once jurors have been drawn for a dispute, the phase changes and re-draw is disallowed."
        );

        uint256 id = kleros.createDispute("ipfs://QmDoubleDraw");
        _step("First draw succeeds");
        kleros.drawJurors(id);

        _step("Second draw must revert with 'wrong phase'");
        vm.expectRevert("wrong phase");
        kleros.drawJurors(id);
    }

    // ============================================
    // Staking mechanics
    // ============================================

    function testCannotUnstakeWhileLocked() public {
        _scenarioHeader(
            "Cannot Unstake While Selected as Juror",
            "A juror whose stake is locked in an active dispute cannot unstake."
        );

        uint256 id = kleros.createDispute("ipfs://QmLockedUnstake");
        kleros.drawJurors(id);
        address[] memory jurors = kleros.getJurors(id);

        _step("First juror tries to unstake while locked and must revert");
        vm.prank(jurors[0]);
        vm.expectRevert("stake locked");
        kleros.unstake(100 ether);
    }

    function testCannotStakeBelowMinimum() public {
        _scenarioHeader(
            "Cannot Stake Below Minimum",
            "New jurors must stake at least the configured minStake."
        );

        address newJuror = address(0x100);
        token.transfer(newJuror, 1000 ether);
        vm.label(newJuror, "newJurorBelowMin");

        _step("newJuror attempts to stake only 50 tokens (below 100 min)");
        vm.startPrank(newJuror);
        token.approve(address(kleros), type(uint256).max);
        vm.expectRevert("below minStake");
        kleros.stake(50 ether);
        vm.stopPrank();
    }

    function testCannotStakeZero() public {
        _scenarioHeader(
            "Cannot Stake Zero",
            "Staking 0 tokens is rejected."
        );

        vm.prank(juror1);
        vm.expectRevert("amount=0");
        kleros.stake(0);
    }

    function testCannotUnstakeMoreThanStaked() public {
        _scenarioHeader(
            "Cannot Unstake More Than Staked",
            "A juror cannot withdraw more than their total stake."
        );

        uint256 id = _completeDisputeWithOption1Winning();
        emit log_named_uint("helper dispute id", id);

        _logJurorStake("juror1 before over-unstake", juror1);

        _step("juror1 attempts to unstake 10,000 tokens and must revert");
        vm.prank(juror1);
        vm.expectRevert("not enough stake");
        kleros.unstake(10_000 ether);
    }

    // ============================================
    // Edge cases & behaviour
    // ============================================

    function testUnanimousVote() public {
        _scenarioHeader(
            "Unanimous Vote: No Slashing",
            "All jurors vote for the same option. No one is slashed; total stake remains constant."
        );

        uint256 id = kleros.createDispute("ipfs://QmUnanimous");
        kleros.drawJurors(id);
        address[] memory jurors = kleros.getJurors(id);

        _logJurorPanel(jurors);

        bytes32 salt0 = keccak256("salt0");
        bytes32 salt1 = keccak256("salt1");
        bytes32 salt2 = keccak256("salt2");

        uint256 totalInitialWei;
        for (uint256 i = 0; i < jurors.length; i++) {
            (uint256 stakeAmt,) = kleros.getJurorStake(jurors[i]);
            totalInitialWei += stakeAmt;
        }
        emit log_named_uint("totalInitial (tokens)", _toTokens(totalInitialWei));

        _step("All jurors commit Option1");
        vm.prank(jurors[0]);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), salt0)));
        vm.prank(jurors[1]);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), salt1)));
        vm.prank(jurors[2]);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), salt2)));

        vm.warp(block.timestamp + 90 minutes);

        _step("All jurors reveal Option1");
        vm.prank(jurors[0]);
        kleros.revealVote(id, 1, salt0);
        vm.prank(jurors[1]);
        kleros.revealVote(id, 1, salt1);
        vm.prank(jurors[2]);
        kleros.revealVote(id, 1, salt2);

        vm.warp(block.timestamp + 1 hours);
        kleros.finalize(id);

        _logDisputeSummary(id);

        uint256 totalFinalWei;
        for (uint256 i = 0; i < jurors.length; i++) {
            (uint256 stakeAmt,) = kleros.getJurorStake(jurors[i]);
            totalFinalWei += stakeAmt;
        }
        emit log_named_uint("totalFinal (tokens)", _toTokens(totalFinalWei));
        assertEq(totalFinalWei, totalInitialWei, "no slashing in unanimous");
    }

    function testSingleRevealerTakesAll() public {
        _scenarioHeader(
            "Single Revealer Takes All",
            "All jurors commit to the same option, but only one reveals. "
            "The lone revealer gets all the stake; non-revealers are fully slashed."
        );

        uint256 id = kleros.createDispute("ipfs://QmSingleRevealer");
        kleros.drawJurors(id);
        address[] memory jurors = kleros.getJurors(id);

        _logJurorPanel(jurors);

        bytes32 salt0 = keccak256("salt0");

        (address bigJuror, address medJuror, address smallJuror) =
            _classifyJurorsByStake(jurors);

        _step("All commit Option1 but only bigJuror will reveal later");
        vm.prank(bigJuror);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), salt0)));
        vm.prank(medJuror);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), keccak256("m"))));
        vm.prank(smallJuror);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), keccak256("s"))));

        vm.warp(block.timestamp + 90 minutes);

        _step("Only bigJuror reveals");
        vm.prank(bigJuror);
        kleros.revealVote(id, 1, salt0);

        vm.warp(block.timestamp + 1 hours);
        kleros.finalize(id);

        _logDisputeSummary(id);

        (uint256 bigFinalWei,) = kleros.getJurorStake(bigJuror);
        (uint256 medFinalWei,) = kleros.getJurorStake(medJuror);
        (uint256 smallFinalWei,) = kleros.getJurorStake(smallJuror);

        emit log_named_uint("bigFinal (tokens)", _toTokens(bigFinalWei));
        emit log_named_uint("medFinal (tokens)", _toTokens(medFinalWei));
        emit log_named_uint("smallFinal (tokens)", _toTokens(smallFinalWei));

        assertEq(bigFinalWei, 1000 ether, "single revealer owns all stake");
        assertEq(medFinalWei, 0, "med loses stake");
        assertEq(smallFinalWei, 0, "small loses stake");
    }

    function testNoOneReveals() public {
        _scenarioHeader(
            "No One Reveals: Dispute Undecided",
            "All jurors commit, but none reveals. The ruling remains 'Undecided' "
            "and no redistribution happens."
        );

        uint256 id = kleros.createDispute("ipfs://QmNoReveal");
        kleros.drawJurors(id);
        address[] memory jurors = kleros.getJurors(id);

        _step("All jurors commit a vote, but none will reveal later");
        for (uint256 i = 0; i < jurors.length; i++) {
            vm.prank(jurors[i]);
            kleros.commitVote(
                id,
                keccak256(abi.encodePacked(uint8(1), keccak256(abi.encode(i))))
            );
        }

        vm.warp(block.timestamp + 3 hours);
        kleros.finalize(id);

        _logDisputeSummary(id);

        (, SimpleKlerosPhase3.Ruling ruling,,) = kleros.getDisputeSummary(id);
        assertEq(uint256(ruling), uint256(SimpleKlerosPhase3.Ruling.Undecided), "no reveals -> undecided");
    }

    function testOption2Wins() public {
        _scenarioHeader(
            "Option2 Wins",
            "Check that the system correctly handles the case where Option2 "
            "gets the majority of voting weight."
        );

        uint256 id = kleros.createDispute("ipfs://QmOption2Wins");
        kleros.drawJurors(id);
        address[] memory jurors = kleros.getJurors(id);

        _logJurorPanel(jurors);

        bytes32 salt0 = keccak256("salt0");
        bytes32 salt1 = keccak256("salt1");
        bytes32 salt2 = keccak256("salt2");

        (address bigJuror, address medJuror, address smallJuror) =
            _classifyJurorsByStake(jurors);

        _step("Commit: big+med vote Option2, small votes Option1");
        vm.prank(bigJuror);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(2), salt0)));
        vm.prank(medJuror);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(2), salt1)));
        vm.prank(smallJuror);
        kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), salt2)));

        vm.warp(block.timestamp + 90 minutes);

        _step("Reveal all and finalize; Option2 should win");
        vm.prank(bigJuror);
        kleros.revealVote(id, 2, salt0);
        vm.prank(medJuror);
        kleros.revealVote(id, 2, salt1);
        vm.prank(smallJuror);
        kleros.revealVote(id, 1, salt2);

        vm.warp(block.timestamp + 1 hours);
        kleros.finalize(id);

        _logDisputeSummary(id);

        (, SimpleKlerosPhase3.Ruling ruling,,) = kleros.getDisputeSummary(id);
        assertEq(uint256(ruling), uint256(SimpleKlerosPhase3.Ruling.Option2), "Option2 wins");

        (uint256 smallFinalWei,) = kleros.getJurorStake(smallJuror);
        assertEq(smallFinalWei, 0, "loser is slashed");
    }

    function testCannotCreateDisputeWithoutEnoughJurors() public {
        _scenarioHeader(
            "Cannot Create Dispute Without Enough Jurors",
            "If the system requires more jurors than currently staked addresses, "
            "dispute creation fails."
        );

        SimpleKlerosPhase3 klerosNew = new SimpleKlerosPhase3(
            IERC20(address(token)),
            100 ether,
            10, // require 10 jurors
            1 hours,
            1 hours
        );
        vm.label(address(klerosNew), "SimpleKlerosPhase3_TooManyJurors");

        _step("Only one juror stakes, so there are not enough jurors");
        vm.prank(juror1);
        token.approve(address(klerosNew), type(uint256).max);
        vm.prank(juror1);
        klerosNew.stake(500 ether);

        _step("Creating a dispute must revert with 'not enough jurors'");
        vm.expectRevert("not enough jurors");
        klerosNew.createDispute("ipfs://QmNotEnough");
    }

    function testJurorListGrows() public {
        _scenarioHeader(
            "Juror List Grows as New Jurors Stake",
            "Whenever a new address stakes for the first time, it is added to the juror list."
        );

        address[] memory initial = kleros.getJurorList();
        emit log_named_uint("initial juror count", initial.length);
        assertEq(initial.length, 3);

        address newJuror = address(0x100);
        vm.label(newJuror, "newJurorGrow");
        token.transfer(newJuror, 1000 ether);

        _step("newJuror stakes exactly the minimum (100 tokens)");
        vm.startPrank(newJuror);
        token.approve(address(kleros), type(uint256).max);
        kleros.stake(100 ether);
        vm.stopPrank();

        address[] memory afterList = kleros.getJurorList();
        emit log_named_uint("new juror count", afterList.length);
        assertEq(afterList.length, 4);
    }

    function testVoteWeightSnapshot() public {
        _scenarioHeader(
            "Vote Weight Snapshot at Selection Time",
            "Check that each juror has a non-zero snapshot weight as soon as they are drawn."
        );

        uint256 id = kleros.createDispute("ipfs://QmSnapshot");
        kleros.drawJurors(id);
        address[] memory jurors = kleros.getJurors(id);

        _step("Inspect snapshot weight for first juror before any commit or reveal");
        (bool revealed, uint8 vote, uint256 snapshotWeightWei) =
            kleros.getJurorVote(id, jurors[0]);

        emit log_named_uint("revealed (0/1)", revealed ? 1 : 0);
        emit log_named_uint("vote", vote);
        emit log_named_uint("snapshotWeight (tokens)", _toTokens(snapshotWeightWei));

        assertFalse(revealed, "should not be revealed yet");
        assertEq(vote, 0, "no vote recorded yet");
        assertGt(snapshotWeightWei, 0, "snapshot should be non-zero");
    }

    // ============================================
    // Simple view tests
    // ============================================

    function testGetDisputeSummary() public {
        _scenarioHeader(
            "Basic Dispute Summary After Creation",
            "Immediately after creation, a dispute is in 'Created' phase with no ruling or votes."
        );

        uint256 id = kleros.createDispute("ipfs://QmSummary");

        (SimpleKlerosPhase3.Phase phase,
         SimpleKlerosPhase3.Ruling ruling,
         uint256 v1,
         uint256 v2) = kleros.getDisputeSummary(id);

        emit log_named_string("phase", _phaseToString(phase));
        emit log_named_string("ruling", _rulingToString(ruling));
        emit log_named_uint("Option1 weight (tokens)", _toTokens(v1));
        emit log_named_uint("Option2 weight (tokens)", _toTokens(v2));

        assertEq(uint256(phase), uint256(SimpleKlerosPhase3.Phase.Created));
        assertEq(uint256(ruling), uint256(SimpleKlerosPhase3.Ruling.Undecided));
        assertEq(v1, 0);
        assertEq(v2, 0);
    }

    function testGetJurorStake() public {
        _scenarioHeader(
            "Simple Stake View",
            "Check that the initial stake for juror1 is correctly recorded and not locked."
        );

        (uint256 amountWei, bool locked) = kleros.getJurorStake(juror1);
        emit log_named_uint("juror1 stake (tokens)", _toTokens(amountWei));
        emit log_named_uint("juror1 locked (0/1)", locked ? 1 : 0);

        assertEq(amountWei, 500 ether);
        assertFalse(locked);
    }

    // ============================================
    // Helper: complete dispute with unanimous Option1
    // ============================================

    function _completeDisputeWithOption1Winning() internal returns (uint256) {
        _scenarioHeader(
            "Helper: Complete Dispute with Unanimous Option1",
            "All jurors vote Option1 and reveal, producing a simple winner scenario."
        );

        uint256 id = kleros.createDispute("ipfs://QmHelper");
        kleros.drawJurors(id);
        address[] memory jurors = kleros.getJurors(id);

        bytes32 salt = keccak256("helper");

        _step("All jurors commit Option1");
        for (uint256 i = 0; i < jurors.length; i++) {
            vm.prank(jurors[i]);
            kleros.commitVote(id, keccak256(abi.encodePacked(uint8(1), salt)));
        }

        vm.warp(block.timestamp + 90 minutes);

        _step("All jurors reveal Option1");
        for (uint256 i = 0; i < jurors.length; i++) {
            vm.prank(jurors[i]);
            kleros.revealVote(id, 1, salt);
        }

        vm.warp(block.timestamp + 1 hours);
        kleros.finalize(id);

        _logDisputeSummary(id);
        return id;
    }
}
