#!/usr/bin/env node
/* eslint-disable no-console */
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";

const BUMP_RANK = {
  none: 0,
  patch: 1,
  minor: 2,
  major: 3
};
const REPO_SAFE_DIRECTORY = process.cwd();

function run(cmd, args, opts = {}) {
  const result = spawnSync(cmd, args, {
    cwd: opts.cwd,
    encoding: "utf8"
  });

  if (result.status !== 0) {
    const stderr = (result.stderr || "").trim();
    const stdout = (result.stdout || "").trim();
    throw new Error(
      [
        `Command failed: ${cmd} ${args.join(" ")}`,
        opts.cwd ? `cwd: ${opts.cwd}` : "",
        stderr ? `stderr: ${stderr}` : "",
        stdout ? `stdout: ${stdout}` : ""
      ]
        .filter(Boolean)
        .join("\n")
    );
  }

  return (result.stdout || "").trim();
}

function runJson(cmd, args, opts = {}) {
  const output = run(cmd, args, opts);
  return JSON.parse(output);
}

function runGit(args, opts = {}) {
  return run("git", ["-c", `safe.directory=${REPO_SAFE_DIRECTORY}`, ...args], opts);
}

function parseArgs(argv) {
  const [, , command, ...rest] = argv;
  const opts = { command };

  for (let i = 0; i < rest.length; i += 1) {
    const current = rest[i];
    if (!current.startsWith("--")) {
      continue;
    }
    const key = current.slice(2);
    const next = rest[i + 1];

    if (next && !next.startsWith("--")) {
      opts[key] = next;
      i += 1;
    } else {
      opts[key] = true;
    }
  }

  return opts;
}

function ensureCommand(opts) {
  if (!opts.command || !["diff", "check"].includes(opts.command)) {
    throw new Error(
      "Usage: node scripts/sol-semver.mjs <diff|check> [--old-ref <ref>] [--new-ref <ref>]"
    );
  }
}

function ensureContractId(contractId) {
  if (!contractId || !contractId.includes(":")) {
    throw new Error(`Invalid contract id '${contractId}'. Expected format: src/Path.sol:ContractName`);
  }
}

function parseContractId(contractId) {
  ensureContractId(contractId);
  const splitIndex = contractId.lastIndexOf(":");
  const sourcePath = contractId.slice(0, splitIndex);
  const contractName = contractId.slice(splitIndex + 1);
  return { sourcePath, contractName };
}

function normalizeStorageTypeId(typeId) {
  // forge type ids include compiler-generated numeric suffixes for structs.
  // Example: t_struct(StrategyParams)79023_storage -> t_struct(StrategyParams)_storage
  return typeId.replace(/\)(\d+)_/g, ")_");
}

function sortStorageEntries(entries) {
  return [...entries].sort((a, b) => {
    const slotA = BigInt(a.slot);
    const slotB = BigInt(b.slot);
    if (slotA < slotB) {
      return -1;
    }
    if (slotA > slotB) {
      return 1;
    }
    return a.offset - b.offset;
  });
}

function toStorageFingerprint(entry, types) {
  const typeInfo = types[entry.type] || {};
  return {
    slot: String(entry.slot),
    offset: Number(entry.offset),
    typeId: normalizeStorageTypeId(entry.type),
    encoding: typeInfo.encoding || "",
    label: typeInfo.label || "",
    numberOfBytes: typeInfo.numberOfBytes || ""
  };
}

function compareStorage(oldStorageRaw, newStorageRaw) {
  const oldEntries = sortStorageEntries(oldStorageRaw.storage || []);
  const newEntries = sortStorageEntries(newStorageRaw.storage || []);
  const oldTypes = oldStorageRaw.types || {};
  const newTypes = newStorageRaw.types || {};

  const reasons = [];

  if (newEntries.length < oldEntries.length) {
    reasons.push("storage entries were removed");
    return { bump: "major", reasons };
  }

  for (let i = 0; i < oldEntries.length; i += 1) {
    const oldFingerprint = toStorageFingerprint(oldEntries[i], oldTypes);
    const newFingerprint = toStorageFingerprint(newEntries[i], newTypes);

    if (!newFingerprint) {
      reasons.push("storage entries were removed");
      return { bump: "major", reasons };
    }

    if (oldFingerprint.slot !== newFingerprint.slot || oldFingerprint.offset !== newFingerprint.offset) {
      reasons.push(
        `storage position changed at index ${i} (old slot=${oldFingerprint.slot},offset=${oldFingerprint.offset}; new slot=${newFingerprint.slot},offset=${newFingerprint.offset})`
      );
      return { bump: "major", reasons };
    }

    if (
      oldFingerprint.typeId !== newFingerprint.typeId ||
      oldFingerprint.encoding !== newFingerprint.encoding ||
      oldFingerprint.label !== newFingerprint.label ||
      oldFingerprint.numberOfBytes !== newFingerprint.numberOfBytes
    ) {
      reasons.push(
        `storage type changed at slot=${oldFingerprint.slot},offset=${oldFingerprint.offset} (${oldFingerprint.label} -> ${newFingerprint.label})`
      );
      return { bump: "major", reasons };
    }
  }

  if (newEntries.length > oldEntries.length) {
    reasons.push(`new storage entries appended (${newEntries.length - oldEntries.length})`);
    return { bump: "minor", reasons };
  }

  return { bump: "none", reasons: ["storage layout is identical"] };
}

