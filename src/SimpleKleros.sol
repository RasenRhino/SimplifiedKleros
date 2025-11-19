// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

/// @title SimpleKleros - toy Kleros-style dispute resolution contract
/// @notice NOT production-safe (pseudo-randomness, no slashing, etc.)
contract SimpleKleros {
    // --- Types ---

    enum Phase {
        None,
        Created,
        JurorsDrawn,
        Commit,
        Reveal,
        Resolved
    }
    enum Ruling {
        Undecided,
        Option1,
        Option2
    }

    struct JurorStake {
        uint256 amount;
        bool locked; // true while selected in an active dispute
    }

    struct Vote {
        bytes32 commit; // keccak256(abi.encodePacked(vote, salt))
        uint8 revealedVote; // 1 or 2
        bool revealed;
    }

    struct Dispute {
        uint256 id;
        address creator;
        string metaEvidence; // e.g. IPFS hash or description 
        Phase phase;
        address[] jurors;
        uint256 commitDeadline;
        uint256 revealDeadline;
        uint256 votesOption1;
        uint256 votesOption2;
        Ruling ruling;
        mapping(address => Vote) votes; // juror => vote
    }

    // --- Storage ---

    IERC20 public immutable stakeToken;
    uint256 public immutable minStake;
    uint256 public immutable jurorsPerDispute;
    uint256 public immutable commitDuration;
    uint256 public immutable revealDuration;

    uint256 public disputeCounter;

    // Note: cannot be public because Dispute contains a mapping
    mapping(uint256 => Dispute) private disputes;

    mapping(address => JurorStake) public stakes;
    address[] public jurorList; // all addresses that ever staked

    // --- Events ---

    event Staked(address indexed juror, uint256 amount);
    event Unstaked(address indexed juror, uint256 amount);
    event DisputeCreated(uint256 indexed id, address indexed creator, string metaEvidence);
    event JurorsDrawn(uint256 indexed id, address[] jurors);
    event VoteCommitted(uint256 indexed id, address indexed juror);
    event VoteRevealed(uint256 indexed id, address indexed juror, uint8 vote);
    event DisputeResolved(uint256 indexed id, Ruling ruling);

    // --- Constructor ---

    constructor(
        IERC20 _stakeToken,
        uint256 _minStake,
        uint256 _jurorsPerDispute,
        uint256 _commitDuration,
        uint256 _revealDuration
    ) {
        require(_jurorsPerDispute > 0, "jurorsPerDispute=0");
        stakeToken = _stakeToken;
        minStake = _minStake;
        jurorsPerDispute = _jurorsPerDispute;
        commitDuration = _commitDuration;
        revealDuration = _revealDuration;
    }

    // --- Juror staking ---

    function stake(uint256 amount) external {
        require(amount > 0, "amount=0");

        // pull tokens from sender
        require(stakeToken.transferFrom(msg.sender, address(this), amount), "transferFrom failed");

        JurorStake storage js = stakes[msg.sender];
        if (js.amount == 0) {
            jurorList.push(msg.sender);
        }
        js.amount += amount;
        require(js.amount >= minStake, "below minStake");

        emit Staked(msg.sender, amount);
    }

    function unstake(uint256 amount) external {
        JurorStake storage js = stakes[msg.sender];
        require(!js.locked, "stake locked");
        require(js.amount >= amount, "not enough stake");

        js.amount -= amount;
        require(stakeToken.transfer(msg.sender, amount), "transfer failed");

        emit Unstaked(msg.sender, amount);
    }

    // --- Dispute lifecycle ---

    function createDispute(string calldata metaEvidence) external returns (uint256) {
        require(jurorList.length >= jurorsPerDispute, "not enough jurors");

        uint256 id = ++disputeCounter;

        Dispute storage d = disputes[id];
        d.id = id;
        d.creator = msg.sender;
        d.metaEvidence = metaEvidence;
        d.phase = Phase.Created;

        emit DisputeCreated(id, msg.sender, metaEvidence);
        return id;
    }

    /// @notice Draw jurors for a dispute (pseudo-random, NOT secure, but unique per dispute)
    function drawJurors(uint256 id) external {
        Dispute storage d = disputes[id];
        require(d.phase == Phase.Created, "wrong phase");
        require(jurorList.length >= jurorsPerDispute, "not enough jurors");

        uint256 nonce = 0;

        // keep picking until we have jurorsPerDispute unique jurors
        while (d.jurors.length < jurorsPerDispute) {
            uint256 i = d.jurors.length;
            uint256 rand = uint256(keccak256(abi.encodePacked(blockhash(block.number - 1), id, i, nonce)));
            address juror = jurorList[rand % jurorList.length];

            if (!_isJuror(id, juror)) {
                d.jurors.push(juror);
                stakes[juror].locked = true;
            }

            nonce++;
            // safety guard to avoid infinite loop in pathological cases
            require(nonce < jurorList.length * 10, "cannot find unique jurors");
        }

        d.phase = Phase.JurorsDrawn;
        d.commitDeadline = block.timestamp + commitDuration;
        d.revealDeadline = d.commitDeadline + revealDuration;

        emit JurorsDrawn(id, d.jurors);
    }

    /// @notice Juror commits a vote as a hash(vote, salt)
    function commitVote(uint256 id, bytes32 commitHash) external {
        Dispute storage d = disputes[id];
        require(d.phase == Phase.JurorsDrawn || d.phase == Phase.Commit, "wrong phase");
        require(block.timestamp <= d.commitDeadline, "commit over");
        require(_isJuror(id, msg.sender), "not a juror");

        d.phase = Phase.Commit;

        Vote storage v = d.votes[msg.sender];
        require(v.commit == bytes32(0), "already committed");

        v.commit = commitHash;

        emit VoteCommitted(id, msg.sender);
    }

    /// @notice Juror reveals their vote by providing (vote, salt)
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

        v.revealed = true;
        v.revealedVote = vote;

        if (vote == 1) {
            d.votesOption1 += 1;
        } else {
            d.votesOption2 += 1;
        }

        emit VoteRevealed(id, msg.sender, vote);
    }

    /// @notice Finalizes the dispute once reveal phase is over
    function finalize(uint256 id) external {
        Dispute storage d = disputes[id];
        require(d.phase == Phase.Reveal, "wrong phase");
        require(block.timestamp > d.revealDeadline, "reveal not finished");

        if (d.votesOption1 > d.votesOption2) {
            d.ruling = Ruling.Option1;
        } else if (d.votesOption2 > d.votesOption1) {
            d.ruling = Ruling.Option2;
        } else {
            d.ruling = Ruling.Undecided; // tie: you could refund everybody, etc.
        }

        d.phase = Phase.Resolved;

        // Unlock juror stakes (no slashing/rewards in this minimal version)
        for (uint256 i = 0; i < d.jurors.length; i++) {
            stakes[d.jurors[i]].locked = false;
        }

        emit DisputeResolved(id, d.ruling);
    }

    // --- View helpers ---

    function getJurors(uint256 id) external view returns (address[] memory) {
        return disputes[id].jurors;
    }

    function getDisputeSummary(uint256 id)
        external
        view
        returns (Phase phase, Ruling ruling, uint256 votes1, uint256 votes2)
    {
        Dispute storage d = disputes[id];
        return (d.phase, d.ruling, d.votesOption1, d.votesOption2);
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
