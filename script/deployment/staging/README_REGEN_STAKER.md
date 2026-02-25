# Regen Staker Deployment Guide

This guide explains how to deploy the Regen Staker components using Gnosis Safe multisig on Tenderly Virtual TestNet (or other networks).

## Overview

The Regen Staker deployment consists of two main steps:

1. **Deploy RegenStakerFactory** - **OPTIONAL** A factory contract for creating Regen Staker instances
2. **Deploy Regen Staker Instance** - Deploy the actual staker with all dependencies (Address Sets, optional Earning Power Calculator)

### Deployment Flow

```
1. DeployRegenStakerFactory
   └─> Creates RegenStakerFactory via CREATE2
   
2. DeployRegenStakerWithSafe
   ├─> Deploys AddressSets (if not exist):
   │   ├─> stakerAllowset
   │   ├─> stakerBlockset
   │   └─> allocationMechanismAllowset
   ├─> Deploys RegenEarningPowerCalculator (if not exist)
   └─> Deploys RegenStaker instance
       └─> Uses RegenStakerFactory.deployWithoutDelegation()
```

## Prerequisites

1. **Tenderly Virtual TestNet** access (shared RPC or your own)
2. **Tenderly Personal Access Token** for contract verification
3. **ETH on TestNet** - Fund your deployer address
4. **Gnosis Safe** deployed and configured with your deployer as owner/delegate

## Step 1: Deploy RegenStakerFactory

Optional step to deploy the factory contract as we have factory already deployed on mainnet.

### Deployment Steps

```bash
# 1. Set required environment variables
export CHAIN=tenderly
export CHAIN_ID=1
export SAFE_API_BASE_URL=https://safeapi.ov2sm.octant.build/tx-service/eth/api/v1/safes/
export WALLET_TYPE=local
export RPC_URL=https://virtual-mainnet.rpc.ontact.build
export SAFE_ADDRESS=0x...

# 2. Validate PRIVATE_KEY is set
if [ -z "$PRIVATE_KEY" ]; then
    echo "ERROR: PRIVATE_KEY not set"
    exit 1
fi

# 3. Derive sender address from private key
export SENDER=$(cast wallet address --private-key "$PRIVATE_KEY")
echo "Derived SENDER from PRIVATE_KEY: $SENDER"

# 4. Generate unique timestamp for salt
export TS=$(date +%s)

# 5. Set deployment salt with timestamp for uniqueness
export REGEN_STAKER_FACTORY_SALT="OCTANT_REGEN_STAKER_FACTORY_V1_$TS"

# 6. Deploy factory
forge script script/deploy/DeployRegenStakerFactory.s.sol:DeployRegenStakerFactory \
  --ffi \
  --rpc-url $RPC_URL \
  --broadcast \
  --sender $SENDER
```

**Important Notes**:
- `PRIVATE_KEY` must be set before running
- `SENDER` will be automatically derived from `PRIVATE_KEY`
- `SENDER` must be an owner or delegate of the Safe
- `TS` timestamp ensures unique deployment salts

### Post-Deployment

