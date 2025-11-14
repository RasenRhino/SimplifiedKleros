// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
}

/// @title SimpleKlerosPhase1 - Token-Weighted Blind Auction
/// @notice Phase 1: Voting weight based on token balance, commit-reveal scheme, no staking
contract SimpleKlerosPhase1 {
    // --- Types ---

    enum Phase {
        None,
        Created,
        JurorsSelected,
        Commit,
        Reveal,
        Resolved
    }

    enum Ruling {
        Undecided,
        Option1,
        Option2
    }

    struct Vote {
        bytes32 commit; // keccak256(abi.encodePacked(vote, salt))
        uint8 revealedVote; // 1 or 2
        bool revealed;
        uint256 weight; // token balance at time of reveal
    }

    struct Dispute {
        uint256 id;
        address creator;
        string metaEvidence;
        Phase phase;
        address[] jurors;
        uint256 commitDeadline;
        uint256 revealDeadline;
        uint256 weightedVotesOption1;
        uint256 weightedVotesOption2;
        Ruling ruling;
        mapping(address => Vote) votes;
    }

    // --- Storage ---

    IERC20 public immutable token;
    uint256 public immutable minBalance; // minimum token balance to be a juror
    uint256 public immutable jurorsPerDispute;
    uint256 public immutable commitDuration;
    uint256 public immutable revealDuration;

    uint256 public disputeCounter;

    mapping(uint256 => Dispute) private disputes;
    address[] public eligibleJurors; // manually registered jurors with sufficient balance

    // --- Events ---

    event JurorRegistered(address indexed juror, uint256 balance);
    event DisputeCreated(uint256 indexed id, address indexed creator, string metaEvidence);
    event JurorsSelected(uint256 indexed id, address[] jurors);
    event VoteCommitted(uint256 indexed id, address indexed juror);
    event VoteRevealed(uint256 indexed id, address indexed juror, uint8 vote, uint256 weight);
    event DisputeResolved(uint256 indexed id, Ruling ruling);

    // --- Constructor ---

    constructor(
        IERC20 _token,
        uint256 _minBalance,
        uint256 _jurorsPerDispute,
        uint256 _commitDuration,
        uint256 _revealDuration
    ) {
        require(_jurorsPerDispute > 0, "jurorsPerDispute=0");
        token = _token;
        minBalance = _minBalance;
        jurorsPerDispute = _jurorsPerDispute;
        commitDuration = _commitDuration;
        revealDuration = _revealDuration;
    }

    // --- Juror Registration (Phase 1: no staking, just registration) ---

    /// @notice Register as a juror if you have sufficient token balance
    function registerAsJuror() external {
        uint256 balance = token.balanceOf(msg.sender);
        require(balance >= minBalance, "insufficient balance");

        // Check if already registered
        for (uint256 i = 0; i < eligibleJurors.length; i++) {
            require(eligibleJurors[i] != msg.sender, "already registered");
        }

        eligibleJurors.push(msg.sender);
        emit JurorRegistered(msg.sender, balance);
    }

    // --- Dispute lifecycle ---

    function createDispute(string calldata metaEvidence) external returns (uint256) {
        require(eligibleJurors.length >= jurorsPerDispute, "not enough jurors");

        uint256 id = ++disputeCounter;

        Dispute storage d = disputes[id];
        d.id = id;
        d.creator = msg.sender;
        d.metaEvidence = metaEvidence;
        d.phase = Phase.Created;

        emit DisputeCreated(id, msg.sender, metaEvidence);
        return id;
    }

    /// @notice Select jurors for a dispute (pseudo-random)
    function selectJurors(uint256 id) external {
        Dispute storage d = disputes[id];
        require(d.phase == Phase.Created, "wrong phase");
        require(eligibleJurors.length >= jurorsPerDispute, "not enough jurors");

        uint256 nonce = 0;

        // Keep picking until we have jurorsPerDispute unique jurors
        while (d.jurors.length < jurorsPerDispute) {
            uint256 i = d.jurors.length;
            uint256 rand = uint256(keccak256(abi.encodePacked(blockhash(block.number - 1), id, i, nonce)));
            address juror = eligibleJurors[rand % eligibleJurors.length];

            // Verify juror still has sufficient balance
            if (!_isJuror(id, juror) && token.balanceOf(juror) >= minBalance) {
                d.jurors.push(juror);
            }

            nonce++;
            require(nonce < eligibleJurors.length * 10, "cannot find unique jurors");
        }

        d.phase = Phase.JurorsSelected;
        d.commitDeadline = block.timestamp + commitDuration;
        d.revealDeadline = d.commitDeadline + revealDuration;

        emit JurorsSelected(id, d.jurors);
    }

    /// @notice Juror commits a vote as hash(vote, salt)
    function commitVote(uint256 id, bytes32 commitHash) external {
        Dispute storage d = disputes[id];
        require(d.phase == Phase.JurorsSelected || d.phase == Phase.Commit, "wrong phase");
        require(block.timestamp <= d.commitDeadline, "commit over");
        require(_isJuror(id, msg.sender), "not a juror");

        d.phase = Phase.Commit;

        Vote storage v = d.votes[msg.sender];
        require(v.commit == bytes32(0), "already committed");

        v.commit = commitHash;

        emit VoteCommitted(id, msg.sender);
    }

    /// @notice Juror reveals their vote by providing (vote, salt)
    /// @dev Voting weight = juror's token balance at time of reveal
    function revealVote(uint256 id, uint8 vote, bytes32 salt) external {
        require(vote == 1 || vote == 2, "invalid vote");

        Dispute storage d = disputes[id];
        require(d.phase == Phase.Commit || d.phase == Phase.Reveal, "wrong phase");
        require(block.timestamp > d.commitDeadline, "commit not finished");
        require(block.timestamp <= d.revealDeadline, "reveal over");
        require(_isJuror(id, msg.sender), "not a juror");

        d.phase = Phase.Reveal;

        Vote storage v = d.votes[msg.sender];
        require(v.commit != bytes32(0), "no commit");
        require(!v.revealed, "already revealed");

        bytes32 expected = keccak256(abi.encodePacked(vote, salt));
        require(expected == v.commit, "bad reveal");

        // PHASE 1 KEY FEATURE: Weight is based on current token balance
        uint256 weight = token.balanceOf(msg.sender);
        require(weight >= minBalance, "balance too low");

        v.revealed = true;
        v.revealedVote = vote;
        v.weight = weight;

        if (vote == 1) {
            d.weightedVotesOption1 += weight;
        } else {
            d.weightedVotesOption2 += weight;
        }

        emit VoteRevealed(id, msg.sender, vote, weight);
    }

    /// @notice Finalizes the dispute once reveal phase is over
    function finalize(uint256 id) external {
        Dispute storage d = disputes[id];
        require(d.phase == Phase.Reveal, "wrong phase");
        require(block.timestamp > d.revealDeadline, "reveal not finished");

        if (d.weightedVotesOption1 > d.weightedVotesOption2) {
            d.ruling = Ruling.Option1;
        } else if (d.weightedVotesOption2 > d.weightedVotesOption1) {
            d.ruling = Ruling.Option2;
        } else {
            d.ruling = Ruling.Undecided;
        }

        d.phase = Phase.Resolved;

        emit DisputeResolved(id, d.ruling);
    }

    // --- View helpers ---

    function getJurors(uint256 id) external view returns (address[] memory) {
        return disputes[id].jurors;
    }

    function getDisputeSummary(uint256 id)
        external
        view
        returns (Phase phase, Ruling ruling, uint256 weightedVotes1, uint256 weightedVotes2)
    {
        Dispute storage d = disputes[id];
        return (d.phase, d.ruling, d.weightedVotesOption1, d.weightedVotesOption2);
    }

    function getJurorVote(uint256 id, address juror) external view returns (bool revealed, uint8 vote, uint256 weight) {
        Vote storage v = disputes[id].votes[juror];
        return (v.revealed, v.revealedVote, v.weight);
    }

    function getEligibleJurors() external view returns (address[] memory) {
        return eligibleJurors;
    }

    // --- Internal helpers ---

    function _isJuror(uint256 id, address juror) internal view returns (bool) {
        Dispute storage d = disputes[id];
        for (uint256 i = 0; i < d.jurors.length; i++) {
            if (d.jurors[i] == juror) {
                return true;
            }
        }
        return false;
    }
}
