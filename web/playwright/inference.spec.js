// Phase 7 follow-on (May 26, 2026): the legacy stateless workbench
// surface that this spec used to exercise (`POST /api/inference`,
// the workbench SPA DOM, the `/objects/:objectRef` shape) is retired
// in favor of the durable-context Chat surface. Per the legacy-
// tracking ledger, this spec is slated for replacement by a
// durable-context Chat E2E that exercises Keycloak auth + the
// `/ws` WebSocket transport + the `/api/objects` presigned MinIO
// flow. Until that replacement lands, the spec here is a minimal
// routed-surface smoke test that confirms the operator-facing edge
// is up and serves the SPA + the published platform-state JSON
// endpoints. The deeper inference correctness is covered end-to-end
// by `infernix test integration`'s per-model Pulsar roundtrip
// against the same cluster.
import { readFileSync } from "node:fs";
import { test, expect } from "playwright/test";

const fixturePath = "/workspace/.data/runtime/playwright-fixture.json";
const fixture = JSON.parse(readFileSync(fixturePath, "utf8"));

test("routed edge surfaces the SPA + the published platform state", async ({ page, request }) => {
  const baseUrl = `http://${fixture.host}:${fixture.edgePort}`;

  const publicationResponse = await request.get(`${baseUrl}/api/publication`);
  expect(publicationResponse.ok()).toBeTruthy();
  const publication = await publicationResponse.json();
  expect(publication.runtimeMode).toBeTruthy();

  const demoConfigResponse = await request.get(`${baseUrl}/api/demo-config`);
  expect(demoConfigResponse.ok()).toBeTruthy();
  const demoConfig = await demoConfigResponse.json();
  expect(Array.isArray(demoConfig.models)).toBe(true);

  const catalogResponse = await request.get(`${baseUrl}/api/models`);
  expect(catalogResponse.ok()).toBeTruthy();
  const routedModels = await catalogResponse.json();
  expect(routedModels).toEqual(demoConfig.models);

  await page.goto(baseUrl);
  await expect(page.locator("h1")).toHaveText("Infernix");
});
