# Duel

Duel is a decentralized smart contract system that allows two participants (Player A and Player B) to create and engage in structured, blockchain-based duels or bets. Each duel has options for funding either side, a funding period, and a judge or mutual agreement mechanism for deciding the outcome. Users fund their chosen side by sending ether to the respective option, and the outcome is determined based on a set duration and decision criteria. If successful, the winner receives the funds. Duel offers a fair and transparent approach to competitive interactions with verifiable, on-chain results.


## Duel Lifecycle: Creation, Funding, Decision, and Payout

### 1. Duel Creation

**Player A initiates a duel by calling createDuel on the DuelFactory contract with the following parameters:**
* title: Title of the duel.
* payoutA: Address for Player A’s payout if they win.
* playerB: Address of the challenger (Player B).
* amount: Target funding amount for each option, in wei.
* fundingDuration: Duration (in seconds) for the funding period.
* decisionLockDuration: Duration (in seconds) of the lock period before a decision can be made.
* judge: Address of the judge (optional, can be zero address if not needed).

**Contracts Deployed:** 
* Duel: The main contract containing duel logic.
* Two DuelOption contracts: One for each side (Option A and Option B).

### 2. Funding Period

**Funding begins for both DuelOption contracts. Any user can fund either option by sending ether, up to the target amount.**
* Funding:
Users fund an option by sending ether directly to the DuelOption contract. Each funder’s balance is recorded in balances.
* Acceptance Requirements:
    * Function: playerBAccept in Duel.
        * Player B accepts the duel by calling playerBAccept, specifying their payout address (_payoutB) and sending the required ether to fund their side.
    * Parameters:
        * _payoutB: Address where Player B’s payout should be sent if they win. Must include the specified amount in ether.
    * Function: judgeAccept in Duel.
        * The judge accepts their role in the duel by calling judgeAccept.
        * This function is accessible only to the assigned judge during the funding period.
* Expiration: If either DuelOption fails to reach the funding target by fundingDuration, or if Player B or the judge does not accept the duel, the duel expires. Funders can reclaim their contributions by calling claimFunds on their respective DuelOption contracts.
    * Function: claimFunds in DuelOption.
        * Allows a funder to reclaim their contribution if the duel expires without a winner.
        * Checks if the associated Duel contract is marked as expired before releasing funds.

### 3. Decision Period

**After the decisionLockDuration ends, the judge or players can declare a winner:**

* Function: judgeDecide in Duel
    * The judge calls judgeDecide to decide the winner, specifying the winning option (_winner). This function is accessible only to the judge during the decision period.
    * Parameters:
    * _winner: Address of the winning option contract (either Option A or Option B).
* Function: playersAgree in Duel
    * If there is no judge, Players A and B can agree on the winner by calling playersAgree. Both players must agree on the same option for the duel to be completed.
    * Parameters:
        * _winner: Address of the agreed-upon winning option contract (either Option A or Option B).

* Expiration:
    * If neither a judge decision nor a player agreement is made within the decision period (decisionLockDuration + fundingDuration), the duel expires.
    * Funders of each DuelOption can call claimFunds to retrieve their contributions.


## Built With:

Framework: [Foundry](https://book.getfoundry.sh/)
Language: [Solidity](https://soliditylang.org/)
Smart Contracts Libraries & Operations: [OpenZeppelin](https://openzeppelin.com/)


## Getting Started

**Prerequisites**

* Foundry: Duel uses [Foundry](https://book.getfoundry.sh/) for development and testing. Please install Foundry if you haven’t already.
* Makefile: The provided Makefile simplifies common development commands for easier use.

**Installation**

1. Clone the repository:

```
git clone https://github.com/En-Garde-Labs/duel-smart-contracts
cd duel
```

2. Install Foundry dependencies

```
forge install
```

3. Compile contracts

```
forge build
```

4. Run tests

```
forge test -vvv
```

**Makefile usage**

1. Run tests

```
make test_factory
make test_duel
make test_option
```

2. Deploy implementation

```
make deploy_duel_base_sepolia
```

2. Change implementation address in /script/DeployFactory.s.sol and deploy Factory

```
make deploy_factory_base_sepolia
```

These two commands will trigger the approval process in [OpenZeppelin's Defender dashboard](https://defender.openzeppelin.com/#/deploy/).