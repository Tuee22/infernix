// Phase 3 Sprint 3.10 — Playwright runs inside the launcher container,
// fed by a typed JSON fixture written by `infernix test e2e` at test
// start (see `runEndToEnd` in `src/Infernix/CLI.hs`). The fixture
// replaces the retired `INFERNIX_EDGE_PORT` / `INFERNIX_PLAYWRIGHT_HOST`
// / `INFERNIX_EXPECT_*` env-var family so no Playwright code path
// reads `process.env.INFERNIX_*` anymore.
import { readFileSync } from "node:fs";
import { defineConfig } from "@playwright/test";

const fixturePath = "/workspace/.data/runtime/playwright-fixture.json";
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
