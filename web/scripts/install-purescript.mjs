import { createHash } from "node:crypto";
import {
  chmodSync,
  existsSync,
  mkdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const version = process.env.PURESCRIPT_VERSION || "0.15.16";

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
const tempRoot = makeTempRoot();
const archivePath = join(tempRoot, artifact.name);

try {
  console.log(`downloading PureScript ${version} from ${archiveUrl}`);
  const archive = await download(archiveUrl);
  verifySha256(archive, artifact.sha256, artifact.name);
  writeFileSync(archivePath, archive);
  extractArchive(archivePath, tempRoot);
  installCompiler(join(tempRoot, "purescript", "purs"), target);
  assertCompilerVersion(target, version);
  console.log(`installed purs ${version} at ${target}`);
} finally {
  rmSync(tempRoot, { recursive: true, force: true });
}

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

function makeTempRoot() {
  const result = spawnSync("mktemp", ["-d", join(tmpdir(), "infernix-purs-XXXXXX")], {
    encoding: "utf8",
  });
  if (result.status !== 0) {
    throw new Error(`mktemp failed: ${result.stderr}`);
  }
  return result.stdout.trim();
}

function extractArchive(archivePath, destination) {
  const result = spawnSync("tar", ["-xzf", archivePath, "-C", destination], {
    encoding: "utf8",
  });
  if (result.status !== 0) {
    throw new Error(`tar extraction failed: ${result.stderr}`);
  }
}

function installCompiler(source, destination) {
  if (!existsSync(source)) {
    throw new Error(`PureScript archive did not contain ${source}`);
  }
  const bytes = readFileSync(source);
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
