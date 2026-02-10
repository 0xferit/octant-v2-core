import "dotenv/config";
import { ethers } from "ethers";

const RPC_URL = process.env.RPC_URL;
const PRIVATE_KEY = process.env.PRIVATE_KEY;

// Already-deployed factory from our forge script
const FACTORY_ADDRESS = "0xbBDA7c5A04B49Ade0dBbbC611AF7Bd3649e87363";
const MOCK_TOKEN_ADDRESS = "0x1443F4A7ec977cb940251fB7dF5f8237B38D9c3f";

const FACTORY_ABI = [
  "function deployQuadraticVotingMechanism(tuple(address asset, string name, string symbol, uint256 votingDelay, uint256 votingPeriod, uint256 quorumShares, uint256 timelockDelay, uint256 gracePeriod, address owner) _config, uint256 _alphaNumerator, uint256 _alphaDenominator) external returns (address mechanism)",
  "function predictMechanismAddress(tuple(address asset, string name, string symbol, uint256 votingDelay, uint256 votingPeriod, uint256 quorumShares, uint256 timelockDelay, uint256 gracePeriod, address owner) _config, uint256 _alphaNumerator, uint256 _alphaDenominator, address deployer) view returns (address predicted)",
  "function getAllDeployedMechanisms() view returns (address[])",
  "function getDeployedCount() view returns (uint256)",
  "event AllocationMechanismDeployed(address indexed mechanism, address indexed asset, string name, string symbol, address indexed deployer)",
];

async function main() {
  const provider = new ethers.JsonRpcProvider(RPC_URL, 1, {
    staticNetwork: true,
    batchMaxCount: 1,
  });
  const wallet = new ethers.Wallet(PRIVATE_KEY, provider);

  console.log("Deployer:", wallet.address);
  console.log("Factory:", FACTORY_ADDRESS);
  console.log("MockToken:", MOCK_TOKEN_ADDRESS);
  console.log();

  const factory = new ethers.Contract(FACTORY_ADDRESS, FACTORY_ABI, wallet);

  // Check existing deployments
  const countBefore = await factory.getDeployedCount();
  console.log("Mechanisms deployed so far:", countBefore.toString());

  // Deploy a new QVM with slightly different params so CREATE2 doesn't collide
  const config = {
    asset: MOCK_TOKEN_ADDRESS,
    name: "Quadratic Voting Mechanism v" + (Number(countBefore) + 1).toString(),
    symbol: "QVM" + (Number(countBefore) + 1).toString(),
    votingDelay: 3600n, // 1 hour
    votingPeriod: 604800n, // 7 days
    quorumShares: ethers.parseEther("1"),
    timelockDelay: 86400n, // 1 day
    gracePeriod: 604800n, // 7 days
    owner: ethers.ZeroAddress, // factory overrides with msg.sender
  };

  // Predict the address BEFORE deploying
  console.log("\nCalling factory.predictMechanismAddress()...");
  const predictedAddress = await factory.predictMechanismAddress(config, 50n, 100n, wallet.address);
  console.log("Predicted QVM address:", predictedAddress);

  // Now actually deploy
  console.log("\nCalling factory.deployQuadraticVotingMechanism()...");
  const tx = await factory.deployQuadraticVotingMechanism(config, 50n, 100n);
  console.log("Tx hash:", tx.hash);

  const receipt = await tx.wait();
  console.log("Tx status:", receipt.status === 1 ? "SUCCESS" : "FAILED");
  console.log("Gas used:", receipt.gasUsed.toString());

  // Parse the AllocationMechanismDeployed event from logs
  let deployedAddress;
  for (const log of receipt.logs) {
    try {
      const parsed = factory.interface.parseLog(log);
      if (parsed && parsed.name === "AllocationMechanismDeployed") {
        deployedAddress = parsed.args.mechanism;
        console.log("\n--- AllocationMechanismDeployed Event ---");
        console.log("  mechanism:", parsed.args.mechanism);
        console.log("  asset:    ", parsed.args.asset);
        console.log("  name:     ", parsed.args.name);
        console.log("  symbol:   ", parsed.args.symbol);
        console.log("  deployer: ", parsed.args.deployer);
      }
    } catch {}
  }

  // Compare predicted vs actual
  console.log("\n--- Address Verification ---");
  console.log("  Predicted:", predictedAddress);
  console.log("  Actual:   ", deployedAddress);
  console.log("  Match:    ", predictedAddress === deployedAddress ? "YES ✅" : "NO ❌");

  // Verify via view call
  const countAfter = await factory.getDeployedCount();
  const allMechanisms = await factory.getAllDeployedMechanisms();
  console.log("\nMechanisms deployed after:", countAfter.toString());
  console.log("All mechanism addresses:", allMechanisms);
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
