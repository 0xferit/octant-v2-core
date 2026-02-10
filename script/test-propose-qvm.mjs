import "dotenv/config";
import { ethers } from "ethers";

const RPC_URL = process.env.RPC_URL;
const PRIVATE_KEY = process.env.PRIVATE_KEY;

const QVM_ADDRESS = process.env.QVM_ADDRESS; // Set this to the address of the QVM you want to test

// The QVM delegates to TokenizedAllocationMechanism, so we call these functions on the QVM address
const QVM_ABI = [
  // View functions
  "function getProposalCount() view returns (uint256)",
  "function management() view returns (address)",
  "function keeper() view returns (address)",
  "function owner() view returns (address)",
  "function votingStartTime() view returns (uint256)",
  "function votingEndTime() view returns (uint256)",
  "function startTime() view returns (uint256)",

  // Propose
  "function propose(address recipient, string description) returns (uint256 pid)",

  // Events
  "event ProposalCreated(uint256 indexed pid, address indexed proposer, address indexed recipient, string description)",
];

async function main() {
  const provider = new ethers.JsonRpcProvider(RPC_URL, 1, {
    staticNetwork: true,
    batchMaxCount: 1,
  });
  const wallet = new ethers.Wallet(PRIVATE_KEY, provider);
  const qvm = new ethers.Contract(QVM_ADDRESS, QVM_ABI, wallet);

  console.log("Deployer/Caller:", wallet.address);
  console.log("QVM:", QVM_ADDRESS);
  console.log();

  // Check roles - deployer should be management + keeper
  const [management, keeper, owner] = await Promise.all([qvm.management(), qvm.keeper(), qvm.owner()]);
  console.log("--- Roles ---");
  console.log("  owner:     ", owner);
  console.log("  management:", management);
  console.log("  keeper:    ", keeper);
  console.log();

  // Check timing
  const [startTime, votingStart, votingEnd] = await Promise.all([
    qvm.startTime(),
    qvm.votingStartTime(),
    qvm.votingEndTime(),
  ]);
  const now = BigInt(Math.floor(Date.now() / 1000));
  console.log("--- Timing ---");
  console.log("  startTime:      ", new Date(Number(startTime) * 1000).toISOString());
  console.log("  votingStartTime:", new Date(Number(votingStart) * 1000).toISOString());
  console.log("  votingEndTime:  ", new Date(Number(votingEnd) * 1000).toISOString());
  console.log("  now:            ", new Date(Number(now) * 1000).toISOString());
  console.log("  can propose?    ", now <= votingEnd ? "YES" : "NO (voting ended)");
  console.log();

  // Check proposal count BEFORE
  const countBefore = await qvm.getProposalCount();
  console.log("--- getProposalCount() BEFORE ---");
  console.log("  count:", countBefore.toString());
  console.log();

  // Create proposals with unique recipient addresses (use random addresses to avoid RecipientUsed)
  const proposals = [
    { recipient: ethers.Wallet.createRandom().address, description: "Fund community grants program" },
    { recipient: ethers.Wallet.createRandom().address, description: "Support open-source tooling development" },
    { recipient: ethers.Wallet.createRandom().address, description: "Ecosystem growth initiative" },
  ];

  let nonce = await provider.getTransactionCount(wallet.address);

  for (const p of proposals) {
    console.log(`--- Calling propose("${p.recipient}", "${p.description}") ---`);
    const tx = await qvm.propose(p.recipient, p.description, { nonce });
    nonce++;
    console.log("  tx hash:", tx.hash);

    const receipt = await tx.wait();
    console.log("  status: ", receipt.status === 1 ? "SUCCESS" : "FAILED");
    console.log("  gas:    ", receipt.gasUsed.toString());

    // Parse ProposalCreated event
    for (const log of receipt.logs) {
      try {
        const parsed = qvm.interface.parseLog(log);
        if (parsed && parsed.name === "ProposalCreated") {
          console.log("  --- ProposalCreated Event ---");
          console.log("    pid:        ", parsed.args.pid.toString());
          console.log("    proposer:   ", parsed.args.proposer);
          console.log("    recipient:  ", parsed.args.recipient);
          console.log("    description:", parsed.args.description);
        }
      } catch {}
    }
    console.log();
  }

  // Check proposal count AFTER
  const countAfter = await qvm.getProposalCount();
  console.log("--- getProposalCount() AFTER ---");
  console.log("  count:", countAfter.toString());
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
