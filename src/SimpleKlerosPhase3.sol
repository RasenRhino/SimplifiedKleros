// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

/// @title SimpleKlerosPhase3 - Weighted Juror Selection with Multi-Selection
/// @notice Phase 3: 
///   - Jurors are selected via weighted random (higher stake = higher chance)
///   - Same juror can be picked multiple times (weight = # times picked)
///   - Always pick odd number of juror slots to avoid ties
///   - Each selection locks minStake tokens
///   - Stake redistribution: losers are slashed, winners are rewarded
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
        uint256 amount;      // total staked amount
        uint256 lockedAmount; // amount currently locked in disputes
    }

    struct Vote {
        bytes32 commit;       // keccak256(abi.encodePacked(vote, salt))
        uint8 revealedVote;   // 1 or 2
        bool revealed;
        uint256 selectionCount; // number of times this juror was selected (their voting weight)
        uint256 lockedStake;    // minStake * selectionCount (stake at risk for this dispute)
    }

    struct Dispute {
        uint256 id;
        address creator;
        string metaEvidence;
        Phase phase;
        address[] uniqueJurors;  // list of unique juror addresses selected
        uint256 totalSelections; // total number of selection slots (always odd)
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
    uint256 public immutable numDraws;      // number of draw slots (must be odd)
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
    event JurorsDrawn(uint256 indexed id, address[] uniqueJurors, uint256 totalSelections);
    event JurorSelected(uint256 indexed id, address indexed juror, uint256 selectionCount);
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
        uint256 _numDraws,
        uint256 _commitDuration,
        uint256 _revealDuration
    ) {
        require(_numDraws > 0 && _numDraws % 2 == 1, "numDraws must be odd and > 0");
        stakeToken = _stakeToken;
        minStake = _minStake;
        numDraws = _numDraws;
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

    /// @notice Unstake tokens (only unlocked portion)
    function unstake(uint256 amount) external {
        JurorStake storage js = stakes[msg.sender];
        uint256 available = js.amount - js.lockedAmount;
        require(available >= amount, "not enough unlocked stake");

        js.amount -= amount;
        require(stakeToken.transfer(msg.sender, amount), "transfer failed");

        emit Unstaked(msg.sender, amount);
    }

    // --- Dispute lifecycle ---

    function createDispute(string calldata metaEvidence) external returns (uint256) {
        // Need at least one juror with sufficient stake
        require(_getTotalStake() >= minStake, "not enough total stake");

        uint256 id = ++disputeCounter;

        Dispute storage d = disputes[id];
        d.id = id;
        d.creator = msg.sender;
        d.metaEvidence = metaEvidence;
        d.phase = Phase.Created;

        emit DisputeCreated(id, msg.sender, metaEvidence);
        return id;
    }

    /// @notice Draw jurors for a dispute using weighted random selection
    /// @dev Each draw slot picks a juror with probability proportional to their available stake
    ///      Same juror can be picked multiple times (each selection = +1 voting weight)
    ///      IMPORTANT: totalStake is recalculated each iteration to account for newly locked stake
    function drawJurors(uint256 id) external {
        Dispute storage d = disputes[id];
        require(d.phase == Phase.Created, "wrong phase");

        // Initial check - must have enough stake to start
        uint256 initialTotalStake = _getTotalStake();
        require(initialTotalStake >= minStake, "not enough total stake");

        // Perform numDraws weighted random selections
        for (uint256 i = 0; i < numDraws; i++) {
            // CRITICAL FIX: Recalculate available stake for EACH draw
            // This accounts for stake that was locked in previous iterations
            uint256 currentTotalStake = _getTotalStake();
            require(currentTotalStake >= minStake, "not enough available stake for draw");

            // Use nonce for retry mechanism if selected juror can't accept another selection
            uint256 nonce = 0;
            uint256 maxRetries = jurorList.length * 10; // Safety limit
            bool selected = false;

            while (!selected && nonce < maxRetries) {
                // Generate random number with nonce for retries
                uint256 rand = uint256(keccak256(abi.encodePacked(
                    blockhash(block.number - 1), 
                    id, 
                    i, 
                    nonce,
                    block.timestamp
                )));
                
                // Pick juror based on weighted random (uses fresh available stake)
                address selectedJuror = _weightedRandomSelect(rand, currentTotalStake);
                
                // Check if this juror can accept another selection
                JurorStake storage js = stakes[selectedJuror];
                
                // CRITICAL FIX: Instead of reverting, check and retry if insufficient
                if (js.amount >= js.lockedAmount + minStake) {
                    // Juror has enough stake - proceed with selection
                    uint256 currentLocked = d.votes[selectedJuror].lockedStake;
                    uint256 newLocked = currentLocked + minStake;
                    
                    // Update selection count
                    Vote storage v = d.votes[selectedJuror];
                    if (v.selectionCount == 0) {
                        // First time selected for this dispute
                        d.uniqueJurors.push(selectedJuror);
                    }
                    v.selectionCount += 1;
                    v.lockedStake = newLocked;
                    
                    // Lock the stake
                    js.lockedAmount += minStake;
                    
                    d.totalSelections += 1;
                    selected = true;
                    
                    emit JurorSelected(id, selectedJuror, v.selectionCount);
                } else {
                    // Juror doesn't have enough stake - try again with new random
                    nonce++;
                }
            }

            // If we couldn't find a juror after max retries, revert
            require(selected, "could not find eligible juror");
        }

        d.phase = Phase.JurorsDrawn;
        d.commitDeadline = block.timestamp + commitDuration;
        d.revealDeadline = d.commitDeadline + revealDuration;

        emit JurorsDrawn(id, d.uniqueJurors, d.totalSelections);
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
    /// @dev Voting weight = number of times juror was selected
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

        uint256 weight = v.selectionCount;
        require(weight > 0, "no selection weight");

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
    /// @dev Redistributes stakes from minority to majority
    function finalize(uint256 id) external {
        Dispute storage d = disputes[id];
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

        // Stake redistribution
        if (d.ruling != Ruling.Undecided) {
            _redistributeStakes(id, d);
        } else {
            // In case of tie, just unlock everyone with no redistribution
            for (uint256 i = 0; i < d.uniqueJurors.length; i++) {
                address juror = d.uniqueJurors[i];
                Vote storage v = d.votes[juror];
                stakes[juror].lockedAmount -= v.lockedStake;
            }
        }

        emit DisputeResolved(id, d.ruling);
    }

    /// @notice Redistribute stakes from minority to majority
    function _redistributeStakes(uint256 id, Dispute storage d) internal {
        uint8 winningVote = d.ruling == Ruling.Option1 ? 1 : 2;

        // First pass: compute total slashed and total winner weight
        uint256 totalSlashed = 0;
        uint256 totalWinnerWeight = 0;

        for (uint256 i = 0; i < d.uniqueJurors.length; i++) {
            address juror = d.uniqueJurors[i];
            Vote storage v = d.votes[juror];

            bool isWinner = v.revealed && v.revealedVote == winningVote;
            if (isWinner) {
                totalWinnerWeight += v.selectionCount;
            }
        }

        // Second pass: slash losers (including non-revealers)
        for (uint256 i = 0; i < d.uniqueJurors.length; i++) {
            address juror = d.uniqueJurors[i];
            Vote storage v = d.votes[juror];

            bool isWinner = v.revealed && v.revealedVote == winningVote;
            if (!isWinner) {
                // Loser: slash their locked stake for this dispute
                uint256 slashAmount = v.lockedStake;
                if (slashAmount > 0) {
                    totalSlashed += slashAmount;
                    stakes[juror].amount -= slashAmount;
                    stakes[juror].lockedAmount -= slashAmount;

                    emit StakeRedistributed(id, juror, address(0), slashAmount);
                }
            }
        }

        // Third pass: distribute slashed stakes to winners proportionally
        if (totalSlashed > 0 && totalWinnerWeight > 0) {
            for (uint256 i = 0; i < d.uniqueJurors.length; i++) {
                address juror = d.uniqueJurors[i];
                Vote storage v = d.votes[juror];

                bool isWinner = v.revealed && v.revealedVote == winningVote;
                if (isWinner) {
                    uint256 reward = (totalSlashed * v.selectionCount) / totalWinnerWeight;
                    stakes[juror].amount += reward;
                    stakes[juror].lockedAmount -= v.lockedStake;

                    emit StakeRedistributed(id, address(0), juror, reward);
                }
            }
        } else {
            // No slashing or no winners: just unlock
            for (uint256 i = 0; i < d.uniqueJurors.length; i++) {
                address juror = d.uniqueJurors[i];
                Vote storage v = d.votes[juror];
                stakes[juror].lockedAmount -= v.lockedStake;
            }
        }
    }

    // --- View helpers ---

    function getJurors(uint256 id) external view returns (address[] memory) {
        return disputes[id].uniqueJurors;
    }

    function getDisputeSummary(uint256 id)
        external
        view
        returns (Phase phase, Ruling ruling, uint256 weightedVotes1, uint256 weightedVotes2, uint256 totalSelections)
    {
        Dispute storage d = disputes[id];
        return (d.phase, d.ruling, d.weightedVotesOption1, d.weightedVotesOption2, d.totalSelections);
    }

    function getJurorVote(uint256 id, address juror)
        external
        view
        returns (bool revealed, uint8 vote, uint256 selectionCount, uint256 lockedStake)
    {
        Vote storage v = disputes[id].votes[juror];
        return (v.revealed, v.revealedVote, v.selectionCount, v.lockedStake);
    }

    function getJurorList() external view returns (address[] memory) {
        return jurorList;
    }

    function getJurorStake(address juror) external view returns (uint256 amount, uint256 lockedAmount) {
        JurorStake storage js = stakes[juror];
        return (js.amount, js.lockedAmount);
    }

    function getTotalSelections(uint256 id) external view returns (uint256) {
        return disputes[id].totalSelections;
    }

    // --- Internal helpers ---

    function _isJuror(uint256 id, address juror) internal view returns (bool) {
        return disputes[id].votes[juror].selectionCount > 0;
    }

    function _getTotalStake() internal view returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < jurorList.length; i++) {
            JurorStake storage js = stakes[jurorList[i]];
            // Only count unlocked stake as available
            if (js.amount > js.lockedAmount) {
                total += (js.amount - js.lockedAmount);
            }
        }
        return total;
    }

    /// @notice Select a juror using weighted random based on stake
    /// @dev Higher stake = higher probability of selection
    function _weightedRandomSelect(uint256 rand, uint256 totalStake) internal view returns (address) {
        uint256 target = rand % totalStake;
        uint256 cumulative = 0;
        
        for (uint256 i = 0; i < jurorList.length; i++) {
            address juror = jurorList[i];
            JurorStake storage js = stakes[juror];
            
            // Use available (unlocked) stake for selection probability
            uint256 available = 0;
            if (js.amount > js.lockedAmount) {
                available = js.amount - js.lockedAmount;
            }
            
            if (available == 0) continue;
            
            cumulative += available;
            if (target < cumulative) {
                return juror;
            }
        }
        
        // Fallback: return first juror with AVAILABLE stake (shouldn't happen with fresh totalStake)
        // CRITICAL: Must check available stake, not just total stake!
        // A juror might have 500 staked but 500 locked = 0 available
        for (uint256 i = 0; i < jurorList.length; i++) {
            JurorStake storage jsFallback = stakes[jurorList[i]];
            uint256 availableFallback = 0;
            if (jsFallback.amount > jsFallback.lockedAmount) {
                availableFallback = jsFallback.amount - jsFallback.lockedAmount;
            }
            if (availableFallback >= minStake) {
                return jurorList[i];
            }
        }
        
        revert("no eligible juror");
    }
}
