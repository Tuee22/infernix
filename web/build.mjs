import { cpSync, mkdirSync, rmSync } from "node:fs";
import { join } from "node:path";
import { execFileSync } from "node:child_process";

const webRoot = process.cwd();
const distRoot = join(webRoot, "dist");
const generatedRoot = join(webRoot, "generated");
const srcRoot = join(webRoot, "src");

rmSync(distRoot, { force: true, recursive: true });
mkdirSync(distRoot, { recursive: true });
mkdirSync(generatedRoot, { recursive: true });

execFileSync("../.build/infernix", ["internal", "generate-web-contracts", generatedRoot], {
  cwd: webRoot,
  stdio: "inherit",
});

cpSync(join(srcRoot, "index.html"), join(distRoot, "index.html"));
cpSync(join(srcRoot, "app.js"), join(distRoot, "app.js"));
cpSync(join(srcRoot, "catalog.js"), join(distRoot, "catalog.js"));
mkdirSync(join(distRoot, "generated"), { recursive: true });
cpSync(join(generatedRoot, "Generated", "contracts.js"), join(distRoot, "generated", "contracts.js"));
