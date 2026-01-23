# Shutter DAO 0x36 × Octant v2 Integration Plan


## Overview

Shutter DAO 0x36 will integrate with Octant v2 through the **SHUGrantPool Strategy** — an ERC-4626 yield-donating vault configured with Morpho's "Steakhouse" USDC yield strategy (rated A+ by Credora, ~4-6% APY).

| Component | Purpose | Capital |
|-----------|---------|---------|
| SHUGrantPool Strategy | Generate yield for public goods funding | 1.2M USDC |

> **Architecture Note**: The strategy IS the ERC-4626 vault. No MultistrategyVault wrapper is needed since only one strategy is approved by the DAO. This simplifies deployment, reduces gas costs, and eliminates unnecessary complexity.

---

## Prerequisites

The following items have been resolved for the DAO proposal:

| Item | Status | Address | Notes |
|------|--------|---------|-------|
| Dragon Funding Pool | Resolved | [`0x4B4505dEdE6408642511Fc0586b62676111e4904`](https://etherscan.io/address/0x4B4505dEdE6408642511Fc0586b62676111e4904) | Strategy donation recipient |
| Keeper Bot | Resolved | [`0x06c2c4dB3776D500636DE63e4F109386dCBa6Ae2`](https://etherscan.io/address/0x06c2c4dB3776D500636DE63e4F109386dCBa6Ae2) (pluch.eth) | Strategy keeper for harvesting |
| Emergency Shutdown Admin | Resolved | [`0x36bD3044ab68f600f6d3e081056F34f2a58432c4`](https://etherscan.io/address/0x36bD3044ab68f600f6d3e081056F34f2a58432c4) | Treasury - can shutdown strategy and perform emergency withdrawals |

### Deployed Contracts

The proposal uses **V1 contracts**:

| Contract | Address |
|----------|---------|
| MorphoCompounderStrategyFactory | [`0x052d20B0e0b141988bD32772C735085e45F357c1`](https://etherscan.io/address/0x052d20B0e0b141988bD32772C735085e45F357c1) |
| YieldDonatingTokenizedStrategy | [`0xb27064A2C51b8C5b39A5Bb911AD34DB039C3aB9c`](https://etherscan.io/address/0xb27064A2C51b8C5b39A5Bb911AD34DB039C3aB9c) |

---

## Verified On-Chain Addresses

| Entity | Address | Network |
|--------|---------|---------|
| Shutter DAO Treasury | [`0x36bD3044ab68f600f6d3e081056F34f2a58432c4`](https://etherscan.io/address/0x36bD3044ab68f600f6d3e081056F34f2a58432c4) | Ethereum |
| Azorius Module | [`0xAA6BfA174d2f803b517026E93DBBEc1eBa26258e`](https://etherscan.io/address/0xAA6BfA174d2f803b517026E93DBBEc1eBa26258e) | Ethereum |
| SHU Token | [`0xe485E2f1bab389C08721B291f6b59780feC83Fd7`](https://etherscan.io/token/0xe485E2f1bab389C08721B291f6b59780feC83Fd7) | Ethereum |
| USDC | [`0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48`](https://etherscan.io/token/0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48) | Ethereum |
| Morpho Strategy Factory | [`0x052d20B0e0b141988bD32772C735085e45F357c1`](https://etherscan.io/address/0x052d20B0e0b141988bD32772C735085e45F357c1) | Ethereum |
| Tokenized Strategy | [`0xb27064A2C51b8C5b39A5Bb911AD34DB039C3aB9c`](https://etherscan.io/address/0xb27064A2C51b8C5b39A5Bb911AD34DB039C3aB9c) | Ethereum |
| Yearn Strategy USDC | [`0x074134A2784F4F66b6ceD6f68849382990Ff3215`](https://etherscan.io/address/0x074134A2784F4F66b6ceD6f68849382990Ff3215) | Ethereum |

---

## Part 1: SHUGrantPool Strategy

The MorphoCompounderStrategy is itself an ERC-4626 vault (via Yearn's TokenizedStrategy). Treasury deposits USDC directly into the strategy.

### Underlying Yield Source

[**Yearn Strategy USDC**](https://etherscan.io/address/0x074134A2784F4F66b6ceD6f68849382990Ff3215) — Deposits into Morpho lending markets via Yearn's aggregator vault.

The `MorphoCompounderStrategyFactory` at [`0x052d20B...`](https://etherscan.io/address/0x052d20B0e0b141988bD32772C735085e45F357c1) deploys strategies that target the Yearn Strategy USDC vault, which optimizes across Morpho lending markets.


### Role Assignments

| Role | Assigned To | Description |
|------|-------------|-------------|
| **Management** | Shutter DAO Treasury (`0x36bD...32c4`) | Administrative role (set keeper, set emergency admin, shutdown) |
| **Keeper** | Dedicated Bot/EOA | **REQUIRED**: Authorized to call `report()`/`tend()` to harvest yields without governance votes |
| **Emergency Admin** | Shutter DAO Treasury (`0x36bD...32c4`) | Can shutdown the strategy and perform emergency withdrawals |

> **Critical**: The Keeper should be a dedicated EOA or bot, NOT the Treasury Safe. Assigning Keeper to Treasury would require a governance vote (72-hour voting + 72-hour execution = 144 hours minimum) for every harvest, creating severe operational bottlenecks that defeat the purpose of automated yield generation.

### Yield Distribution

| Destination | Allocation |
|-------------|------------|
| Dragon Funding Pool | 100% |

---

## Shutter DAO Governance

### Architecture

Shutter DAO 0x36 uses **Fractal (Decent)** for on-chain governance, built on Safe:

| Component | Address / Value |
|-----------|-----------------|
| Safe (Treasury) | [`0x36bD3044ab68f600f6d3e081056F34f2a58432c4`](https://etherscan.io/address/0x36bD3044ab68f600f6d3e081056F34f2a58432c4) |
| Azorius Module | [`0xAA6BfA174d2f803b517026E93DBBEc1eBa26258e`](https://etherscan.io/address/0xAA6BfA174d2f803b517026E93DBBEc1eBa26258e) |
| Voting Token | SHU ([`0xe485E2f1bab389C08721B291f6b59780feC83Fd7`](https://etherscan.io/token/0xe485E2f1bab389C08721B291f6b59780feC83Fd7)) |

### Execution Call Chain

When a proposal passes and is executed, the call flow is:

```
┌──────────────────────────────────────────────────────────────────────────┐
│  Step 1: Any EOA calls Azorius to execute passed proposal                │
│          executeProposal(proposalId)                                     │
│                           │                                              │
│                           ▼                                              │
│  ┌────────────────────────────────────────────────────────────────────┐  │
│  │  Azorius Module (0xAA6BfA174d2f803b517026E93DBBEc1eBa26258e)       │  │
│  └────────────────────────────────────────────────────────────────────┘  │
│                           │                                              │
│  Step 2: Azorius calls Safe via module interface                         │
│          execTransactionFromModule(to, value, data, operation)           │
│                           │                                              │
│                           ▼                                              │
│  ┌────────────────────────────────────────────────────────────────────┐  │
│  │  DAO Safe / Treasury (0x36bD3044ab68f600f6d3e081056F34f2a58432c4)  │  │
│  └────────────────────────────────────────────────────────────────────┘  │
│                           │                                              │
│  Step 3: Safe executes transaction to target contract                    │
│          msg.sender = Safe (0x36bD...)                                   │
│                           │                                              │
│                           ▼                                              │
│  ┌────────────────────────────────────────────────────────────────────┐  │
│  │  Target Contract (Factory / USDC / Strategy)                       │  │
│  └────────────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────────┘
```

> **Critical**: From the target contract's perspective, `msg.sender` is the **Safe address** (`0x36bD...`), NOT the Azorius module. This is why all roles (`management`, `keeper`, `emergencyAdmin`) are assigned to the Treasury Safe address.

### Governance Parameters

See current governance parameters on the [Decent DAO App](https://app.decentdao.org/home?dao=eth%3A0x36bD3044ab68f600f6d3e081056F34f2a58432c4).

### Voting Platforms

| Platform | Type | Use Case |
|----------|------|----------|
| [Decent](https://app.decentdao.org/home?dao=eth%3A0x36bD3044ab68f600f6d3e081056F34f2a58432c4) | On-chain | Treasury transactions, contract interactions |
| [Snapshot](https://snapshot.org/#/shutterdao0x36.eth) | Off-chain | Temperature checks, non-binding polls |

Shutter DAO also supports **Shielded Voting** on Snapshot, which encrypts votes until the voting period ends to prevent manipulation.

---

## Execution Playbook

### Phase 1: Strategy Deployment

If CREATE2 prediction is verified (see tests below), the deployment can be executed in a **single DAO proposal** with **1 batched MultiSend** containing 3 operations:
1. Deploy Strategy via Factory
2. Approve USDC to Strategy (uses precomputed Strategy address)
3. Deposit USDC into Strategy

**CREATE2 Address Prediction**: The script uses CREATE2 to precompute the strategy address, enabling batched execution. The script automatically verifies this prediction by simulating deployment on a mainnet fork and comparing bytecode. If verification fails, the script aborts with an error - ensuring calldata is never generated with an incorrect address.

> **MultiSend requirement**: Execute MultiSend with `operation=DELEGATECALL` (Azorius `execTransactionFromModule(..., operation=1)`). Using CALL makes `msg.sender` the MultiSend contract and will break USDC approvals.
>
> **UI Limitation**: The Safe UI may not support DELEGATECALL directly. Use the Transaction Builder or submit raw transactions via the Azorius module.

<details>
<summary><strong>Fallback: Individual Transactions (if DELEGATECALL batching unavailable)</strong></summary>

If the Decent UI doesn't support DELEGATECALL batching, submit as **3 individual transactions** in a single proposal:

| TX | Target | Function | Notes |
|----|--------|----------|-------|
| 0 | MorphoCompounderStrategyFactory | `createStrategy(name, symbol, mgmt, keeper, admin, donationAddr, false, tokenizedStrategy)` | Returns Strategy address |
| 1 | USDC | `approve(strategyAddress, amount)` | Use Strategy address from TX 0 |
| 2 | Strategy | `deposit(amount, treasury)` | Deposits treasury USDC |

Each transaction uses `operation=0` (CALL). The Decent UI should support adding multiple transactions to a single proposal.

</details>

#### Step 1: Create Fractal Proposal (UI Walkthrough)

**1.1 — Navigate to Shutter DAO on Decent**

Open [app.decentdao.org/home?dao=eth:0x36bD3044ab68f600f6d3e081056F34f2a58432c4](https://app.decentdao.org/home?dao=eth%3A0x36bD3044ab68f600f6d3e081056F34f2a58432c4)

**1.2 — Connect Wallet**

Connect a wallet holding SHU tokens (required to meet proposal threshold).

**1.3 — Click "Create Proposal"**

Navigate to the Proposals tab and click the "Create Proposal" button.

**1.4 — Fill Proposal Details**

| Field | Value |
|-------|-------|
| Title | `Deploy Octant SHUGrantPool Strategy and Deposit 1.2M USDC` |
| Description | See [Proposal Template](#proposal-template) below |

**1.5 — Add Transaction 1: Deploy Strategy**

| Field | Value |
|-------|-------|
| Target Contract | [`0x052d20B0e0b141988bD32772C735085e45F357c1`](https://etherscan.io/address/0x052d20B0e0b141988bD32772C735085e45F357c1) (Morpho Strategy Factory) |
| Function | `createStrategy(string,address,address,address,address,bool,address)` |
| `_name` | `SHUGrantPool` |
| `_management` | [`0x36bD3044ab68f600f6d3e081056F34f2a58432c4`](https://etherscan.io/address/0x36bD3044ab68f600f6d3e081056F34f2a58432c4) |
| `_keeper` | [`0x06c2c4dB3776D500636DE63e4F109386dCBa6Ae2`](https://etherscan.io/address/0x06c2c4dB3776D500636DE63e4F109386dCBa6Ae2) (pluch.eth) |
| `_emergencyAdmin` | [`0x36bD3044ab68f600f6d3e081056F34f2a58432c4`](https://etherscan.io/address/0x36bD3044ab68f600f6d3e081056F34f2a58432c4) |
| `_donationAddress` | [`0x4B4505dEdE6408642511Fc0586b62676111e4904`](https://etherscan.io/address/0x4B4505dEdE6408642511Fc0586b62676111e4904) |
| `_enableBurning` | `false` |
| `_tokenizedStrategyAddress` | [`0xb27064A2C51b8C5b39A5Bb911AD34DB039C3aB9c`](https://etherscan.io/address/0xb27064A2C51b8C5b39A5Bb911AD34DB039C3aB9c) |

> **Note**: The strategy IS the ERC-4626 vault. No additional vault wrapper is needed.

**1.6 — Add Transaction 2: Approve USDC**

| Field | Value |
|-------|-------|
| Target Contract | [`0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48`](https://etherscan.io/token/0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48) (USDC) |
| Function | `approve(address spender, uint256 amount)` |
| `spender` | `[PREDICTED_STRATEGY_ADDRESS]` *(CREATE2 prediction, verified on fork)* |
| `amount` | `1200000000000` (1.2M USDC) |

**1.7 — Add Transaction 3: Deposit USDC**

| Field | Value |
|-------|-------|
| Target Contract | `[PREDICTED_STRATEGY_ADDRESS]` *(CREATE2 prediction, verified on fork)* |
| Function | `deposit(uint256 assets, address receiver)` |
| `assets` | `1200000000000` (1.2M USDC) |
| `receiver` | [`0x36bD3044ab68f600f6d3e081056F34f2a58432c4`](https://etherscan.io/address/0x36bD3044ab68f600f6d3e081056F34f2a58432c4) |

**1.8 — Submit Proposal**

Review all details and click "Submit Proposal". Sign the transaction with your wallet.

> ✅ **Gas Verified**: The batched proposal (1 MultiSend with 3 operations) uses minimal gas - well under the 16.7M per-transaction limit (EIP-7825). See `ShutterDAOGasProfilingTest` for details.

### Gas Profile

| Component | Gas Cost |
|-----------|----------|
| **DAO Proposal (1 batched call, 3 operations)** | **~1M** |
| **EIP-7825 Limit** | 16,777,216 |
| **Headroom** | >92% |

*Note: Direct strategy deposits (no vault wrapper) and batched execution minimize gas costs.*

#### Step 2: Vote

1. Share the proposal link on the [Shutter Forum](https://shutternetwork.discourse.group/) for discussion
2. SHU holders vote during the voting period
3. Proposal passes if quorum is met and majority votes "For"

#### Step 3: Execute

Once the voting period ends and the proposal passes:

1. Return to the proposal page on Decent
2. Click "Execute" (available during the execution window)
3. Sign the execution transaction
4. Verify on Etherscan that all transactions succeeded

#### Step 4: Verify Deployment

After execution, verify:

- [ ] Strategy deployed with correct donation address (Dragon Funding Pool)
- [ ] Treasury received strategy shares
- [ ] USDC deposited and earning yield in Morpho markets

### Proposal Template

```markdown
## Summary

This proposal deploys the Octant SHUGrantPool Strategy and deposits
1,200,000 USDC from Shutter DAO 0x36 treasury as part of the Octant v2 pilot.

## Background

Octant v2 enables DAOs to optimize treasury yield while funding public goods.
See: [Octant v2 Pilot Proposal](https://shutternetwork.discourse.group/t/octant-v2-pilot-to-optimize-treasury-strengthen-ecosystem/760)

## Transactions (3 total)

1. **Deploy Strategy**: Create ERC-4626 yield-donating strategy (yield → Dragon Funding Pool)
2. **Approve USDC**: Allow Strategy to spend 1.2M USDC
3. **Deposit USDC**: Deposit 1.2M USDC, receiving shares to Treasury

## Architecture

The MorphoCompounderStrategy IS the ERC-4626 vault (via Yearn's TokenizedStrategy).
No additional vault wrapper is needed since only one strategy is approved by the DAO.

## Yield Distribution

- 100% → Dragon Funding Pool (Shutter ecosystem grants)

## Risk Considerations

- Underlying: Yearn Strategy USDC (deposits into Morpho lending markets)
- Custody: Treasury retains full share ownership
- Liquidity: Instant withdrawals (no lockup period)

## Links

- [Yearn Strategy USDC](https://etherscan.io/address/0x074134A2784F4F66b6ceD6f68849382990Ff3215)
- [Morpho Strategy Factory](https://etherscan.io/address/0x052d20B0e0b141988bD32772C735085e45F357c1)
- [YieldDonatingTokenizedStrategy](https://etherscan.io/address/0xb27064A2C51b8C5b39A5Bb911AD34DB039C3aB9c)
```

### Prepared Calldata

Complete transaction calldata can be generated programmatically using the provided script:

```bash
forge script partners/shutter_dao_0x36/script/GenerateProposalCalldata.s.sol --fork-url $ETH_RPC_URL -vvvv
```

**Configuration:** Update the constants at the top of the script:
- `SHUTTER_TREASURY` — Treasury Safe address
- `DRAGON_FUNDING_POOL` — Yield recipient address
- `KEEPER_BOT` — Keeper address for report() calls
- `STRATEGY_NAME` — Strategy name (V1 does not use symbol)
- `DEPOSIT_AMOUNT` — USDC deposit amount

**Output:** The script:
1. Predicts the strategy address using CREATE2
2. Verifies prediction by simulating deployment on the fork
3. Fails if bytecode mismatch detected
4. Outputs batched MultiSend calldata for governance proposal

> **Manual Reference**: The transaction parameters below can be used for UI-based proposal creation.

---

### Transaction 1: Deploy Strategy

```
Target:   0x052d20B0e0b141988bD32772C735085e45F357c1 (Morpho Strategy Factory)
Function: createStrategy(string,address,address,address,address,bool,address)
Selector: 0x31d89943
Value:    0

Parameters:
  _name:                     "SHUGrantPool"
  _management:               0x36bD3044ab68f600f6d3e081056F34f2a58432c4
  _keeper:                   0x06c2c4dB3776D500636DE63e4F109386dCBa6Ae2
  _emergencyAdmin:           0x36bD3044ab68f600f6d3e081056F34f2a58432c4
  _donationAddress:          0x4B4505dEdE6408642511Fc0586b62676111e4904
  _enableBurning:            false
  _tokenizedStrategyAddress: 0xb27064A2C51b8C5b39A5Bb911AD34DB039C3aB9c
```

### Transaction 2: Approve USDC

```
Target:   0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48 (USDC)
Function: approve(address,uint256)
Selector: 0x095ea7b3
Value:    0

Parameters:
  spender: [PREDICTED_STRATEGY_ADDRESS] (CREATE2 prediction, verified on fork)
  amount:  1200000000000 (1.2M USDC with 6 decimals)
```

### Transaction 3: Deposit USDC

```
Target:   [PREDICTED_STRATEGY_ADDRESS] (CREATE2 prediction, verified on fork)
Function: deposit(uint256,address)
Selector: 0x6e553f65
Value:    0

Parameters:
  assets:   1200000000000 (1.2M USDC with 6 decimals)
  receiver: 0x36bD3044ab68f600f6d3e081056F34f2a58432c4 (Treasury)
```

---

## Post-Deployment Operations

#### Harvest Operation

**Report (Harvest Yield)**

```
Target:   [STRATEGY_ADDRESS]
Function: report()
Selector: 0x2606a10b
Value:    0

Parameters: (none)

Note: Called by management or keeper to harvest yield. Returns (uint256 profit, uint256 loss).
```

---

### Emergency Operations

**Shutdown Strategy**

```
Target:   [STRATEGY_ADDRESS]
Function: shutdownStrategy()
Selector: 0xbe8f1668
Value:    0

Parameters: (none)

Effect: Stops new deposits/mints, allows withdrawals, still allows tend/report.
Access:  management or emergencyAdmin
```

**Emergency Withdraw**

```
Target:   [STRATEGY_ADDRESS]
Function: emergencyWithdraw(uint256)
Selector: 0x5312ea8e
Value:    0

Parameters:
  _amount: Amount to withdraw (up to full balance)

Prerequisite: Strategy must be shutdown first.
Access:       management or emergencyAdmin
```

---

### Quick Reference: Function Selectors

| Function | Selector | Target | Purpose |
|----------|----------|--------|---------|
| `createStrategy(...)` | `0x31d89943` | Morpho Factory | Deploy strategy |
| `approve(address,uint256)` | `0x095ea7b3` | USDC | Allow spending |
| `deposit(uint256,address)` | `0x6e553f65` | Strategy | Deposit funds |
| `withdraw(uint256,address,address)` | `0xb460af94` | Strategy | Withdraw funds |
| `report()` | `0x2606a10b` | Strategy | Harvest yield |
| `shutdownStrategy()` | `0xbe8f1668` | Strategy | Emergency shutdown |
| `emergencyWithdraw(uint256)` | `0x5312ea8e` | Strategy | Emergency exit |

---

## Operational Considerations

### Keeper Setup

See [Role Assignments](#role-assignments) for Keeper requirements. A dedicated EOA or bot enables autonomous harvesting without governance votes.

### Emergency Admin

The Treasury serves as Emergency Admin. Emergency actions (shutdown, forced withdrawals) will follow standard DAO voting timelines unless a separate multisig is designated for faster response.

### Withdrawals

The strategy provides instant liquidity (no lockup). Withdrawals are straightforward:
1. Call `withdraw(assets, receiver, owner)` or `redeem(shares, receiver, owner)` on the strategy
2. Receive underlying USDC immediately

The strategy will automatically unwind positions in Morpho markets as needed.

---

## Risk Disclosure

### Emergency Withdrawal Loss Acceptance

The strategy accepts up to 100% loss on emergency withdrawals via the `emergencyWithdraw()` function
(`maxLoss = 10000 BPS`), callable only by the Emergency Admin (`emergencyAdmin` role).
This emergency `maxLoss` value is hardcoded in the strategy contract and cannot be
modified post-deployment by the Emergency Admin or any other party. This is necessary because:

- Underlying Yearn/Morpho vaults may have temporary unrealized losses during market stress
- Emergency admin can always withdraw, even at a loss, rather than being locked out
- This ensures the Treasury is never permanently locked in the strategy

Normal withdrawals through `withdraw()` default to `maxLoss = 0`, reverting if any loss would occur.
Redemptions through `redeem()` default to `maxLoss = MAX_BPS` (accepts any loss). Users can specify
explicit `maxLoss` parameters when calling the 4-argument versions of these functions.

### Dependency Chain

Yield flows through a multi-layer dependency chain:

```
Treasury USDC
    |
    v
MorphoCompounderStrategy (SHUGrantPool)
    |
    v
Yearn Strategy USDC (0x074134A2784F4F66b6ceD6f68849382990Ff3215)
    |
    v
Morpho "Steakhouse" USDC Vault
    |
    v
Morpho Lending Markets
```

**Risk implications:**
- Smart contract risk across all layers (Octant, Yearn, Morpho)
- Morpho market risk (borrower defaults, liquidation delays)
- Oracle risk (price feed failures affecting Morpho)
- Yearn operational risk (strategy mismanagement)

The Treasury accepts these layered risks in exchange for optimized yield (~4-6% APY).

### Failure Mode Analysis

| Failure Mode | Impact | Recovery |
|--------------|--------|----------|
| CREATE2 address prediction mismatch | Proposal fails atomically (batched mode) | Script aborts; re-verify factory bytecode or use UI-based manual transactions |
| Azorius rejects DELEGATECALL | Batched proposal fails | Use 3 separate transactions |
| Yearn vault shutdown | Deposit reverts | USDC stays in Treasury, no loss |
| Morpho market pause | Withdrawals delayed | Wait for unpause or accept loss |
| Strategy keeper offline | Yield not harvested | Management can call report() |

**No permanent fund loss scenarios identified** - all failure modes are recoverable.

### Fallback: Separate Transactions

> **Note**: This is a **UI-based manual alternative**, not a script-generated fallback. The `GenerateProposalCalldata.s.sol` script only generates batched MultiSend calldata. If batching fails, use the Decent UI to manually create individual transactions.

If the DAO UI (Decent/Fractal) doesn't support DELEGATECALL batching, the proposal can be executed as 3 separate transactions:

1. **TX 1: Deploy Strategy**
   - Target: MorphoCompounderStrategyFactory
   - Note the returned strategy address from transaction logs

2. **TX 2: Approve USDC**
   - Target: USDC
   - Spender: Strategy address from TX 1

3. **TX 3: Deposit USDC**
   - Target: Strategy address from TX 1
   - Receiver: Treasury

Each transaction must be executed sequentially and approved separately through DAO governance.

See `partners/shutter_dao_0x36/test/ShutterDAOCalldataVerification.t.sol` for verification tests that cover both execution paths.

---

## Verification Scripts

### Pre-Submission Verification

Run the calldata verification test before submitting the DAO proposal:

```bash
ETH_RPC_URL=<mainnet-rpc> forge test --match-contract ShutterDAOCalldataVerification -vvv
```

This verifies:
- CREATE2 predicted address matches actual factory deployment (required for batched mode)
- Batched MultiSend calldata executes successfully (batched mode)
- 3-transaction fallback works if needed

### Post-Execution Verification

After the DAO executes the proposal:

```bash
forge script partners/shutter_dao_0x36/script/VerifyProposalExecution.s.sol \
  --fork-url $ETH_RPC_URL -vvvv
```

This verifies:
- Strategy deployed at expected address
- Treasury holds expected shares (~1.2M)
- Dragon Funding Pool set as yield recipient
- Keeper configured correctly
- Management roles assigned to Treasury

---

## References

- [Shutter DAO Blueprint](https://blog.shutter.network/a-proposed-blueprint-for-launching-a-shutter-dao/)
- [Octant v2 Pilot Proposal (Forum)](https://shutternetwork.discourse.group/t/octant-v2-pilot-to-optimize-treasury-strengthen-ecosystem/760)
- [Yearn Strategy USDC (Etherscan)](https://etherscan.io/address/0x074134A2784F4F66b6ceD6f68849382990Ff3215)
- [Shutter DAO Governance (Fractal/Decent)](https://app.decentdao.org/home?dao=eth%3A0x36bD3044ab68f600f6d3e081056F34f2a58432c4)
- [Shutter DAO Treasury (Etherscan)](https://etherscan.io/address/0x36bD3044ab68f600f6d3e081056F34f2a58432c4)
