# Implementation and Analysis of a Simplified Decentralized Dispute Resolution System

**Authors:** Ridham Bhagat, Daniel Mints
**Course:** Distributed Systems  
**Institution:** Northeastern University

**[View README](README.md)** - Quick start guide and test commands

---

## 1. Background and Motivation

The rapid expansion of the digital economy has led to a surge in peer-to-peer transactions across jurisdictional boundaries. Traditional legal systems are often too slow, expensive, and geographically limited to handle disputes arising from these interactions, such as freelancing disagreements or crowdfunding failures.

The theoretical foundation for solving this problem lies in the concept of the Schelling Point (or Focal Point). Game theorist Thomas Schelling posited that in the absence of communication, rational actors will converge on a solution that seems natural or prominent. Vitalik Buterin expanded this into the "SchellingCoin" concept, where agents are economically incentivized to vote on the "truth" by rewarding consensus and penalizing deviation.

Kleros applies this mechanism to dispute resolution. It acts as a decentralized third party, utilizing crowdsourced jurors and game-theoretic incentives to render judgments. The core ideology is not to guarantee a perfect outcome in every instance, but to create a resilient process that probabilistically converges on the truth while resisting bribery and strategic manipulation.

We took up this project as we think such a system can be useful for agentic AI collaboration and cross border payment channels. Another possible use case that interests us is using such a system for creating a crowdsourced training corpus and feedback mechanisms for AI systems. 

## 2. Project Goals

The primary objective of this project was to architect and implement `SimpleKleros`, a simplified version of the Kleros protocol. Rather than creating a production-ready clone, the goal was to strip the system down to its fundamental game-theoretic components to analyze the mechanics of decentralized justice.

Specific goals included:

- **Core Mechanics Implementation:** Developing the finite state machine for dispute creation, juror selection, voting, and execution.
- **Gap Analysis:** Identifying and enumerating the specific pitfalls that arise from simplifying the standard Kleros specification, particularly regarding scalability and economic security.
- **Testing:** The majority of the effort was dedicated to writing a comprehensive test suite. This served as the "Proof of Work" for our understanding of the system, verifying how the protocol handles edge cases and adversarial behavior (e.g., "lazy" jurors or strategic voters). Lazy juror being someone who won't reveal their vote and a strategic voter being someone who would want to find leverages that are not common knowledge to gain certain edge. 

### Key Features of our implementation

| Feature | Description |
|---------|-------------|
| **Weighted Random Selection** | Higher stake = higher chance of being selected as juror (see `testWeightedSelectionFavorsHigherStakes`, `testWeightedSelectionWithMultipleRandomSeeds`, and `testFuzz_WeightedSelectionFavorsHigherStakes`) |
| **Multi-Selection** | Same juror can be picked multiple times (each pick = +1 voting power), demonstrated in `testJurorCanBeSelectedMultipleTimes` |
| **Odd Number of Draws** | Always odd (3, 5, 7...) to prevent ties (`testNumDrawsMustBeOdd`, `testNumDrawsMustBePositive`) |
| **Stake Locking** | Each selection locks `minStake` tokens until dispute resolves (`testStakeLockedIsMinStakeTimesSelections`) |
| **Commit-Reveal Voting** | Secret votes prevent copying others (`testCannotRevealWithWrongSalt`, `testCannotRevealWithWrongVote`) |
| **Stake Redistribution** | Losers are slashed, winners gain proportionally (`testMajorityWinsAndGetsReward`, `testLoserGetsSlashed`) |

### Key Rules

| Rule | Why |
|------|-----|
| **Commit-reveal** | Prevents copying others' votes; enforced by tests like `testCannotRevealWithWrongSalt`, `testCannotRevealWithWrongVote`, and `testCannotRevealTwice` |
| **Weighted selection** | Higher stake = more skin in the game (`testWeightedSelectionFavorsHigherStakes`) |
| **Multi-selection** | Natural weighting without complex math (`testJurorCanBeSelectedMultipleTimes`) |
| **Odd draws only** | Prevents ties in voting (`testNumDrawsMustBeOdd`) |
| **Locked during dispute** | Can't withdraw while voting (`testCannotUnstakeWhileLocked`) |
| **Non-revealers lose** | Forces participation (`testNonRevealerLosesStake`) |
| **Recalculate stake each draw** | Prevents stale stake bugs (`testFix_StaleTotalStakeInDrawLoop`, `testFix_CorrectTotalStakeAfterMultipleSelections`) |


