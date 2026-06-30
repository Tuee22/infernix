import { createHash } from "node:crypto";
import {
  chmodSync,
  existsSync,
  mkdirSync,
  readFileSync,
  writeFileSync,
} from "node:fs";
import { dirname, join, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { gunzipSync } from "node:zlib";

// Phase 5 Sprint 5.9: `PURESCRIPT_VERSION` env override retired. The
// supported version is hardcoded here per the no-env-var doctrine
// (see `documents/development/no_env_vars.md`). Operators bump the
// PureScript compiler by editing this file directly; the
// `verifySha256` step below ensures the matching artifact metadata is
// updated together.
const version = "0.15.16";

const artifacts = {
  "linux:x64": {
    name: "linux64.tar.gz",
    sha256: "44da9efb8a4e14519e8fd5350acc377a4b981e42351a78c53e9f84045bf38e22",
  },
  "linux:arm64": {
    name: "linux-arm64.tar.gz",
    sha256: "b8d153c5c6e0d8c9618a90824eb342b5818e14a92b0b6cdff753d9b353a927f3",
  },
  "darwin:x64": {
    name: "macos.tar.gz",
    sha256: "9f5bfdb7a468241c7106660bc6bd0209ce3f19ad197516ccdcd5c17df81958b6",
  },
  "darwin:arm64": {
    name: "macos-arm64.tar.gz",
    sha256: "63f15a13e226efc260fb025c4a4ad7f66429b6685da607040b7bcc209332fcc4",
  },
};

const packageRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const binDir = join(packageRoot, "node_modules", ".bin");
const target = join(binDir, "purs");
const platformKey = `${process.platform}:${process.arch}`;
const artifact = artifacts[platformKey];

if (!artifact) {
  throw new Error(`unsupported PureScript compiler platform: ${platformKey}`);
}

if (existingCompilerIsCurrent(target)) {
  console.log(`purs ${version} already installed at ${target}`);
  process.exit(0);
}

mkdirSync(binDir, { recursive: true });

const archiveUrl = `https://github.com/purescript/purescript/releases/download/v${version}/${artifact.name}`;

console.log(`downloading PureScript ${version} from ${archiveUrl}`);
const archive = await download(archiveUrl);
verifySha256(archive, artifact.sha256, artifact.name);
installCompilerBytes(extractCompilerFromArchive(archive), target);
assertCompilerVersion(target, version);
console.log(`installed purs ${version} at ${target}`);

function existingCompilerIsCurrent(path) {
  if (!existsSync(path)) {
    return false;
  }
  const result = spawnSync(path, ["--version"], { encoding: "utf8" });
  return result.status === 0 && result.stdout.trim() === version;
}

async function download(url) {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`failed to download ${url}: HTTP ${response.status}`);
  }
  return Buffer.from(await response.arrayBuffer());
}

function verifySha256(bytes, expected, label) {
  const actual = createHash("sha256").update(bytes).digest("hex");
  if (actual !== expected) {
    throw new Error(`sha256 mismatch for ${label}: expected ${expected}, got ${actual}`);
  }
}

function extractCompilerFromArchive(archiveBytes) {
  const tarBytes = gunzipSync(archiveBytes);
  const wantedPath = "purescript/purs";
  let offset = 0;
  while (offset + 512 <= tarBytes.length) {
    const header = tarBytes.subarray(offset, offset + 512);
    if (header.every((byte) => byte === 0)) {
      break;
    }
    const name = readTarString(header, 0, 100);
    const prefix = readTarString(header, 345, 155);
    const entryPath = prefix ? `${prefix}/${name}` : name;
    const sizeText = readTarString(header, 124, 12).trim();
    const size = parseInt(sizeText || "0", 8);
    const typeFlag = String.fromCharCode(header[156] || 0);
    const dataOffset = offset + 512;
    if ((typeFlag === "0" || typeFlag === "\0") && entryPath === wantedPath) {
      return Buffer.from(tarBytes.subarray(dataOffset, dataOffset + size));
    }
    offset = dataOffset + Math.ceil(size / 512) * 512;
  }
  throw new Error(`PureScript archive did not contain ${wantedPath}`);
}

function readTarString(buffer, offset, length) {
  const bytes = buffer.subarray(offset, offset + length);
  const terminator = bytes.indexOf(0);
  return bytes.subarray(0, terminator === -1 ? bytes.length : terminator).toString("utf8");
}

function installCompilerBytes(bytes, destination) {
  writeFileSync(destination, bytes);
  chmodSync(destination, 0o755);
}

function assertCompilerVersion(path, expected) {
  const result = spawnSync(path, ["--version"], { encoding: "utf8" });
  if (result.status !== 0) {
    throw new Error(`installed purs failed to run: ${result.stderr}`);
  }
  const actual = result.stdout.trim();
  if (actual !== expected) {
    throw new Error(`installed purs version mismatch: expected ${expected}, got ${actual}`);
  }
}