function abiKey(item) {
  const inputs = (item.inputs || []).map((i) => i.type).join(",");
  return `${item.type}:${item.name || ""}(${inputs})`;
}

function abiOutputs(item) {
  return (item.outputs || []).map((o) => o.type).join(",");
}

function eventIndexedPattern(item) {
  return (item.inputs || []).map((i) => (i.indexed ? "1" : "0")).join("");
}

function compareAbi(oldAbiRaw, newAbiRaw) {
  const oldRelevant = (oldAbiRaw || []).filter((x) => ["function", "event", "error"].includes(x.type));
  const newRelevant = (newAbiRaw || []).filter((x) => ["function", "event", "error"].includes(x.type));

  const oldMap = new Map(oldRelevant.map((item) => [abiKey(item), item]));
  const newMap = new Map(newRelevant.map((item) => [abiKey(item), item]));

  const majorReasons = [];
  const minorReasons = [];

  for (const [key, oldItem] of oldMap) {
    const newItem = newMap.get(key);
    if (!newItem) {
      majorReasons.push(`removed ${oldItem.type} ${key}`);
      continue;
    }

    if (oldItem.type === "function") {
      if (abiOutputs(oldItem) !== abiOutputs(newItem)) {
        majorReasons.push(`changed function return types for ${key}`);
      }
      if ((oldItem.stateMutability || "") !== (newItem.stateMutability || "")) {
        majorReasons.push(`changed function mutability for ${key}`);
      }
    }

    if (oldItem.type === "event") {
      if (eventIndexedPattern(oldItem) !== eventIndexedPattern(newItem)) {
        majorReasons.push(`changed indexed event arguments for ${key}`);
      }
    }
  }

  for (const [key, newItem] of newMap) {
    if (!oldMap.has(key)) {
      minorReasons.push(`added ${newItem.type} ${key}`);
    }
  }

  if (majorReasons.length > 0) {
    return { bump: "major", reasons: majorReasons };
  }

  if (minorReasons.length > 0) {
    return { bump: "minor", reasons: minorReasons };
  }

  return { bump: "none", reasons: ["ABI is identical"] };
}

function stripSolidityMetadata(bytecode) {
  if (!bytecode || bytecode === "0x") {
    return bytecode || "0x";
  }

  const hex = bytecode.startsWith("0x") ? bytecode.slice(2) : bytecode;
  if (hex.length < 4) {
    return `0x${hex}`;
  }

  const metadataLengthHex = hex.slice(-4);
  const metadataLengthBytes = Number.parseInt(metadataLengthHex, 16);
  if (!Number.isFinite(metadataLengthBytes)) {
    return `0x${hex}`;
  }

  const suffixHexLength = metadataLengthBytes * 2 + 4;
  if (suffixHexLength > hex.length) {
    return `0x${hex}`;
  }

  return `0x${hex.slice(0, hex.length - suffixHexLength)}`;
}

function compareBytecode(oldBytecodeRaw, newBytecodeRaw) {
  const oldStripped = stripSolidityMetadata(oldBytecodeRaw);
  const newStripped = stripSolidityMetadata(newBytecodeRaw);

  if (oldStripped === newStripped) {
    return { bump: "none", reasons: ["deployed bytecode is identical after metadata stripping"] };
  }

  return { bump: "patch", reasons: ["deployed bytecode changed"] };
}

function maxBump(...bumps) {
  let current = "none";
  for (const bump of bumps) {
    if (BUMP_RANK[bump] > BUMP_RANK[current]) {
      current = bump;
    }
  }
  return current;
}

function deriveRecommendedBump(storageLayer, abiLayer, bytecodeLayer) {
  const raw = maxBump(storageLayer.bump, abiLayer.bump, bytecodeLayer.bump);
  return { raw, recommended: raw };
}