### The Economic Logic

```
"I think others will vote for the obvious truth"
        ↓
"If I vote the same, I'm in the majority"
        ↓
"I'll take money from the minority"
        ↓
Everyone votes honestly → System finds truth
```

---

## 3. Architecture and Design

The system is designed as an Ethereum smart contract acting as an Arbitrator.

### 3.1 The State Machine

~~~~mermaid
stateDiagram-v2
    [*] --> Created: createDispute()
    
    state Created {
        [*] --> CheckStake
        CheckStake --> Ready: TotalStake >= MinStake
    }

    Created --> JurorsDrawn: drawJurors()
    note right of JurorsDrawn
        Jurors selected based on
        weighted random stake.
        Tokens locked.
    end note

    JurorsDrawn --> Commit: commitVote()
    
    state Commit {
        [*] --> VotingOpen
        VotingOpen --> VotingClosed: block.timestamp > commitDeadline
    }

    Commit --> Reveal: revealVote()
    note right of Reveal
        Jurors reveal vote + salt.
        Must match commit hash.
    end note

    state Reveal {
        [*] --> RevealingOpen
        RevealingOpen --> RevealingClosed: block.timestamp > revealDeadline
    }

    Reveal --> Resolved: finalize()
    
    state Resolved {
        [*] --> TallyVotes
        TallyVotes --> Redistribute: Determine Majority
        Redistribute --> SlashLosers
        SlashLosers --> RewardWinners
        RewardWinners --> UnlockStake
    }

    Resolved --> [*]
~~~~

**Dispute Creation:** An arbitrable contract (e.g., an Escrow) raises a dispute.

