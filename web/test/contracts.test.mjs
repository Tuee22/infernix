import assert from "node:assert/strict";
import { apiBasePath, maxInlineOutputLength, models, runtimeMode } from "../dist/generated/contracts.js";
import { filterModels } from "../dist/catalog.js";
import { catalogCards, describeCompletedRequest, publicationSummary, selectionSummary } from "../dist/workbench.js";

assert.equal(apiBasePath, "/api");
assert.equal(maxInlineOutputLength, 80);
assert.equal(
  models.length,
  {
    "apple-silicon": 15,
    "linux-cpu": 12,
    "linux-cuda": 16,
  }[runtimeMode],
);
assert.ok(models.every((model) => model.selectedEngine));
assert.ok(models.every((model) => model.runtimeLane));
assert.ok(filterModels(models, "qwen").some((model) => model.modelId.includes("qwen")));
assert.deepEqual(
  catalogCards(models, "", models[0]?.modelId ?? null).map((card) => card.modelId),
  models.map((model) => model.modelId),
);
assert.equal(selectionSummary(models[0]).inputLabel, models[0].requestShape[0].label);
assert.deepEqual(
  publicationSummary(
    {
      runtimeMode,
      controlPlaneContext: "host-native",
      daemonLocation: "control-plane-host",
      catalogSource: "generated-build-root",
      edgePort: 9090,
      apiUpstream: { mode: "host-daemon-bridge" },
      demoConfigPath: "/tmp/infernix-demo.dhall",
      routes: [{ path: "/api", purpose: "Service API" }],
      upstreams: [{ id: "service", healthStatus: "ready", targetSurface: "host-native daemon bridge", durableBackendState: "pulsar-transport and minio-durable-state" }],
    },
    runtimeMode,
  ),
  {
    runtimeMode,
    controlPlaneContext: "host-native",
    daemonLocation: "control-plane-host",
    catalogSource: "generated-build-root",
    edgePort: "9090",
    apiUpstreamMode: "host-daemon-bridge",
    demoConfigPath: "/tmp/infernix-demo.dhall",
    routes: [{ path: "/api", purpose: "Service API" }],
    upstreams: [{ id: "service", healthStatus: "ready", targetSurface: "host-native daemon bridge", durableBackendState: "pulsar-transport and minio-durable-state" }],
  },
);
assert.deepEqual(publicationSummary(null, runtimeMode), {
  runtimeMode,
  controlPlaneContext: "Unavailable",
  daemonLocation: "Unavailable",
  catalogSource: "Unavailable",
  edgePort: "Not published",
  apiUpstreamMode: "Unavailable",
  demoConfigPath: "Unavailable",
  routes: [],
  upstreams: [],
});
assert.equal(selectionSummary(models[0]).artifactType, models[0].artifactType);
assert.equal(typeof selectionSummary(models[0]).familyLabel, "string");
assert.equal(typeof selectionSummary(models[0]).submitLabel, "string");
assert.equal(typeof selectionSummary(models[0]).resultLabel, "string");
const completedRequest = describeCompletedRequest(
  { requestId: "req-1", payload: { inlineOutput: null, objectRef: "results/req-1.txt" } },
  models[0],
);
assert.equal(completedRequest.statusText, `Completed request req-1 on ${models[0].selectedEngine}`);
assert.equal(completedRequest.resultLabel, selectionSummary(models[0]).resultLabel);
assert.equal(completedRequest.outputText, "Stored object reference: results/req-1.txt");
assert.equal(completedRequest.objectHref, "/objects/results/req-1.txt");
assert.equal(typeof completedRequest.objectLinkLabel, "string");

console.log("web unit tests passed");
