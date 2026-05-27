import { existsSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

// Phase 5 Sprint 5.9: `INFERNIX_PLAYWRIGHT_INFERNIX` +
// `INFERNIX_BUILD_ROOT` env reads retired. The supported binary
// location is typed: the Linux launcher image installs the
// `infernix` binary at `/usr/local/bin/infernix` (per
// `docker/linux-substrate.Dockerfile`), and the Apple host build
// places it at `<repoRoot>/.build/infernix`. This script picks
// whichever exists rather than consulting any env var or `$PATH`.
const webRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const repoRoot = resolve(webRoot, "..");

const candidates = [
  "/usr/local/bin/infernix",
  resolve(repoRoot, ".build", "infernix"),
];

const infernixCommand = candidates.find((candidate) => existsSync(candidate));
if (!infernixCommand) {
  console.error(
    "could not locate the infernix binary at any supported path:\n  " +
      candidates.join("\n  ")
  );
  process.exit(2);
}

const result = spawnSync(infernixCommand, ["test", "e2e"], {
  cwd: repoRoot,
  stdio: "inherit",
  // The supported Playwright invocation flows config through the
  // typed Dhall-backed fixture (see Sprint 3.10's playwright config);
  // no env-var inheritance is required for this launcher wrapper.
  env: {
    HOME: "/tmp",
    PATH: "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
    LANG: "C.UTF-8",
    LC_ALL: "C.UTF-8",
  },
});

process.exit(result.status ?? 1);
