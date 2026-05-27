// Phase 3 Sprint 3.10 — Playwright is fed by a typed JSON fixture
// written by `infernix test e2e` at test start. The repo-relative
// fixture path works both in the Linux launcher (`/workspace`) and
// on the Apple host-native checkout, replacing the retired
// `INFERNIX_EDGE_PORT` / `INFERNIX_PLAYWRIGHT_HOST` /
// `INFERNIX_EXPECT_*` env-var family.
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { defineConfig } from "@playwright/test";

const fixturePath = fileURLToPath(new URL("../.data/runtime/playwright-fixture.json", import.meta.url));
const fixture = JSON.parse(readFileSync(fixturePath, "utf8"));

export default defineConfig({
  testDir: "./playwright",
  reporter: "list",
  timeout: 30000,
  use: {
    baseURL: `http://${fixture.host}:${fixture.edgePort}`,
  },
  projects: [
    {
      name: "infernix-e2e",
      use: {
        baseURL: `http://${fixture.host}:${fixture.edgePort}`,
        infernixFixture: fixture,
      },
    },
  ],
});
