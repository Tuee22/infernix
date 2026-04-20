import { readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const webRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const repoRoot = resolve(webRoot, "..");
const runtimeModes = process.env.INFERNIX_RUNTIME_MODE
  ? [process.env.INFERNIX_RUNTIME_MODE]
  : ["apple-silicon", "linux-cpu", "linux-cuda"];
const infernixCommand =
  process.env.INFERNIX_PLAYWRIGHT_INFERNIX ??
  (process.env.INFERNIX_BUILD_ROOT ? "infernix" : "../.build/infernix");
const playwrightHost = process.env.INFERNIX_PLAYWRIGHT_HOST ?? "127.0.0.1";

function runInfernix(runtimeMode, args) {
  const result = spawnSync(infernixCommand, ["--runtime-mode", runtimeMode, ...args], {
    cwd: webRoot,
    stdio: "inherit",
    env: process.env,
  });
  if (result.status !== 0) {
    throw new Error(`infernix ${args.join(" ")} failed for ${runtimeMode}`);
  }
}

function loadPublishedEdgePort() {
  return String(
    Number.parseInt(readFileSync(resolve(repoRoot, ".data", "runtime", "edge-port.json"), "utf8").trim(), 10),
  );
}

for (const runtimeMode of runtimeModes) {
  process.stdout.write(`playwright matrix: runtime mode ${runtimeMode}\n`);
  let exitStatus = 0;
  try {
    runInfernix(runtimeMode, ["cluster", "up"]);
    const edgePort = loadPublishedEdgePort();
    const result = spawnSync("npx", ["playwright", "test"], {
      cwd: webRoot,
      stdio: "inherit",
      env: {
        ...process.env,
        INFERNIX_RUNTIME_MODE: runtimeMode,
        INFERNIX_EDGE_PORT: edgePort,
        INFERNIX_PLAYWRIGHT_HOST: playwrightHost,
      },
    });
    exitStatus = result.status ?? 1;
  } catch (error) {
    process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
    exitStatus = 1;
  } finally {
    try {
      runInfernix(runtimeMode, ["cluster", "down"]);
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
}
