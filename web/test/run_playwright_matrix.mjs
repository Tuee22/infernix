import { spawnSync } from "node:child_process";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const webRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const repoRoot = resolve(webRoot, "..");
const infernixCommand =
  process.env.INFERNIX_PLAYWRIGHT_INFERNIX ??
  (process.env.INFERNIX_BUILD_ROOT ? "infernix" : "../.build/infernix");

function sanitizedEnvironment() {
  const env = {
    ...process.env,
  };
  delete env.FORCE_COLOR;
  delete env.NO_COLOR;
  return env;
}

const result = spawnSync(infernixCommand, ["test", "e2e"], {
  cwd: repoRoot,
  stdio: "inherit",
  env: sanitizedEnvironment(),
});

process.exit(result.status ?? 1);
