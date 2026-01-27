# GenerateProposalCalldata Script

Generates calldata for a Nouns DAO proposal to deploy and fund a Lido yield skimming strategy.

## Usage

```bash
forge script partners/nouns_dao/script/GenerateProposalCalldata.s.sol \
  --fork-url $ETH_RPC_URL -vvvv
```

## Configuration

Before running, update the constants in the script (lines 46-77):

| Constant | Description |
|----------|-------------|
| `TOKENIZED_STRATEGY` | YieldSkimmingTokenizedStrategy implementation address |
| `LIDO_STRATEGY_FACTORY` | LidoStrategyFactory address |
| `DRAGON_FUNDING_POOL` | Grant recipient address |
| `KEEPER_BOT` | Address authorized to call `report()` |
| `EMERGENCY_ADMIN` | Emergency admin address |
| `STRATEGY_NAME` | Name for the strategy token |
| `TARGET_ETH_VALUE` | ETH value to deposit (converted to wstETH at current exchange rate) |

**Note:** The `TARGET_ETH_VALUE` is specified in ETH (e.g., `1000 ether`). At script execution time, it is converted to the equivalent wstETH amount by calling `wstETH.getWstETHByStETH()`. This ensures the deposited amount is always worth the target ETH value, regardless of the stETH/wstETH exchange rate.

## Output

The script outputs 4 transactions for the Nouns DAO proposal:

| TX | Action | Target |
|----|--------|--------|
| 1 | Deploy PaymentSplitter | PaymentSplitterFactory |
| 2 | Deploy LidoStrategy | LidoStrategyFactory |
| 3 | Approve wstETH | wstETH token |
| 4 | Deposit wstETH | Predicted strategy address |

For each transaction, the output includes:
- **Target**: Contract address to call
- **Value**: ETH to send (always 0)
- **Function**: Human-readable signature for Nouns UI
- **Calldata**: ABI-encoded parameters (without selector)

## Creating the Proposal

1. Go to [nouns.wtf/vote](https://nouns.wtf/vote)
2. Create a new proposal
3. Add each transaction using the TARGET, FUNCTION, and CALLDATA from the output
4. Submit for voting