function parseSemver(version) {
  const match = /^(\d+)\.(\d+)\.(\d+)$/.exec(version || "");
  if (!match) {
    return null;
  }
  return {
    major: Number(match[1]),
    minor: Number(match[2]),
    patch: Number(match[3])
  };
}

function semverBump(version, bump) {
  const parsed = parseSemver(version);
  if (!parsed) {
    return null;
  }

  if (bump === "none") {
    return `${parsed.major}.${parsed.minor}.${parsed.patch}`;
  }
  if (bump === "patch") {
    return `${parsed.major}.${parsed.minor}.${parsed.patch + 1}`;
  }
  if (bump === "minor") {
    return `${parsed.major}.${parsed.minor + 1}.0`;
  }
  return `${parsed.major + 1}.0.0`;
}

function semverCompare(a, b) {
  const pa = parseSemver(a);
  const pb = parseSemver(b);
  if (!pa || !pb) {
    return null;
  }
  if (pa.major !== pb.major) {
    return pa.major < pb.major ? -1 : 1;
  }
  if (pa.minor !== pb.minor) {
    return pa.minor < pb.minor ? -1 : 1;
  }
  if (pa.patch !== pb.patch) {
    return pa.patch < pb.patch ? -1 : 1;
  }
  return 0;
}

function computeExpectedMinimumVersion(result, oldLockedVersion) {
  if (result.declared_version_old) {
    return semverBump(result.declared_version_old, result.recommended_bump);
  }

  if (oldLockedVersion) {
    return semverBump(oldLockedVersion, result.recommended_bump);
  }

  // No historical version exists in code or lock file.
  return null;
}

function readDeclaredVersion(worktreeDir, contractId) {
  const { sourcePath } = parseContractId(contractId);
  const filePath = path.join(worktreeDir, sourcePath);
  if (!fs.existsSync(filePath)) {
    return null;
  }

  const source = fs.readFileSync(filePath, "utf8");
  const apiVersionMatch = source.match(/\bAPI_VERSION\b\s*=\s*"(\d+\.\d+\.\d+)"/);
  if (apiVersionMatch) {
    return apiVersionMatch[1];
  }

  const versionMatch = source.match(/\bVERSION\b\s*=\s*"(\d+\.\d+\.\d+)"/);
  if (versionMatch) {
    return versionMatch[1];
  }

  return null;
}

function prepareWorktree(worktreeDir) {
  run("forge", ["soldeer", "install"], { cwd: worktreeDir });
  run("forge", ["clean"], { cwd: worktreeDir });
  run("forge", ["build", "--skip", "test", "--skip", "script"], { cwd: worktreeDir });
}

function inspectAbi(worktreeDir, contractId) {
  return runJson("forge", ["inspect", contractId, "abi", "--json"], { cwd: worktreeDir });
}

function inspectStorage(worktreeDir, contractId) {
  return runJson("forge", ["inspect", contractId, "storage", "--json"], { cwd: worktreeDir });
}

function inspectDeployedBytecode(worktreeDir, contractId) {
  return run("forge", ["inspect", contractId, "deployedBytecode"], { cwd: worktreeDir }).trim();
}

function analyzeContract(worktrees, contractId) {
  const oldAbi = inspectAbi(worktrees.old, contractId);
  const newAbi = inspectAbi(worktrees.new, contractId);
  const oldStorage = inspectStorage(worktrees.old, contractId);
  const newStorage = inspectStorage(worktrees.new, contractId);
  const oldBytecode = inspectDeployedBytecode(worktrees.old, contractId);
  const newBytecode = inspectDeployedBytecode(worktrees.new, contractId);

  const storageLayer = compareStorage(oldStorage, newStorage);
  const abiLayer = compareAbi(oldAbi, newAbi);
  const bytecodeLayer = compareBytecode(oldBytecode, newBytecode);
  const recommendation = deriveRecommendedBump(storageLayer, abiLayer, bytecodeLayer);
  const recommendedBump = recommendation.recommended;

  const declaredVersionOld = readDeclaredVersion(worktrees.old, contractId);
  const declaredVersionNew = readDeclaredVersion(worktrees.new, contractId);

  return {
    contract: contractId,
    raw_recommended_bump: recommendation.raw,
    recommended_bump: recommendedBump,
    layers: {
      storage: storageLayer,
      abi: abiLayer,
      bytecode: bytecodeLayer
    },
    declared_version_old: declaredVersionOld,
    declared_version_new: declaredVersionNew,
    expected_minimum_version: null
  };
}