**Juror Selection:** Jurors are drawn based on the weight of their staked tokens. Kleros selects an odd number of jurors to minimize the chance of a tie. However, situations may still arise—for example, with 7 jurors, if one fails to reveal their vote, a 3-3 tie can occur. See [section 5.7](#57-handling-tie-events) for a discussion of how such cases are handled, and tests `testTieNoRedistribution` and `testTieResultsInUndecided` for concrete executions.

**Commit Phase:** Selected jurors submit a hash of their vote (`keccak256(vote + salt)`). This prevents "bandwagoning" where jurors simply copy the visible majority to secure their reward.

**Reveal Phase:** Jurors reveal their actual vote and salt. The contract verifies this against the commit hash.

**Execution/Finalize:** The contract aggregates votes, declares a winner, and redistributes stakes from the minority to the majority. This is exercised in `testMajorityWinsAndGetsReward`, `testLoserGetsSlashed`, and `testCanUnstakeAfterDispute`.

### 3.2 Weighted Juror Selection

A critical component of the design is Sybil resistance. In Kleros, the probability of being drawn as a juror is proportional to the amount of tokens staked.

In our `SimpleKlerosPhase3` implementation, we utilized a linear weighted random selection algorithm. The simplified logic iterates through the list of jurors, summing their "available" stake (total stake minus locked stake) to determine selection probability. This ensures that a juror cannot be selected more times than their stake allows, a critical fix we identified during testing to prevent Denial of Service (DoS) scenarios (see `testFix_StaleTotalStakeInDrawLoop`, `testFix_CorrectTotalStakeAfterMultipleSelections`, and `testFix_NoDoSWhenJurorHasInsufficientStake`).

---

## 4. Achievements and Implementation Details

We successfully delivered a functional Solidity contract and a Foundry test suite.

### 4.1 Key Features Implemented

- **End-to-End Dispute Cycle:** Successfully executed the full flow: `createDispute → drawJurors → commitVote → revealVote → finalize`. This full lifecycle is walked through in tests like `testMajorityWinsAndGetsReward`, `testNonRevealerLosesStake`, and `testCanUnstakeAfterDispute`.
- **Multi-Selection Support:** Implemented logic allowing a single high-stake juror to be selected multiple times for the same dispute, increasing their voting weight and potential rewards/penalties, mirroring the behavior described in the Kleros Whitepaper. This is observed directly in `testJurorCanBeSelectedMultipleTimes` and the weighted selection tests.
- **Incentive Redistribution:** Implemented the mechanism where incoherent jurors (those voting against the majority) lose their locked stake, which is then distributed to coherent jurors (`testMajorityWinsAndGetsReward`, `testLoserGetsSlashed`, `testNonRevealerLosesStake`).

### 4.2 Testing 

The most significant achievement of this project is the test suite (`SimpleKlerosPhase3Test.sol`). 

**Scenarios Verified:**

- **The "Stale Stake" Bug:** We identified and fixed a logic error where the "total available stake" was not updating dynamically during the juror selection loop. In actual Kleros, the flow is slightly different as they don't update the total available stake because the token distribution is more sparse. We update the total available stake as it makes implementation easier for us, while making sure juror selection goes as expected. We have not yet identified any issues with our slight modification but the jury is still out on that. The fix is regression-tested in `testFix_StaleTotalStakeInDrawLoop` and `testFix_CorrectTotalStakeAfterMultipleSelections`.
- **The "Lazy Juror" Penalty:** We verified that jurors who commit but fail to reveal are penalized, ensuring liveness (`testNonRevealerLosesStake`).
- **Sybil Resistance:** We proved via testing that splitting tokens across multiple addresses yields no mathematical advantage (discussed in the next subsection) in selection probability compared to holding them in a single address, using a combination of `testWeightedSelectionFavorsHigherStakes`, `testWeightedSelectionWithMultipleRandomSeeds`, and `testFuzz_WeightedSelectionFavorsHigherStakes`.

##### NOTE : Test cases are discussed in more detail in the README.md. We draw our motivation for tests from actual Kleros v1 testing suite. 

#### Mathematical Explanation: Sybil Resistance in Weighted Selection

The selection mechanism in Kleros (and implemented in `SimpleKlerosPhase3`) is designed such that the probability of being selected as a juror is directly proportional to the amount of tokens a user has staked.

Let:

- $S_{\text{total}}$ be the total amount of tokens staked in the court by all jurors.  
- $S_A$ be the amount of tokens staked by a specific user (User A).  
- $n$ be the number of juror spots (draws) to be filled for a dispute.

The probability of User A being selected for **one specific draw** is:

$$
P(\text{User A selected}) = \frac{S_A}{S_{\text{total}}}
$$

Now, consider a Sybil attack scenario where User A splits their stake $S_A$ across $k$ different addresses (identities), denoted as $a_1, a_2, \dots, a_k$.  
Let $s_i$ be the stake in address $a_i$. Therefore:

$$
\sum_{i=1}^{k} s_i = S_A
$$

The probability of any specific address $a_i$ being selected for a single draw is:

$$
P(a_i \text{ selected}) = \frac{s_i}{S_{\text{total}}}
$$

The probability that **any** of User A's addresses is selected for that single draw is the sum of the probabilities of each individual address being selected (since the events are mutually exclusive for a single draw):

$$
P(\text{Any of User A's addresses selected}) = \sum_{i=1}^{k} P(a_i \text{ selected})
= \sum_{i=1}^{k} \frac{s_i}{S_{\text{total}}}
$$

Since the denominator $S_{\text{total}}$ is constant:

$$
P(\text{Any of User A's addresses selected}) 
= \frac{1}{S_{\text{total}}} \sum_{i=1}^{k} s_i
$$

Substituting $\sum_{i=1}^{k} s_i = S_A$:

$$
P(\text{Any of User A's addresses selected}) 
= \frac{S_A}{S_{\text{total}}}
$$


**Conclusion:** The probability of selection remains exactly $\frac{S_A}{S_{\text{total}}}$ regardless of whether the stake $S_A$ is held in one address or split across $k$ addresses. Splitting tokens increases the computational overhead (gas costs) for the attacker without providing any statistical advantage in being selected. This mathematical property underpins the Sybil resistance of the protocol and is empirically illustrated in the weighted-selection tests described above.

---

## 5. Gap Analysis

By simplifying the protocol, we exposed several pitfalls and deviations from the full Kleros specification (v1).

### 5.1 Lack of Appeal Mechanism (Critical Vulnerability)

**The Shortcoming:** Our prototype relies on a single round of voting. Once the `finalize` function is called, the ruling is permanent.

**The Consequence:** This makes the system highly vulnerable to bribery. An attacker only needs to bribe 51% of the small initial jury (e.g., 2 out of 3 jurors) to win permanently. In the full Kleros protocol, appeals are the primary defense against bribery. If a victim loses due to a bribed jury, they can pay an appeal fee to trigger a new round with a larger jury (e.g., 7, then 15, then 31 jurors). This raises the cost of bribery exponentially, eventually making it economically infeasible.

**The "Galileo" Problem:** Without appeals, the system also fails the "virtuous contrarian" case. If a juror holds a correct but unpopular view (like Galileo), they are simply slashed in our single-round system. An appeal system would allow truth to eventually prevail as the jury pool expands.

### 5.2 Scalability and Gas Optimization

**The Problem:** Our implementation uses a linear loop (`O(n)`) to select jurors and a linear loop to redistribute tokens. As the number of jurors increases, the gas cost to process a dispute creates a bottleneck, potentially exceeding the Ethereum block gas limit.

**The Kleros Solution:** The actual Kleros contract utilizes a Sortition Sum Tree data structure. This allows for drawing jurors in `O(log n)` time, making the system scalable to thousands of jurors. We did not implement this data structure due to its complexity, but the linear behavior and its limits can be observed indirectly by running the higher-verbosity test configurations described in the README.

### 5.3 The Alpha Parameter vs. 100% Slashing

**Current Implementation:** In our code, if a juror votes incorrectly, they lose 100% of the stake locked for that specific dispute.

**The Pitfall:** This is too punitive. It discourages participation because an honest mistake results in a total loss of the staked amount.

**The Standard Spec:** The Kleros Yellowpaper defines a parameter α (Alpha). The amount lost is defined as `D = α × min_stake × weight`. This allows the governance system to tune the penalty (e.g., jurors might only lose 20% of their stake for an incorrect vote), balancing incentive security with participation safety. The current “full slashing” behavior is visible in `testLoserGetsSlashed` and `testNonRevealerLosesStake`.

### 5.4 Arbitration Fees

**Status:** Not Implemented.

**Impact:** Our system relies solely on token redistribution (internal economic game). We did not implement the flow of ETH (Arbitration Fees) from the disputing parties to the jurors. In a production environment, this is critical because token redistribution alone is a zero-sum game among jurors; external fees are required to make honest work net-profitable. Also, if everyone is in majority then there will be no incentive to work with, which might fail some assertions in the test cases. We have written our test cases keeping that in mind – for example, `testMajorityWinsAndGetsReward` and `testCanUnstakeAfterDispute` focus on stake movement, not on external fee flows.

### 5.5 Randomness Generation

**Current Implementation:** We used `blockhash` for Random Number Generation (RNG).

**The Pitfall:** As noted in the Kleros Whitepaper, miners can manipulate blockhashes by withholding blocks that produce unfavorable outcomes.

**The Standard Spec:** A production-ready system requires a more robust RNG, such as Sequential Proof-of-Work or Verifiable Delay Functions (VDFs). Our test suite explores different block/environment configurations (`vm.roll`, `vm.warp`) in `testWeightedSelectionFavorsHigherStakes`, `testWeightedSelectionWithMultipleRandomSeeds`, and `testFuzz_WeightedSelectionFavorsHigherStakes`, which makes the dependence on blockhash-based randomness explicit.

### 5.6 Rounding Errors in Token Redistribution

- **The Issue:** When redistributing slashed tokens to coherent jurors, we use integer division:  
  `reward = (totalSlashed * jurorWeight) / totalWinnerWeight`.  
  In Solidity, this operation truncates the decimal remainder.

- **The Scenario:** Consider a dispute with 3 jurors where 1 incoherent juror is slashed for 100 tokens. The 2 coherent jurors have equal weight (1 vote each). The reward calculation is `100 * 1 / 2 = 50`. Both winners get 50 tokens, and 0 tokens are left over. However, if the slashed amount was 101 tokens, `101 / 2 = 50`. Each winner gets 50, and 1 token remains stuck in the contract (`101 - 50 - 50 = 1`).

- **Impact:** Over time, these "dust" tokens accumulate in the contract balance, effectively burned from circulation unless a sweep mechanism is implemented. In our simplified implementation, we did not include logic to send this dust to a governance treasury or distribute it to the dispute creator, which is a minor economic inefficiency. This behavior can be seen in practice when inspecting balances during reward-distribution tests such as `testMajorityWinsAndGetsReward` and `testLoserGetsSlashed`.

### 5.7 Handling TIE events 

**Example:** We have 7 jurors, one of them decides to not reveal its vote, so we have only 6 votes now. Say, we get 3 "yes" and 3 "no" , in this case it is a tie. In such a case , **Option 0** is considered a solution and we usually give the jurors their stake back.

#### Summary of Actual Kleros Behavior in this Edge Case:

- **Ruling:** Option 0 (Refuse to Arbitrate).
- **Juror 1:** Penalized (slashed) for not revealing.
- **Jurors 2–7:**
  - They voted for 1 or 2. The winner is 0.
  - They are technically incoherent.
  - However, since *no one* won (no coherent jurors), they usually just get their stake back (minus arbitration fees in some versions, or simply net zero change in stake).
- The slashed tokens from Juror 1 go to the **Governance Treasury**.

#### Our implementation

Since we have no **Governance Treasury** , we just revert the stake. The key behaviors around ties and “everyone silent” cases are exercised in `testTieNoRedistribution` (single-juror / trivial tie handling) and `testTieResultsInUndecided` (0 vs 0 votes → Undecided with all stakes returned).


### Why This Matters

This mechanism is crucial for fairness. It ensures that:

1. **Liveness is Enforced:** Jurors are strongly incentivized to reveal their votes; otherwise, they lose money.  This is enforced in `testNonRevealerLosesStake` and by the timing tests (`testCannotRevealAfterDeadline`, `testCannotFinalizeBeforeRevealDeadline`).
2. **Genuine Disagreement is not Punished:** If the case is truly ambiguous or the jury is perfectly split, honest jurors are not slashed for voting their conscience, even if they didn't pick the "winning" side (which turned out to be a tie). This is reflected in `testTieResultsInUndecided`, where stakes are returned on a true tie.

### 5.8 Security and Governance

We have not performed a security audit on the simplified contracts. Additionally, the system currently lacks the liquid governance mechanism described in the whitepaper, meaning parameters like `minStake` or `alpha` cannot be adjusted by the community without redeploying the contract. Access-control–style checks (for example, "only jurors can vote/reveal") and basic sanity constraints are validated by tests such as `testNonJurorCannotCommit`, `testNonJurorCannotReveal`, `testCannotCommitAfterDeadline`, and `testCannotDrawJurorsTwice`, but these are not a substitute for a full audit or on-chain governance.

---

## 6. Challenges faced 

Adversarial approach to game theoretic systems was something we needed some time, effort and intuition for. Unlike other adversarial SOPs, there were very few resources we could refer to. Since we were understanding and simplifying the protocol, it was imperative that we enumerate the tradeoffs associated with such an endeavour.

Even with bugs the system would seem to function, a good example for it will be `testFix_StaleTotalStakeInDrawLoop` in the testing suite. The output would recommend that our code is working alright, till we decided to tally the total tokens with total stake in the system + remaining tokens. Such errors were encountered regularly and honestly we won't be surprised if more such errors show up. We have found some errors and fixed them and wrote tests from them starting with `testFix_`. It is like solving probability puzzles, just like any Turing complete software. It is immensely hard to create an exhaustive testing suite.

We also are not sure how to hedge against a single juror getting picked all the time. It is a low probability event and we tried to fuzz test to get such a case but we didn't get it, in all honesty we didn't try that hard for that as well. The theoretical proof itself is unequivocal. We did a lot of brainstorming on such issues that occur due to the inherent design of the system. We had to understand that the point of such systems is to prevent really bad things from happening, not to always converge at an optimal solution. Even if it is a near optimal solution, it is alright. Implementing that mindset into our critical thinking while simplifying the protocol was crucial but took a while to converge at. 

---

## References

1. **Kleros Whitepaper** - Clément Lesaege, Federico Ast, and William George (September 2019)  
   [https://kleros.io/whitepaper.pdf](https://kleros.io/whitepaper.pdf)

2. **Kleros Yellowpaper** - Technical specification and implementation details  
   [https://kleros.io/yellowpaper.pdf](https://kleros.io/yellowpaper.pdf)

3. **Kleros Smart Contracts** - Official Kleros contract implementations on GitHub  
   [https://github.com/kleros/kleros/blob/master/contracts/kleros/](https://github.com/kleros/kleros/blob/master/contracts/kleros/)

