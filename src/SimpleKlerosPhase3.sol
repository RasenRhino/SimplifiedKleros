// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

/// @title SimpleKlerosPhase3 - Full Cryptoeconomic Incentive System
/// @notice Phase 3: Stake redistribution - losers are slashed, winners are rewarded
contract SimpleKlerosPhase3 {
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
        bytes32 commit;      // keccak256(abi.encodePacked(vote, salt))
        uint8 revealedVote;  // 1 or 2
        bool revealed;
        uint256 weight;      // snapshot of staked amount at time of selection
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

    IERC20 public immutable stakeToken;
    uint256 public immutable minStake;
    uint256 public immutable jurorsPerDispute;
    uint256 public immutable commitDuration;
    uint256 public immutable revealDuration;

    uint256 public disputeCounter;

    mapping(uint256 => Dispute) private disputes;
    mapping(address => JurorStake) public stakes;
    address[] public jurorList; // all addresses that have ever staked

    // --- Events ---

    event Staked(address indexed juror, uint256 amount);
    event Unstaked(address indexed juror, uint256 amount);
    event DisputeCreated(uint256 indexed id, address indexed creator, string metaEvidence);
    event JurorsDrawn(uint256 indexed id, address[] jurors);
    event VoteCommitted(uint256 indexed id, address indexed juror);
    event VoteRevealed(uint256 indexed id, address indexed juror, uint8 vote, uint256 weight);
    event DisputeResolved(uint256 indexed id, Ruling ruling);
    event StakeRedistributed(
        uint256 indexed id, address indexed from, address indexed to, uint256 amount
    );

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

    /// @notice Stake tokens to become eligible as a juror
    /// @dev Tokens are locked in the contract
    function stake(uint256 amount) external {
        require(amount > 0, "amount=0");
        require(stakeToken.transferFrom(msg.sender, address(this), amount), "transferFrom failed");

        JurorStake storage js = stakes[msg.sender];
        if (js.amount == 0) {
            jurorList.push(msg.sender);
        }
        js.amount += amount;
        require(js.amount >= minStake, "below minStake");

        emit Staked(msg.sender, amount);
    }

    /// @notice Unstake tokens (only if not locked in a dispute)
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

    /// @notice Draw jurors for a dispute (pseudo-random)
    function drawJurors(uint256 id) external {
        Dispute storage d = disputes[id];
        require(d.phase == Phase.Created, "wrong phase");
        require(jurorList.length >= jurorsPerDispute, "not enough jurors");

        uint256 nonce = 0;

        // Keep picking until we have jurorsPerDispute unique jurors
        while (d.jurors.length < jurorsPerDispute) {
            uint256 i = d.jurors.length;
            uint256 rand =
                uint256(keccak256(abi.encodePacked(blockhash(block.number - 1), id, i, nonce)));
            address juror = jurorList[rand % jurorList.length];

            // Check if juror has sufficient stake and is not already selected
            if (!_isJuror(id, juror) && stakes[juror].amount >= minStake && !stakes[juror].locked) {
                d.jurors.push(juror);
                stakes[juror].locked = true; // Lock their stake

                // 🔹 SNAPSHOT weight at selection time
                Vote storage v = d.votes[juror];
                v.weight = stakes[juror].amount;
            }

            nonce++;
            require(nonce < jurorList.length * 10, "cannot find unique jurors");
        }

        d.phase = Phase.JurorsDrawn;
        d.commitDeadline = block.timestamp + commitDuration;
        d.revealDeadline = d.commitDeadline + revealDuration;

        emit JurorsDrawn(id, d.jurors);
    }

    /// @notice Juror commits a vote as hash(vote, salt)
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
    /// @dev Voting weight = juror's SNAPSHOT stake at selection time
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

        uint256 weight = v.weight;
        require(weight >= minStake, "snapshot stake too low");

        v.revealed = true;
        v.revealedVote = vote;

        if (vote == 1) {
            d.weightedVotesOption1 += weight;
        } else {
            d.weightedVotesOption2 += weight;
        }

        emit VoteRevealed(id, msg.sender, vote, weight);
    }

    /// @notice Finalizes the dispute once reveal phase is over
    /// @dev PHASE 3 KEY FEATURE: Redistributes stakes from minority to majority
    function finalize(uint256 id) external {
        Dispute storage d = disputes[id];
        // Allow finalize even if nobody revealed (phase could still be Commit)
        require(
            d.phase == Phase.Reveal || d.phase == Phase.Commit,
            "wrong phase"
        );
        require(block.timestamp > d.revealDeadline, "reveal not finished");

        // Determine ruling
        if (d.weightedVotesOption1 > d.weightedVotesOption2) {
            d.ruling = Ruling.Option1;
        } else if (d.weightedVotesOption2 > d.weightedVotesOption1) {
            d.ruling = Ruling.Option2;
        } else {
            d.ruling = Ruling.Undecided;
        }

        d.phase = Phase.Resolved;

        // PHASE 3: STAKE REDISTRIBUTION
        if (d.ruling != Ruling.Undecided) {
            _redistributeStakes(id, d);
        } else {
            // In case of tie, just unlock everyone with no redistribution
            for (uint256 i = 0; i < d.jurors.length; i++) {
                stakes[d.jurors[i]].locked = false;
            }
        }

        emit DisputeResolved(id, d.ruling);
    }

    /// @notice PHASE 3: Redistribute stakes from minority to majority
    function _redistributeStakes(uint256 id, Dispute storage d) internal {
        uint8 winningVote = d.ruling == Ruling.Option1 ? 1 : 2;

        // First pass: compute total slashed and total winner weight (based on snapshot weight)
        uint256 totalSlashed = 0;
        uint256 totalWinnerWeight = 0;

        for (uint256 i = 0; i < d.jurors.length; i++) {
            address juror = d.jurors[i];
            Vote storage v = d.votes[juror];

            bool isWinner = v.revealed && v.revealedVote == winningVote;
            if (isWinner) {
                totalWinnerWeight += v.weight;
            }
        }

        // Second pass: slash losers (including non-revealers)
        for (uint256 i = 0; i < d.jurors.length; i++) {
            address juror = d.jurors[i];
            Vote storage v = d.votes[juror];

            bool isWinner = v.revealed && v.revealedVote == winningVote;
            if (!isWinner) {
                // loser (wrong vote or failed to reveal)
                uint256 stakeAmt = stakes[juror].amount;
                if (stakeAmt > 0) {
                    // For simplicity: slash ENTIRE stake
                    totalSlashed += stakeAmt;
                    stakes[juror].amount = 0;

                    emit StakeRedistributed(id, juror, address(0), stakeAmt);
                }
                stakes[juror].locked = false;
            }
        }

        // Third pass: distribute slashed stakes to winners proportionally to snapshot weight
        if (totalSlashed > 0 && totalWinnerWeight > 0) {
            for (uint256 i = 0; i < d.jurors.length; i++) {
                address juror = d.jurors[i];
                Vote storage v = d.votes[juror];

                bool isWinner = v.revealed && v.revealedVote == winningVote;
                if (isWinner) {
                    uint256 reward = (totalSlashed * v.weight) / totalWinnerWeight;
                    stakes[juror].amount += reward;
                    stakes[juror].locked = false;

                    emit StakeRedistributed(id, address(0), juror, reward);
                }
            }
        } else {
            // No slashing or no winners: just unlock winners
            for (uint256 i = 0; i < d.jurors.length; i++) {
                address juror = d.jurors[i];
                stakes[juror].locked = false;
            }
        }
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

    function getJurorVote(uint256 id, address juror)
        external
        view
        returns (bool revealed, uint8 vote, uint256 weight)
    {
        Vote storage v = disputes[id].votes[juror];
        return (v.revealed, v.revealedVote, v.weight);
    }

    function getJurorList() external view returns (address[] memory) {
        return jurorList;
    }

    function getJurorStake(address juror) external view returns (uint256 amount, bool locked) {
        JurorStake storage js = stakes[juror];
        return (js.amount, js.locked);
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