1. **Go to Gnosis Safe UI** (e.g., https://app.safe.global)
2. **Connect your wallet** and select the Safe
3. **Review the transaction batch** containing the factory deployment
4. **Sign and execute** the transaction
5. **Save the factory address** - you'll need it for step 2:
   ```bash
   export REGEN_STAKER_FACTORY=0x... # Address from deployment output
   ```

## Step 2: Deploy Regen Staker Instance

This step deploys:
- 3 Address Sets (allowset, blockset, allocation allowset)
- Regen Earning Power Calculator
- Regen Staker instance (without delegation)

### Deployment Steps

```bash
# 1. Set network configuration (if not already set from Step 1)
export CHAIN=tenderly
export CHAIN_ID=1
export SAFE_API_BASE_URL=https://safeapi.ov2sm.octant.build/tx-service/eth/api/v1/safes/
export WALLET_TYPE=local
export RPC_URL=https://virtual-mainnet.rpc.octant.build
export SAFE_ADDRESS=0x...

# 2. Validate PRIVATE_KEY is set
if [ -z "$PRIVATE_KEY" ]; then
    echo "ERROR: PRIVATE_KEY not set"
    exit 1
fi

# 3. Derive sender address from private key
export SENDER=$(cast wallet address --private-key "$PRIVATE_KEY")
echo "Derived SENDER from PRIVATE_KEY: $SENDER"

# 4. Generate unique timestamp for salts
export TS=$(date +%s)

# 5. Configure Address Sets
export ADDRESS_SET_OWNER=$SAFE_ADDRESS
export STAKER_ALLOWSET_SALT="OCTANT_STAKER_ALLOWSET_V1_${TS}"
export STAKER_BLOCKSET_SALT="OCTANT_STAKER_BLOCKSET_V1_${TS}"
export ALLOCATION_MECHANISM_ALLOWSET_SALT="OCTANT_ALLOCATION_MECHANISM_ALLOWSET_V1_${TS}"

# 6. Configure Regen Staker parameters
export REGEN_STAKER_WITH_DELEGATION_SALT="OCTANT_REGEN_STAKER_WITH_DELEGATION_V1${TS}"
export REGEN_STAKER_WITHOUT_DELEGATION_SALT="OCTANT_REGEN_STAKER_WITHOUT_DELEGATION_V1_${TS}"
export ACCESS_MODE=0                        # 0=Open, 1=AllowlistOnly, 2=DenylistOnly
export REWARD_DURATION=2592000              # 30 days in seconds
export REWARDS_TOKEN=0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2  # WETH on mainnet
export STAKE_TOKEN=0x7DD9c5Cba05E151C895FDe1CF355C9A1D5DA6429    # GLM token
export MAX_BUMP_TIP=2000000000000000        # 0.002 ETH in wei
export MIN_STAKE=100000000000000000000      # 100 tokens (with 18 decimals)

# 7. Deploy Regen Staker with all dependencies
forge script script/deployment/staging/DeployRegenStakerWithSafe.s.sol:DeployRegenStakerWithSafe \
  --ffi \
  --rpc-url $RPC_URL \
  --broadcast \
  --sender $SENDER
```

**Important Notes**:
- `PRIVATE_KEY` must be set before running
- `REGEN_STAKER_FACTORY` must be set to the address from Step 1 - **OPTIONAL**
- `SENDER` will be automatically derived from `PRIVATE_KEY`
- `SENDER` must be an owner or delegate of the Safe
- Token addresses (`REWARDS_TOKEN`, `STAKE_TOKEN`) must exist on the target network
- `REWARD_DURATION` must be between 7 and 3000 days
- All salt values are automatically made unique with timestamp suffix

### Post-Deployment

1. **Review the output** - the script will print all deployed addresses:
   ```
   Deployment Summary:
   ------------------
   Starting block:                   12345678
   Staker Allowset:                  0x...
   Staker Blockset:                  0x...
   Allocation Mechanism Allowset:    0x...
   Earning Power Calculator:         0x...
   RegenStakerFactory:               0x...
   RegenStaker (without delegation): 0x...
   ------------------
   ```

2. **Go to Gnosis Safe UI**
3. **Review the transaction batch** - it will contain multiple deployments
4. **Sign and execute** all transactions
5. **Wait for confirmation** on the blockchain

## Verification

### Verify Deployments On-Chain

```bash
# Check factory code
cast code $REGEN_STAKER_FACTORY --rpc-url $RPC_URL

# Check staker code
cast code $REGEN_STAKER --rpc-url $RPC_URL

# Get staker parameters
cast call $REGEN_STAKER "rewardsDuration()(uint256)" --rpc-url $RPC_URL
cast call $REGEN_STAKER "stakingToken()(address)" --rpc-url $RPC_URL
cast call $REGEN_STAKER "rewardsToken()(address)" --rpc-url $RPC_URL
```

### Verify Contract Source Code

For Tenderly verification:
```bash
forge verify-contract \
  --verifier custom \
  --verifier-url $VERIFIER_URL \
  $CONTRACT_ADDRESS \
  src/factories/RegenStakerFactory.sol:RegenStakerFactory
```
