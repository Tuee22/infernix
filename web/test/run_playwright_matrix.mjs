import { readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const webRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const repoRoot = resolve(webRoot, "..");
const infernixCommand =
  process.env.INFERNIX_PLAYWRIGHT_INFERNIX ??
  (process.env.INFERNIX_BUILD_ROOT ? "infernix" : "../.build/infernix");
const playwrightHost = process.env.INFERNIX_PLAYWRIGHT_HOST ?? "127.0.0.1";
const generatedSubstratePath = resolve(process.env.INFERNIX_BUILD_ROOT ?? resolve(repoRoot, ".build"), "infernix-substrate.dhall");

function sanitizedPlaywrightEnv(extraEnvironment = {}) {
  const env = {
    ...process.env,
    ...extraEnvironment,
  };
  delete env.FORCE_COLOR;
  delete env.NO_COLOR;
  return env;
}

function runInfernix(args) {
  const result = spawnSync(infernixCommand, args, {
    cwd: webRoot,
    stdio: "inherit",
    env: process.env,
  });
  if (result.status !== 0) {
    throw new Error(`infernix ${args.join(" ")} failed`);
  }
}

function loadPublishedEdgePort() {
  return String(
    Number.parseInt(readFileSync(resolve(repoRoot, ".data", "runtime", "edge-port.json"), "utf8").trim(), 10),
  );
}

function loadActiveSubstrateId() {
  const rawValue = readFileSync(generatedSubstratePath, "utf8").replace(/^\s*\{-[^\n]*\}\s*\n/, "");
  return JSON.parse(rawValue).runtimeMode;
}

let exitStatus = 0;

try {
  runInfernix(["cluster", "up"]);
  const substrateId = loadActiveSubstrateId();
  process.stdout.write(`playwright substrate: ${substrateId}\n`);
  const edgePort = loadPublishedEdgePort();
  const result = spawnSync("npm", ["exec", "--", "playwright", "test", "./playwright/inference.spec.js", "--reporter=list", "--timeout=30000"], {
    cwd: webRoot,
    stdio: "inherit",
    env: sanitizedPlaywrightEnv({
      INFERNIX_EDGE_PORT: edgePort,
      INFERNIX_PLAYWRIGHT_HOST: playwrightHost,
    }),
  });
  exitStatus = result.status ?? 1;
} catch (error) {
  process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
  exitStatus = 1;
} finally {
  try {
    runInfernix(["cluster", "down"]);
  } catch (error) {
    process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
    if (exitStatus === 0) {
      exitStatus = 1;
    }
  }
}

if (exitStatus !== 0) {
  process.exit(exitStatus);
}
