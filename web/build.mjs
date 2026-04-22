import { cpSync, mkdirSync, mkdtempSync, renameSync, rmSync } from "node:fs";
import { join } from "node:path";
import { execFileSync } from "node:child_process";

const webRoot = process.cwd();
const repoBuildRoot = process.env.INFERNIX_BUILD_ROOT ?? join(webRoot, "..", ".build");
const cabalBuildDir = process.env.INFERNIX_CABAL_BUILDDIR ?? "../.build/cabal";
const distRoot = join(webRoot, "dist");
const generatedRoot = join(repoBuildRoot, "web-generated");
const srcRoot = join(webRoot, "src");

mkdirSync(repoBuildRoot, { recursive: true });
const distStagingRoot = mkdtempSync(join(webRoot, ".dist-build-"));
const generatedStagingParent = mkdtempSync(join(repoBuildRoot, "web-generated-build-"));
const generatedStagingRoot = join(generatedStagingParent, "web-generated");
const stagedDistRoot = join(distStagingRoot, "dist");
mkdirSync(stagedDistRoot, { recursive: true });
mkdirSync(generatedStagingRoot, { recursive: true });

const runtimeModeArgs = process.env.INFERNIX_RUNTIME_MODE ? ["--runtime-mode", process.env.INFERNIX_RUNTIME_MODE] : [];

execFileSync(
  "cabal",
  ["--builddir=" + cabalBuildDir, "run", "exe:infernix", "--", ...runtimeModeArgs, "internal", "generate-web-contracts", generatedStagingRoot],
  {
    cwd: webRoot,
    stdio: "inherit",
  },
);

cpSync(join(srcRoot, "index.html"), join(stagedDistRoot, "index.html"));
cpSync(join(srcRoot, "app.js"), join(stagedDistRoot, "app.js"));
cpSync(join(srcRoot, "catalog.js"), join(stagedDistRoot, "catalog.js"));
cpSync(join(srcRoot, "workbench.js"), join(stagedDistRoot, "workbench.js"));
mkdirSync(join(stagedDistRoot, "generated"), { recursive: true });
cpSync(join(generatedStagingRoot, "Generated", "contracts.js"), join(stagedDistRoot, "generated", "contracts.js"));

rmSync(generatedRoot, { force: true, recursive: true });
renameSync(generatedStagingRoot, generatedRoot);
rmSync(distRoot, { force: true, recursive: true });
renameSync(stagedDistRoot, distRoot);
rmSync(generatedStagingParent, { force: true, recursive: true });
rmSync(distStagingRoot, { force: true, recursive: true });