function parseContractsOption(rawContracts) {
  if (!rawContracts) {
    return [];
  }
  return rawContracts
    .split(",")
    .map((c) => c.trim())
    .filter(Boolean);
}

function loadLockFile(worktreeDir, lockFilePath) {
  if (!lockFilePath) {
    return { version: 1, contracts: {} };
  }

  const absolute = path.join(worktreeDir, lockFilePath);
  if (!fs.existsSync(absolute)) {
    return { version: 1, contracts: {} };
  }

  const parsed = JSON.parse(fs.readFileSync(absolute, "utf8"));
  if (!parsed.contracts || typeof parsed.contracts !== "object") {
    throw new Error(`Invalid lock file format: ${lockFilePath}`);
  }
  return parsed;
}

function gatherChangedSolidityFiles(oldRef, newRef) {
  const output = runGit(["diff", "--name-only", oldRef, newRef, "--", "src"]);
  return output
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line.endsWith(".sol"));
}

function detectChangedVersionedContracts(worktrees, changedFiles, lockContracts) {
  const candidates = [];
  const lockSet = new Set(lockContracts);

  for (const contractId of lockContracts) {
    const { sourcePath } = parseContractId(contractId);
    if (changedFiles.includes(sourcePath)) {
      candidates.push(contractId);
    }
  }

  // If no lock entries match changed files, scan changed files for API_VERSION and map to known lock entries.
  if (candidates.length === 0) {
    for (const file of changedFiles) {
      const fullPath = path.join(worktrees.new, file);
      if (!fs.existsSync(fullPath)) {
        continue;
      }
      const source = fs.readFileSync(fullPath, "utf8");
      if (!/\bAPI_VERSION\b/.test(source)) {
        continue;
      }
      for (const contractId of lockSet) {
        const { sourcePath } = parseContractId(contractId);
        if (sourcePath === file) {
          candidates.push(contractId);
        }
      }
    }
  }

  return [...new Set(candidates)];
}

function createTempWorktrees(oldRef, newRef) {
  const baseTemp = fs.mkdtempSync(path.join(os.tmpdir(), "sol-semver-"));
  const oldDir = path.join(baseTemp, "old");
  const newDir = path.join(baseTemp, "new");

  runGit(["worktree", "add", "--detach", oldDir, oldRef]);
  runGit(["worktree", "add", "--detach", newDir, newRef]);

  return {
    baseTemp,
    old: oldDir,
    new: newDir
  };
}

function cleanupTempWorktrees(worktrees) {
  if (!worktrees) {
    return;
  }
  try {
    runGit(["worktree", "remove", "--force", worktrees.old]);
  } catch (_e) {
    // Best effort cleanup.
  }
  try {
    runGit(["worktree", "remove", "--force", worktrees.new]);
  } catch (_e) {
    // Best effort cleanup.
  }
  try {
    fs.rmSync(worktrees.baseTemp, { recursive: true, force: true });
  } catch (_e) {
    // Best effort cleanup.
  }
}

function validateUnderBump(result, oldLockedVersion) {
  if (oldLockedVersion && semverCompare(oldLockedVersion, oldLockedVersion) === null) {
    return {
      ok: false,
      reason: `invalid lock version format '${oldLockedVersion}'`,
      expectedMinimumVersion: null
    };
  }

  if (!result.declared_version_new) {
    return {
      ok: false,
      reason: "missing declared API_VERSION/VERSION; version is required",
      expectedMinimumVersion: null
    };
  }

  const cmpFormat = semverCompare(result.declared_version_new, result.declared_version_new);
  if (cmpFormat === null) {
    return {
      ok: false,
      reason: `invalid semantic version format '${result.declared_version_new}'`,
      expectedMinimumVersion: null
    };
  }

  const expectedMinimumVersion = computeExpectedMinimumVersion(result, oldLockedVersion);
  if (!expectedMinimumVersion) {
    return {
      ok: true,
      reason: "",
      expectedMinimumVersion: null
    };
  }

  const cmp = semverCompare(result.declared_version_new, expectedMinimumVersion);
  if (cmp === null) {
    return {
      ok: false,
      reason: `invalid semantic version format '${result.declared_version_new}'`,
      expectedMinimumVersion
    };
  }

  if (cmp < 0) {
    return {
      ok: false,
      reason: `declared version ${result.declared_version_new} is below expected minimum ${expectedMinimumVersion}`,
      expectedMinimumVersion
    };
  }

  return {
    ok: true,
    reason: "",
    expectedMinimumVersion
  };
}

