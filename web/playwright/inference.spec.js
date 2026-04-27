import { test, expect } from "playwright/test";

const edgePort = Number(process.env.INFERNIX_EDGE_PORT ?? "9090");
const edgeHost = process.env.INFERNIX_PLAYWRIGHT_HOST ?? "127.0.0.1";
const baseUrl = `http://${edgeHost}:${edgePort}`;
const expectedDaemonLocation = process.env.INFERNIX_EXPECT_DAEMON_LOCATION;
const expectedApiUpstreamMode = process.env.INFERNIX_EXPECT_API_UPSTREAM_MODE;

async function loadSerializedCatalog(request) {
  const publicationResponse = await request.get(`${baseUrl}/api/publication`);
  const demoConfigResponse = await request.get(`${baseUrl}/api/demo-config`);
  expect(publicationResponse.ok()).toBeTruthy();
  expect(demoConfigResponse.ok()).toBeTruthy();
  const publication = await publicationResponse.json();
  const demoConfig = await demoConfigResponse.json();
  return { publication, models: demoConfig.models };
}

test("active mode catalog is fully exercised through the routed HTTP surface", async ({ request }) => {
  const { publication, models } = await loadSerializedCatalog(request);
  const homeResponse = await request.get(`${baseUrl}/`);
  expect(homeResponse.ok()).toBeTruthy();
  expect(await homeResponse.text()).toContain("Infernix");

  const catalogResponse = await request.get(`${baseUrl}/api/models`);
  expect(catalogResponse.ok()).toBeTruthy();
  const routedModels = await catalogResponse.json();
  expect(routedModels).toEqual(models);
  expect(publication.runtimeMode).toBe(models[0]?.runtimeMode ?? publication.runtimeMode);
  expect(publication.workerExecutionMode).toBe("process-isolated-engine-workers");
  expect(publication.workerAdapterMode).toBe("engine-specific-runner-defaults");
  expect(publication.artifactAcquisitionMode).toBe("engine-ready-artifact-manifests");

  for (const model of models) {
    const inferenceResponse = await request.post(`${baseUrl}/api/inference`, {
      data: {
        requestModelId: model.modelId,
        inputText: `exercise ${model.modelId}`,
      },
    });
    expect(inferenceResponse.ok()).toBeTruthy();
    const payload = await inferenceResponse.json();
    expect(payload.resultModelId).toBe(model.modelId);
    expect(payload.runtimeMode).toBe(model.runtimeMode);
    expect(payload.selectedEngine).toBe(model.selectedEngine);
  }
});

test("manual inference workbench renders generated catalog entries and result state in the browser", async ({ page, request }) => {
  const { publication, models } = await loadSerializedCatalog(request);

  await page.goto(baseUrl);
  await expect(page.locator("h1")).toHaveText("Infernix");
  await expect(page.locator("#runtime-mode")).toHaveText(publication.runtimeMode);
  await expect(page.locator("#control-plane-context")).not.toHaveText("loading…");
  await expect(page.locator("#daemon-location")).not.toHaveText("loading…");
  if (expectedDaemonLocation) {
    await expect(page.locator("#daemon-location")).toHaveText(expectedDaemonLocation);
  }
  await expect(page.locator("#catalog-source")).not.toHaveText("loading…");
  if (expectedApiUpstreamMode) {
    await expect(page.locator("#api-upstream-mode")).toHaveText(expectedApiUpstreamMode);
  }
  await expect(page.locator("#route-list li")).toHaveCount(publication.routes.length);
  await expect(page.locator("#upstream-list li")).toHaveCount(publication.upstreams.length);
  const catalogItems = page.locator(".catalog-item");
  await expect(catalogItems).toHaveCount(models.length);

  for (const [index, model] of models.entries()) {
    await catalogItems.nth(index).click();
    await expect(page.locator("#selected-model-name")).toHaveText(model.displayName);
    await expect(page.locator("#selected-engine")).toHaveText(model.selectedEngine);
    await expect(page.locator("#selected-family")).not.toHaveText("Loading…");
    await expect(page.locator("#selected-artifact-type")).toHaveText(model.artifactType);
    await expect(page.locator("#request-guidance")).not.toHaveText(/Select a model/);
    await expect(page.locator("#submit-button")).not.toHaveText("Run Inference");

    await page.locator("#inputText").fill(`browser exercise ${model.modelId} ${"x".repeat(120)}`);
    await page.locator("#submit-button").click();

    await expect(page.locator("#request-status")).toContainText("Completed request");
    await expect(page.locator("#request-status")).toContainText(model.selectedEngine);
    await expect(page.locator("#result-label")).not.toHaveText("Result payload");
    await expect(page.locator("#result-output")).toContainText("Stored object reference");
    await expect(page.locator("#object-link-container a")).toHaveAttribute("href", /\/objects\/results\/req-/);
    await expect(page.locator("#object-link-container a")).not.toHaveText("Open large output");
  }
});
