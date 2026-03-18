#!/bin/bash

# Combine ABIs from SkyCompounderStrategy and YieldDonatingTokenizedStrategy
jq -s '{"abi": (.[0].abi + .[1].abi)|unique}' \
  out/SkyCompounderStrategy.sol/SkyCompounderStrategy.json \
  out/YieldDonatingTokenizedStrategy.sol/YieldDonatingTokenizedStrategy.json \
  > out/SkyCompounderStrategy.sol/SkyCompounderYieldDonatingTokenizedStrategy.json

# Combine ABIs from MorphoCompounderStrategy and YieldDonatingTokenizedStrategy
jq -s '{"abi": (.[0].abi + .[1].abi)|unique}' \
  out/MorphoCompounderStrategy.sol/MorphoCompounderStrategy.json \
  out/YieldDonatingTokenizedStrategy.sol/YieldDonatingTokenizedStrategy.json \
  > out/MorphoCompounderStrategy.sol/MorphoCompounderYieldDonatingTokenizedStrategy.json

# Combine ABIs from LidoStrategy and YieldSkimmingTokenizedStrategy
jq -s '{"abi": (.[0].abi + .[1].abi)|unique}' \
  out/LidoStrategy.sol/LidoStrategy.json \
  out/YieldSkimmingTokenizedStrategy.sol/YieldSkimmingTokenizedStrategy.json \
  > out/LidoStrategy.sol/LidoYieldSkimmingTokenizedStrategy.json

# Combine ABIs from MorphoStrategy and YieldSkimmingTokenizedStrategy
jq -s '{"abi": (.[0].abi + .[1].abi)|unique}' \
  out/MorphoCompounderStrategy.sol/MorphoCompounderStrategy.json \
  out/YieldSkimmingTokenizedStrategy.sol/YieldSkimmingTokenizedStrategy.json \
  > out/MorphoCompounderStrategy.sol/MorphoCompounderYieldSkimmingTokenizedStrategy.json

# Combine ABIs from RocketPoolStrategy and YieldSkimmingTokenizedStrategy
jq -s '{"abi": (.[0].abi + .[1].abi)|unique}' \
  out/RocketPoolStrategy.sol/RocketPoolStrategy.json \
  out/YieldSkimmingTokenizedStrategy.sol/YieldSkimmingTokenizedStrategy.json \
  > out/RocketPoolStrategy.sol/RocketPoolYieldSkimmingTokenizedStrategy.json


# Combine ABIs from QuadraticVotingMechanism and TokenizedAllocationMechanism
jq -s '{"abi": (.[0].abi + .[1].abi)|unique}' \
  out/QuadraticVotingMechanism.sol/QuadraticVotingMechanism.json \
  out/TokenizedAllocationMechanism.sol/TokenizedAllocationMechanism.json \
  > out/QuadraticVotingMechanism.sol/QuadraticVotingMechanismTokenizedAllocationMechanism.json