function buildCheckReport(opts, worktrees) {
  const oldRef = opts["old-ref"] || "HEAD~1";
  const newRef = opts["new-ref"] || "HEAD";
  const lockFilePath = opts["lock-file"] || "";

  const oldLock = loadLockFile(worktrees.old, lockFilePath);
  const newLock = loadLockFile(worktrees.new, lockFilePath);

  let contracts = parseContractsOption(opts.contracts);
  if (contracts.length === 0) {
    contracts = Object.keys(newLock.contracts || {});
  }

  if (contracts.length === 0) {
    throw new Error("No contracts to check. Provide --contracts or --lock-file with non-empty contracts map.");
  }

  const changedFiles = gatherChangedSolidityFiles(oldRef, newRef);
  const changedCandidates = detectChangedVersionedContracts(worktrees, changedFiles, contracts);
  const contractsToAnalyze = changedCandidates.length > 0 ? changedCandidates : contracts;

  const contractReports = [];
  const failures = [];

  for (const contractId of contractsToAnalyze) {
    const result = analyzeContract(worktrees, contractId);
    const changed = result.recommended_bump !== "none";
    const contractStatus = {
      contract: contractId,
      changed,
      result,
      checks: []
    };

    if (changed) {
      const oldLocked = lockFilePath ? oldLock.contracts[contractId] : null;
      const underBump = validateUnderBump(result, oldLocked);
      result.expected_minimum_version = underBump.expectedMinimumVersion;
      contractStatus.checks.push({
        name: "under-bump",
        ok: underBump.ok,
        reason: underBump.reason
      });
      if (!underBump.ok) {
        failures.push(`${contractId}: ${underBump.reason}`);
      }

      if (lockFilePath) {
        const newLocked = newLock.contracts[contractId];

        if (!newLocked) {
          failures.push(`${contractId}: missing entry in ${lockFilePath}`);
          contractStatus.checks.push({
            name: "lock-entry-present",
            ok: false,
            reason: `missing lock entry in ${lockFilePath}`
          });
        } else {
          contractStatus.checks.push({
            name: "lock-entry-present",
            ok: true,
            reason: ""
          });
        }

        if (newLocked && result.declared_version_new && newLocked !== result.declared_version_new) {
          failures.push(
            `${contractId}: lock version ${newLocked} does not match declared version ${result.declared_version_new}`
          );
          contractStatus.checks.push({
            name: "lock-vs-declared",
            ok: false,
            reason: `lock=${newLocked} declared=${result.declared_version_new}`
          });
        } else {
          contractStatus.checks.push({
            name: "lock-vs-declared",
            ok: true,
            reason: ""
          });
        }

        if (oldLocked && newLocked && oldLocked === newLocked) {
          failures.push(`${contractId}: changed contract but ${lockFilePath} was not updated`);
          contractStatus.checks.push({
            name: "lock-updated",
            ok: false,
            reason: "lock version did not change despite contract changes"
          });
        } else {
          contractStatus.checks.push({
            name: "lock-updated",
            ok: true,
            reason: ""
          });
        }
      }
    }

    contractReports.push(contractStatus);
  }

  return {
    old_ref: oldRef,
    new_ref: newRef,
    lock_file: lockFilePath || null,
    contracts_analyzed: contractsToAnalyze,
    changed_files: changedFiles,
    failures,
    results: contractReports
  };
}

function printAndExit(payload, exitCode) {
  console.log(JSON.stringify(payload, null, 2));
  process.exit(exitCode);
}

function main() {
  const opts = parseArgs(process.argv);
  ensureCommand(opts);

  const oldRef = opts["old-ref"] || "HEAD~1";
  const newRef = opts["new-ref"] || "HEAD";

  if (Object.hasOwn(opts, "policy")) {
    throw new Error("`--policy` is not supported. sol-semver has a single built-in classification mode.");
  }

  let worktrees;

  try {
    worktrees = createTempWorktrees(oldRef, newRef);
    prepareWorktree(worktrees.old);
    prepareWorktree(worktrees.new);

    if (opts.command === "diff") {
      const contractId = opts.contract;
      ensureContractId(contractId);
      const report = analyzeContract(worktrees, contractId);
      printAndExit(report, 0);
    }

    const report = buildCheckReport(opts, worktrees);
    if (report.failures.length > 0) {
      printAndExit(report, 1);
    }
    printAndExit(report, 0);
  } catch (error) {
    const payload = {
      error: error instanceof Error ? error.message : String(error)
    };
    printAndExit(payload, 1);
  } finally {
    cleanupTempWorktrees(worktrees);
  }
}

main();
