#!/usr/bin/env node
/* eslint-disable no-console */
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync, spawn } from "node:child_process";

const BUMP_RANK = {
  none: 0,
  patch: 1,
  minor: 2,
  major: 3
};
const REPO_SAFE_DIRECTORY = process.cwd();
const API_VERSION_DECLARATION_PATTERN =
  /\bstring\s+(?:(?:public|internal|private|constant|immutable|override(?:\s*\([^)]*\))?)\s+)*API_VERSION\s*=\s*"(\d+\.\d+\.\d+)"/;

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

function runAsync(cmd, args, opts = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(cmd, args, {
      cwd: opts.cwd,
      stdio: ["ignore", "pipe", "pipe"]
    });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (chunk) => {
      stdout += chunk;
    });
    child.stderr.on("data", (chunk) => {
      stderr += chunk;
    });
    child.on("close", (code) => {
      if (code !== 0) {
        reject(
          new Error(
            [
              `Command failed: ${cmd} ${args.join(" ")}`,
              opts.cwd ? `cwd: ${opts.cwd}` : "",
              stderr.trim() ? `stderr: ${stderr.trim()}` : "",
              stdout.trim() ? `stdout: ${stdout.trim()}` : ""
            ]
              .filter(Boolean)
              .join("\n")
          )
        );
      } else {
        resolve(stdout.trim());
      }
    });
    child.on("error", reject);
  });
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

function remapContractIdSourcePath(contractId, sourcePathMap = {}) {
  const { sourcePath, contractName } = parseContractId(contractId);
  const mappedSourcePath = sourcePathMap[sourcePath] || sourcePath;
  return `${mappedSourcePath}:${contractName}`;
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

/**
 * Compare storage layouts from two Forge inspect outputs.
 *
 * Known limitation: Forge's storage output only includes statically-allocated
 * slots (fixed-size state variables). Mappings and dynamic arrays use keccak256-
 * hashed slots and are invisible to this comparison. Changes to mapping key/value
 * types or dynamic array element types will not be detected here and must be
 * caught by ABI-level review or manual inspection.
 */
function compareStorage(oldStorageRaw, newStorageRaw) {
  const oldEntries = sortStorageEntries(oldStorageRaw.storage || []);
  const newEntries = sortStorageEntries(newStorageRaw.storage || []);
  const oldTypes = oldStorageRaw.types || {};
  const newTypes = newStorageRaw.types || {};

  const minorReasons = [];

  if (newEntries.length < oldEntries.length) {
    minorReasons.push("storage entries were removed");
  }

  const compareCount = Math.min(oldEntries.length, newEntries.length);
  for (let i = 0; i < compareCount; i += 1) {
    const oldFingerprint = toStorageFingerprint(oldEntries[i], oldTypes);
    const newFingerprint = toStorageFingerprint(newEntries[i], newTypes);

    if (oldFingerprint.slot !== newFingerprint.slot || oldFingerprint.offset !== newFingerprint.offset) {
      minorReasons.push(
        `storage position changed at index ${i} (old slot=${oldFingerprint.slot},offset=${oldFingerprint.offset}; new slot=${newFingerprint.slot},offset=${newFingerprint.offset})`
      );
    } else if (
      oldFingerprint.typeId !== newFingerprint.typeId ||
      oldFingerprint.encoding !== newFingerprint.encoding ||
      oldFingerprint.label !== newFingerprint.label ||
      oldFingerprint.numberOfBytes !== newFingerprint.numberOfBytes
    ) {
      minorReasons.push(
        `storage type changed at slot=${oldFingerprint.slot},offset=${oldFingerprint.offset} (${oldFingerprint.label} -> ${newFingerprint.label})`
      );
    }
  }

  if (newEntries.length > oldEntries.length) {
    minorReasons.push(`new storage entries appended (${newEntries.length - oldEntries.length})`);
  }

  if (minorReasons.length > 0) {
    return { bump: "minor", reasons: minorReasons };
  }

  return { bump: "none", reasons: ["storage layout is identical"] };
}

function canonicalAbiParamType(param) {
  const rawType = (param && param.type) || "";
  if (!rawType.startsWith("tuple")) {
    return rawType;
  }

  const tupleSuffix = rawType.slice("tuple".length);
  const components = (param.components || []).map((component) => canonicalAbiParamType(component)).join(",");
  return `tuple(${components})${tupleSuffix}`;
}

function abiKey(item) {
  const inputs = (item.inputs || []).map((i) => canonicalAbiParamType(i)).join(",");
  return `${item.type}:${item.name || ""}(${inputs})`;
}

function abiOutputs(item) {
  return (item.outputs || []).map((o) => canonicalAbiParamType(o)).join(",");
}

function eventIndexedPattern(item) {
  return (item.inputs || []).map((i) => (i.indexed ? "1" : "0")).join("");
}

function isAnonymousEvent(item) {
  return Boolean(item && item.type === "event" && item.anonymous);
}

function compareAbi(oldAbiRaw, newAbiRaw) {
  const oldRelevant = (oldAbiRaw || []).filter((x) =>
    ["function", "event", "error", "fallback", "receive"].includes(x.type)
  );
  const newRelevant = (newAbiRaw || []).filter((x) =>
    ["function", "event", "error", "fallback", "receive"].includes(x.type)
  );

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
    }

    if (["function", "fallback", "receive"].includes(oldItem.type)) {
      if ((oldItem.stateMutability || "") !== (newItem.stateMutability || "")) {
        majorReasons.push(`changed ${oldItem.type} mutability for ${key}`);
      }
    }

    if (oldItem.type === "event") {
      if (eventIndexedPattern(oldItem) !== eventIndexedPattern(newItem)) {
        majorReasons.push(`changed indexed event arguments for ${key}`);
      }
      if (isAnonymousEvent(oldItem) !== isAnonymousEvent(newItem)) {
        majorReasons.push(`changed event anonymity for ${key}`);
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

function isBytecodeOnlyChange(storageLayer, abiLayer, bytecodeLayer) {
  return storageLayer.bump === "none" && abiLayer.bump === "none" && bytecodeLayer.bump !== "none";
}

function deriveRecommendedBump(storageLayer, abiLayer, bytecodeLayer) {
  const raw = maxBump(storageLayer.bump, abiLayer.bump, bytecodeLayer.bump);
  const bytecodeOnly = isBytecodeOnlyChange(storageLayer, abiLayer, bytecodeLayer);
  return {
    raw,
    recommended: bytecodeOnly ? "none" : raw,
    bytecode_only_advisory: bytecodeOnly
  };
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

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function findContractBody(source, contractName) {
  const declaration = new RegExp(
    `\\b(?:abstract\\s+)?contract\\s+${escapeRegExp(contractName)}\\b[^\\{]*\\{`,
    "g"
  );
  const match = declaration.exec(source);
  if (!match) {
    return null;
  }

  const openBraceIndex = source.indexOf("{", match.index);
  if (openBraceIndex < 0) {
    return null;
  }

  let depth = 1;
  let i = openBraceIndex + 1;
  let mode = "normal";

  while (i < source.length) {
    const ch = source[i];
    const next = source[i + 1];

    if (mode === "line-comment") {
      if (ch === "\n") {
        mode = "normal";
      }
      i += 1;
      continue;
    }

    if (mode === "block-comment") {
      if (ch === "*" && next === "/") {
        mode = "normal";
        i += 2;
      } else {
        i += 1;
      }
      continue;
    }

    if (mode === "single-quote") {
      if (ch === "\\") {
        i += 2;
        continue;
      }
      if (ch === "'") {
        mode = "normal";
      }
      i += 1;
      continue;
    }

    if (mode === "double-quote") {
      if (ch === "\\") {
        i += 2;
        continue;
      }
      if (ch === "\"") {
        mode = "normal";
      }
      i += 1;
      continue;
    }

    if (ch === "/" && next === "/") {
      mode = "line-comment";
      i += 2;
      continue;
    }
    if (ch === "/" && next === "*") {
      mode = "block-comment";
      i += 2;
      continue;
    }
    if (ch === "'") {
      mode = "single-quote";
      i += 1;
      continue;
    }
    if (ch === "\"") {
      mode = "double-quote";
      i += 1;
      continue;
    }

    if (ch === "{") {
      depth += 1;
      i += 1;
      continue;
    }
    if (ch === "}") {
      depth -= 1;
      if (depth === 0) {
        return source.slice(openBraceIndex + 1, i);
      }
      i += 1;
      continue;
    }

    i += 1;
  }

  return null;
}

function sourceDeclaresApiVersion(source) {
  const contractNames = extractContractNames(source);
  for (const contractName of contractNames) {
    if (readDeclaredVersionFromSource(source, contractName)) {
      return true;
    }
  }

  return false;
}

function readDeclaredVersionFromSource(source, contractName) {
  const sourceWithoutComments = stripComments(source);
  const contractBody = findContractBody(sourceWithoutComments, contractName);
  if (!contractBody) {
    return null;
  }

  const apiVersionMatch = contractBody.match(API_VERSION_DECLARATION_PATTERN);
  if (apiVersionMatch) {
    return apiVersionMatch[1];
  }

  return null;
}

function readDeclaredVersion(worktreeDir, contractId) {
  const { sourcePath, contractName } = parseContractId(contractId);
  const filePath = path.join(worktreeDir, sourcePath);
  if (!fs.existsSync(filePath)) {
    return null;
  }

  const source = fs.readFileSync(filePath, "utf8");
  return readDeclaredVersionFromSource(source, contractName);
}

function prepareWorktree(worktreeDir) {
  run("forge", ["soldeer", "install"], { cwd: worktreeDir });
  run("forge", ["clean"], { cwd: worktreeDir });
  run("forge", ["build", "--skip", "test", "--skip", "script"], { cwd: worktreeDir });
}

async function prepareWorktreeAsync(worktreeDir) {
  await runAsync("forge", ["soldeer", "install"], { cwd: worktreeDir });
  await runAsync("forge", ["clean"], { cwd: worktreeDir });
  await runAsync("forge", ["build", "--skip", "test", "--skip", "script"], { cwd: worktreeDir });
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

function isMissingContractInspectError(error) {
  const message = error instanceof Error ? error.message : String(error);
  return (
    /Could not find artifact/i.test(message) ||
    /Could not find source file for contract/i.test(message) ||
    /No contract found/i.test(message)
  );
}

function inspectContractSnapshot(worktreeDir, contractId, opts = {}) {
  try {
    return {
      missing: false,
      abi: inspectAbi(worktreeDir, contractId),
      storage: inspectStorage(worktreeDir, contractId),
      bytecode: inspectDeployedBytecode(worktreeDir, contractId)
    };
  } catch (error) {
    if (opts.allowMissing && isMissingContractInspectError(error)) {
      return {
        missing: true,
        abi: null,
        storage: null,
        bytecode: "0x"
      };
    }
    throw error;
  }
}

function analyzeContract(worktrees, contractId, opts = {}) {
  const { sourcePath, contractName } = parseContractId(contractId);
  const oldSourcePath = (opts.renamedNewToOld && opts.renamedNewToOld[sourcePath]) || sourcePath;
  const oldContractId = oldSourcePath === sourcePath ? contractId : `${oldSourcePath}:${contractName}`;

  const oldSnapshot = inspectContractSnapshot(worktrees.old, oldContractId, { allowMissing: true });
  const newSnapshot = inspectContractSnapshot(worktrees.new, contractId, { allowMissing: true });

  let storageLayer;
  let abiLayer;
  let bytecodeLayer;

  if (oldSnapshot.missing && newSnapshot.missing) {
    throw new Error(`Contract ${contractId} is missing in both old and new refs`);
  }

  if (oldSnapshot.missing) {
    // New contract in new-ref: treat as additive change and require lock/version checks.
    storageLayer = { bump: "minor", reasons: ["contract is absent in old ref"] };
    abiLayer = { bump: "minor", reasons: ["contract is absent in old ref"] };
    bytecodeLayer = { bump: "patch", reasons: ["contract is absent in old ref"] };
  } else if (newSnapshot.missing) {
    // Contract removed in new-ref: always breaking.
    storageLayer = { bump: "major", reasons: ["contract is absent in new ref"] };
    abiLayer = { bump: "major", reasons: ["contract is absent in new ref"] };
    bytecodeLayer = { bump: "major", reasons: ["contract is absent in new ref"] };
  } else {
    storageLayer = compareStorage(oldSnapshot.storage, newSnapshot.storage);
    abiLayer = compareAbi(oldSnapshot.abi, newSnapshot.abi);
    bytecodeLayer = compareBytecode(oldSnapshot.bytecode, newSnapshot.bytecode);
  }
  const recommendation = deriveRecommendedBump(storageLayer, abiLayer, bytecodeLayer);
  const recommendedBump = recommendation.recommended;

  const declaredVersionOld = oldSnapshot.missing ? null : readDeclaredVersion(worktrees.old, oldContractId);
  const declaredVersionNew = newSnapshot.missing ? null : readDeclaredVersion(worktrees.new, contractId);

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
    expected_minimum_version: null,
    removed_in_new_ref: !oldSnapshot.missing && newSnapshot.missing,
    bytecode_only_advisory: recommendation.bytecode_only_advisory || false
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

// Lock file support: the --lock-file flag enables pinned version tracking
// per contract. Pre-built for future adoption; the workflow does not pass
// --lock-file yet, and no semver-lock.json exists in the repo.
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
  const output = runGit(["diff", "--name-status", "-M", oldRef, newRef, "--", "src"]);
  const changedFiles = new Set();
  const renamedNewToOld = {};
  const renamedOldToNew = {};

  for (const rawLine of output.split("\n")) {
    const line = rawLine.trim();
    if (!line) {
      continue;
    }

    const parts = line.split("\t");
    const status = parts[0] || "";

    if (status.startsWith("R")) {
      const oldPath = parts[1] || "";
      const newPath = parts[2] || "";

      if (oldPath.endsWith(".sol") && newPath.endsWith(".sol")) {
        changedFiles.add(newPath);
        renamedNewToOld[newPath] = oldPath;
        renamedOldToNew[oldPath] = newPath;
      } else {
        if (oldPath.endsWith(".sol")) {
          changedFiles.add(oldPath);
        }
        if (newPath.endsWith(".sol")) {
          changedFiles.add(newPath);
        }
      }
      continue;
    }

    const filePath = parts[1] || "";
    if (filePath.endsWith(".sol")) {
      changedFiles.add(filePath);
    }
  }

  return {
    changedFiles: [...changedFiles],
    renamedNewToOld,
    renamedOldToNew
  };
}

function detectChangedVersionedContracts(changedFiles, lockContracts, renamedOldToNew = {}) {
  const candidates = [];
  const changedSet = new Set(changedFiles);
  for (const contractId of lockContracts) {
    const { sourcePath } = parseContractId(contractId);
    if (changedSet.has(sourcePath) || Object.hasOwn(renamedOldToNew, sourcePath)) {
      candidates.push(contractId);
    }
  }
  return [...new Set(candidates)];
}

function fileHasVersionConstant(worktreeDir, sourcePath) {
  const fullPath = path.join(worktreeDir, sourcePath);
  if (!fs.existsSync(fullPath)) {
    return false;
  }
  const source = fs.readFileSync(fullPath, "utf8");
  return sourceDeclaresApiVersion(source);
}

function stripComments(sourceCode) {
  let output = "";
  let mode = "normal";

  for (let i = 0; i < sourceCode.length; i += 1) {
    const ch = sourceCode[i];
    const next = sourceCode[i + 1];

    if (mode === "line-comment") {
      if (ch === "\n") {
        mode = "normal";
        output += "\n";
      } else {
        output += " ";
      }
      continue;
    }

    if (mode === "block-comment") {
      if (ch === "*" && next === "/") {
        mode = "normal";
        output += "  ";
        i += 1;
      } else if (ch === "\n") {
        output += "\n";
      } else {
        output += " ";
      }
      continue;
    }

    if (mode === "single-quote") {
      output += ch;
      if (ch === "\\") {
        output += next || "";
        i += 1;
      } else if (ch === "'") {
        mode = "normal";
      }
      continue;
    }

    if (mode === "double-quote") {
      output += ch;
      if (ch === "\\") {
        output += next || "";
        i += 1;
      } else if (ch === "\"") {
        mode = "normal";
      }
      continue;
    }

    if (ch === "/" && next === "/") {
      mode = "line-comment";
      output += "  ";
      i += 1;
      continue;
    }
    if (ch === "/" && next === "*") {
      mode = "block-comment";
      output += "  ";
      i += 1;
      continue;
    }
    if (ch === "'") {
      mode = "single-quote";
      output += ch;
      continue;
    }
    if (ch === "\"") {
      mode = "double-quote";
      output += ch;
      continue;
    }

    output += ch;
  }

  return output;
}

function extractContractNames(sourceCode) {
  const names = [];
  const uncommentedSource = stripComments(sourceCode);
  const regex = /\b(?:abstract\s+)?contract\s+([A-Za-z_][A-Za-z0-9_]*)\b/g;
  let match;
  while ((match = regex.exec(uncommentedSource)) !== null) {
    names.push(match[1]);
  }
  return [...new Set(names)];
}

function findVersionedInspectableContractsInSource(worktreeDir, sourcePath, sourceCode) {
  const inspectable = [];
  const candidates = extractContractNames(sourceCode);

  for (const contractName of candidates) {
    if (!readDeclaredVersionFromSource(sourceCode, contractName)) {
      continue;
    }

    const contractId = `${sourcePath}:${contractName}`;
    try {
      inspectContractSnapshot(worktreeDir, contractId);
      inspectable.push(contractId);
    } catch (error) {
      if (isMissingContractInspectError(error)) {
        continue;
      }
      throw error;
    }
  }

  return inspectable;
}

function discoverChangedContracts(worktrees, changedFiles) {
  const discovered = [];
  const unresolvedFiles = [];

  for (const sourcePath of changedFiles) {
    const newFullPath = path.join(worktrees.new, sourcePath);
    const oldFullPath = path.join(worktrees.old, sourcePath);
    const existsInNew = fs.existsSync(newFullPath);
    const existsInOld = fs.existsSync(oldFullPath);

    if (!existsInNew && !existsInOld) {
      continue;
    }

    let hasVersion = false;
    const inspectable = [];
    const addInspectableFrom = (worktreeDir, fullPath) => {
      const source = fs.readFileSync(fullPath, "utf8");
      if (sourceDeclaresApiVersion(source)) {
        hasVersion = true;
      }
      inspectable.push(...findVersionedInspectableContractsInSource(worktreeDir, sourcePath, source));
    };

    if (existsInOld) {
      addInspectableFrom(worktrees.old, oldFullPath);
    }
    if (existsInNew) {
      addInspectableFrom(worktrees.new, newFullPath);
    }

    const uniqueInspectable = [...new Set(inspectable)];

    discovered.push(...uniqueInspectable);
    if (hasVersion && uniqueInspectable.length === 0) {
      unresolvedFiles.push(sourcePath);
    }
  }

  return {
    contracts: [...new Set(discovered)],
    unresolvedFiles
  };
}

function listSoliditySourceFiles(baseDir, relativeDir = "src") {
  const root = path.join(baseDir, relativeDir);
  if (!fs.existsSync(root)) {
    return [];
  }

  const files = [];
  const entries = fs.readdirSync(root, { withFileTypes: true });
  for (const entry of entries) {
    const entryRelative = path.join(relativeDir, entry.name);
    if (entry.isDirectory()) {
      files.push(...listSoliditySourceFiles(baseDir, entryRelative));
    } else if (entry.isFile() && entry.name.endsWith(".sol")) {
      files.push(entryRelative);
    }
  }
  return files;
}

function discoverVersionedContracts(worktrees) {
  const discovered = [];
  const unresolvedFiles = [];
  const sourceFiles = listSoliditySourceFiles(worktrees.new, "src");

  for (const sourcePath of sourceFiles) {
    const fullPath = path.join(worktrees.new, sourcePath);
    const source = fs.readFileSync(fullPath, "utf8");
    if (!sourceDeclaresApiVersion(source)) {
      continue;
    }

    const inspectable = findVersionedInspectableContractsInSource(worktrees.new, sourcePath, source);
    if (inspectable.length === 0) {
      unresolvedFiles.push(sourcePath);
      continue;
    }

    discovered.push(...inspectable);
  }

  return {
    contracts: [...new Set(discovered)],
    unresolvedFiles
  };
}

function findVersionedChangedFilesMissingLockEntries(worktrees, changedFiles, lockContracts) {
  const lockPaths = new Set(lockContracts.map((contractId) => parseContractId(contractId).sourcePath));
  const missing = [];

  for (const sourcePath of changedFiles) {
    if (lockPaths.has(sourcePath)) {
      continue;
    }

    if (fileHasVersionConstant(worktrees.new, sourcePath)) {
      missing.push(sourcePath);
    }
  }

  return missing;
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
  if (oldLockedVersion && parseSemver(oldLockedVersion) === null) {
    return {
      ok: false,
      reason: `invalid lock version format '${oldLockedVersion}'`,
      expectedMinimumVersion: null
    };
  }

  if (!result.declared_version_new) {
    return {
      ok: false,
      reason: "missing declared API_VERSION; version is required",
      expectedMinimumVersion: null
    };
  }

  if (parseSemver(result.declared_version_new) === null) {
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

  const {
    changedFiles,
    renamedNewToOld,
    renamedOldToNew
  } = gatherChangedSolidityFiles(oldRef, newRef);
  const oldLock = loadLockFile(worktrees.old, lockFilePath);
  const newLock = loadLockFile(worktrees.new, lockFilePath);
  const failures = [];
  const rawLockContracts = [
    ...new Set([...Object.keys(oldLock.contracts || {}), ...Object.keys(newLock.contracts || {})])
  ];
  const lockContracts = [...new Set(rawLockContracts.map((contractId) => remapContractIdSourcePath(contractId, renamedOldToNew)))];

  let contracts = parseContractsOption(opts.contracts);
  const hasExplicitContracts = Object.hasOwn(opts, "contracts");
  const changedDiscovery = hasExplicitContracts
    ? { contracts: [], unresolvedFiles: [] }
    : discoverChangedContracts(worktrees, changedFiles);
  if (!hasExplicitContracts && contracts.length === 0) {
    if (lockContracts.length > 0) {
      contracts = lockContracts;
    } else {
      const discovery = discoverVersionedContracts(worktrees);
      contracts = discovery.contracts;
      for (const sourcePath of discovery.unresolvedFiles) {
        failures.push(
          `${sourcePath}: contains API_VERSION but no inspectable contract could be determined; pass --contracts explicitly`
        );
      }
    }
  }

  for (const sourcePath of changedDiscovery.unresolvedFiles) {
    failures.push(
      `${sourcePath}: contains API_VERSION but no inspectable contract could be determined; pass --contracts explicitly`
    );
  }

  if (!hasExplicitContracts) {
    contracts = [...new Set([...contracts, ...changedDiscovery.contracts])];
    const changedCandidates = detectChangedVersionedContracts(changedFiles, contracts, renamedOldToNew);
    contracts = [...new Set([...contracts, ...changedCandidates])];
  }

  if (lockFilePath) {
    const missingLockEntries = findVersionedChangedFilesMissingLockEntries(worktrees, changedFiles, rawLockContracts);
    for (const sourcePath of missingLockEntries) {
      failures.push(`${sourcePath}: changed contract declares API_VERSION but is missing in ${lockFilePath}`);
    }
  }

  if (contracts.length === 0) {
    const uniqueFailures = [...new Set(failures)];
    if (failures.length > 0) {
      return {
        old_ref: oldRef,
        new_ref: newRef,
        lock_file: lockFilePath || null,
        contracts_analyzed: [],
        changed_files: changedFiles,
        failures: uniqueFailures,
        results: []
      };
    }
    if (hasExplicitContracts) {
      throw new Error("No contracts to check. Provide non-empty --contracts list.");
    }
    return {
      old_ref: oldRef,
      new_ref: newRef,
      lock_file: lockFilePath || null,
      contracts_analyzed: [],
      changed_files: changedFiles,
      failures: uniqueFailures,
      results: []
    };
  }

  const contractsToAnalyze = contracts;

  const contractReports = [];

  for (const contractId of contractsToAnalyze) {
    const result = analyzeContract(worktrees, contractId, { renamedNewToOld });
    const changed = result.recommended_bump !== "none";
    const sourcePath = parseContractId(contractId).sourcePath;
    const changedInPr = changedFiles.includes(sourcePath) || Object.hasOwn(renamedOldToNew, sourcePath);
    const oldLockedExists = lockFilePath ? Object.hasOwn(oldLock.contracts, contractId) : false;
    const newLockedExists = lockFilePath ? Object.hasOwn(newLock.contracts, contractId) : false;
    const oldLocked = oldLockedExists ? oldLock.contracts[contractId] : null;
    const newLocked = newLockedExists ? newLock.contracts[contractId] : null;
    const contractStatus = {
      contract: contractId,
      changed,
      changed_in_pr: changedInPr,
      result,
      checks: []
    };

    if (result.bytecode_only_advisory) {
      contractStatus.checks.push({
        name: "bytecode-only-advisory",
        ok: true,
        reason: "bytecode changed but ABI and storage are identical; version bump is advisory"
      });
    }

    if (changed || changedInPr) {
      const oldLocked = lockFilePath ? oldLock.contracts[contractId] : null;
      const underBump = result.removed_in_new_ref
        ? {
            ok: true,
            reason: "contract is absent in new ref; deletion is allowed",
            expectedMinimumVersion: null
          }
        : validateUnderBump(result, oldLocked);
      result.expected_minimum_version = underBump.expectedMinimumVersion;
      contractStatus.checks.push({
        name: "under-bump",
        ok: underBump.ok,
        reason: underBump.reason
      });
      if (!underBump.ok) {
        failures.push(`${contractId}: ${underBump.reason}`);
      }
    }

    if (lockFilePath) {
      if (!newLockedExists) {
        if (result.removed_in_new_ref) {
          contractStatus.checks.push({
            name: "lock-entry-present",
            ok: true,
            reason: ""
          });
        } else {
          failures.push(`${contractId}: missing entry in ${lockFilePath}`);
          contractStatus.checks.push({
            name: "lock-entry-present",
            ok: false,
            reason: `missing lock entry in ${lockFilePath}`
          });
        }
      } else {
        contractStatus.checks.push({
          name: "lock-entry-present",
          ok: true,
          reason: ""
        });
      }

      if (newLockedExists && parseSemver(newLocked) === null) {
        failures.push(`${contractId}: invalid lock version format '${newLocked}'`);
        contractStatus.checks.push({
          name: "lock-format-valid",
          ok: false,
          reason: `invalid lock version format '${newLocked}'`
        });
      } else {
        contractStatus.checks.push({
          name: "lock-format-valid",
          ok: true,
          reason: ""
        });
      }

      if (oldLockedExists && parseSemver(oldLocked) === null) {
        failures.push(`${contractId}: invalid old lock version format '${oldLocked}'`);
        contractStatus.checks.push({
          name: "old-lock-format-valid",
          ok: false,
          reason: `invalid old lock version format '${oldLocked}'`
        });
      } else {
        contractStatus.checks.push({
          name: "old-lock-format-valid",
          ok: true,
          reason: ""
        });
      }

      if (oldLockedExists && newLockedExists && parseSemver(oldLocked) && parseSemver(newLocked)) {
        const lockCmp = semverCompare(newLocked, oldLocked);
        if (lockCmp !== null && lockCmp < 0) {
          failures.push(`${contractId}: lock version downgraded (${oldLocked} -> ${newLocked})`);
          contractStatus.checks.push({
            name: "lock-not-downgraded",
            ok: false,
            reason: `lock downgraded (${oldLocked} -> ${newLocked})`
          });
        } else {
          contractStatus.checks.push({
            name: "lock-not-downgraded",
            ok: true,
            reason: ""
          });
        }
      }

      if (newLockedExists && result.declared_version_new && newLocked !== result.declared_version_new) {
        failures.push(`${contractId}: lock version ${newLocked} does not match declared version ${result.declared_version_new}`);
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

      if (changed && oldLockedExists && newLockedExists && oldLocked === newLocked) {
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

    contractReports.push(contractStatus);
  }

  const uniqueFailures = [...new Set(failures)];
  return {
    old_ref: oldRef,
    new_ref: newRef,
    lock_file: lockFilePath || null,
    contracts_analyzed: contractsToAnalyze,
    changed_files: changedFiles,
    failures: uniqueFailures,
    results: contractReports
  };
}

function writeSummary(report) {
  const summaryPath = process.env.GITHUB_STEP_SUMMARY;
  if (!summaryPath) {
    return;
  }

  const lines = [];

  if (report.error) {
    lines.push("## Contract Semver Check: ERROR");
    lines.push("");
    lines.push(`**Error:** ${report.error}`);
    fs.appendFileSync(summaryPath, lines.join("\n") + "\n");
    return;
  }

  if (!report.results) {
    return;
  }

  const hasFails = report.failures && report.failures.length > 0;
  lines.push(`## Contract Semver Check: ${hasFails ? "FAIL" : "PASS"}`);
  lines.push("");
  lines.push(`Comparing \`${report.old_ref}\` to \`${report.new_ref}\``);
  lines.push("");

  if (report.results.length > 0) {
    lines.push("| Contract | Changed | Recommended bump | Declared version | Status |");
    lines.push("|----------|---------|------------------|------------------|--------|");

    for (const entry of report.results) {
      const r = entry.result || {};
      const changed = entry.changed ? "yes" : "no";
      const advisory = r.bytecode_only_advisory ? " (advisory)" : "";
      const bump = (r.raw_recommended_bump || "none") + advisory;
      const version = r.declared_version_new || "n/a";
      const failedChecks = (entry.checks || []).filter((c) => !c.ok);
      const status = failedChecks.length > 0 ? "FAIL" : "pass";
      lines.push(`| \`${entry.contract}\` | ${changed} | ${bump} | ${version} | ${status} |`);
    }
    lines.push("");
  } else {
    lines.push("No contracts analyzed.");
    lines.push("");
  }

  if (hasFails) {
    lines.push("### Failures");
    lines.push("");
    for (const failure of report.failures) {
      lines.push(`- ${failure}`);
    }
    lines.push("");
  }

  fs.appendFileSync(summaryPath, lines.join("\n") + "\n");
}

async function main() {
  const opts = parseArgs(process.argv);
  ensureCommand(opts);

  const oldRef = opts["old-ref"] || "HEAD~1";
  const newRef = opts["new-ref"] || "HEAD";

  if (Object.hasOwn(opts, "policy")) {
    throw new Error("`--policy` is not supported. sol-semver has a single built-in classification mode.");
  }

  let worktrees;
  let exitPayload;
  let exitCode = 0;

  try {
    worktrees = createTempWorktrees(oldRef, newRef);

    // Parallelize the two independent worktree builds.
    // Per-contract targeted builds are not supported by forge today;
    // parallelization is the main lever for reducing CI wall-clock time.
    const buildResults = await Promise.allSettled([
      prepareWorktreeAsync(worktrees.old),
      prepareWorktreeAsync(worktrees.new)
    ]);
    const buildFailure = buildResults.find((r) => r.status === "rejected");
    if (buildFailure) {
      throw buildFailure.reason;
    }

    if (opts.command === "diff") {
      const contractId = opts.contract;
      ensureContractId(contractId);
      exitPayload = analyzeContract(worktrees, contractId);
      exitCode = 0;
    } else {
      const report = buildCheckReport(opts, worktrees);
      writeSummary(report);
      exitPayload = report;
      exitCode = report.failures.length > 0 ? 1 : 0;
    }
  } catch (error) {
    exitPayload = {
      error: error instanceof Error ? error.message : String(error)
    };
    writeSummary(exitPayload);
    exitCode = 1;
  } finally {
    cleanupTempWorktrees(worktrees);
  }

  console.log(JSON.stringify(exitPayload, null, 2));
  process.exit(exitCode);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
