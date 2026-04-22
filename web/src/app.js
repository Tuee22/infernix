import { apiBasePath, runtimeMode as generatedRuntimeMode } from "./generated/contracts.js";
import {
  catalogCards,
  describeCompletedRequest,
  publicationSummary,
  selectedModel,
  selectionSummary,
} from "./workbench.js";

const state = {
  models: [],
  publication: null,
  runtimeMode: generatedRuntimeMode,
  selectedModelId: null,
};

const catalogEl = document.querySelector("#catalog");
const catalogCountEl = document.querySelector("#catalog-count");
const searchEl = document.querySelector("#search");
const formEl = document.querySelector("#inference-form");
const inputEl = document.querySelector("#inputText");
const inputLabelEl = document.querySelector("#input-label");
const modelNameEl = document.querySelector("#selected-model-name");
const modelEngineEl = document.querySelector("#selected-engine");
const modelLaneEl = document.querySelector("#selected-lane");
const modelFamilyEl = document.querySelector("#selected-family");
const modelArtifactEl = document.querySelector("#selected-artifact-type");
const modelNotesEl = document.querySelector("#selected-notes");
const requestGuidanceEl = document.querySelector("#request-guidance");
const runtimeModeEl = document.querySelector("#runtime-mode");
const controlPlaneContextEl = document.querySelector("#control-plane-context");
const daemonLocationEl = document.querySelector("#daemon-location");
const catalogSourceEl = document.querySelector("#catalog-source");
const edgePortEl = document.querySelector("#edge-port");
const apiUpstreamModeEl = document.querySelector("#api-upstream-mode");
const demoConfigPathEl = document.querySelector("#demo-config-path");
const routeListEl = document.querySelector("#route-list");
const upstreamListEl = document.querySelector("#upstream-list");
const selectionStatusEl = document.querySelector("#selection-status");
const requestStatusEl = document.querySelector("#request-status");
const submitButtonEl = document.querySelector("#submit-button");
const resultLabelEl = document.querySelector("#result-label");
const resultOutputEl = document.querySelector("#result-output");
const objectLinkContainerEl = document.querySelector("#object-link-container");

function renderSelectionDetails() {
  const summary = selectionSummary(selectedModel(state.models, state.selectedModelId));
  modelNameEl.textContent = summary.name;
  modelEngineEl.textContent = summary.engine;
  modelLaneEl.textContent = summary.lane;
  modelFamilyEl.textContent = summary.familyLabel;
  modelArtifactEl.textContent = summary.artifactType;
  modelNotesEl.textContent = summary.notes;
  inputLabelEl.textContent = summary.inputLabel;
  inputEl.placeholder = summary.placeholder;
  requestGuidanceEl.textContent = summary.requestGuidance;
  submitButtonEl.textContent = summary.submitLabel;
  resultLabelEl.textContent = summary.resultLabel;
}

function renderCatalog() {
  const query = searchEl.value;
  const visibleModels = catalogCards(state.models, query, state.selectedModelId);

  catalogCountEl.textContent = `${visibleModels.length} visible / ${state.models.length} total`;
  runtimeModeEl.textContent = state.runtimeMode;
  catalogEl.innerHTML = "";

  if (visibleModels.length === 0) {
    catalogEl.innerHTML = `<p class="muted">${
      state.models.length === 0 && !query ? "Live catalog unavailable." : `No models match “${query}”.`
    }</p>`;
    renderSelectionDetails();
    return;
  }

  for (const model of visibleModels) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = `catalog-item${model.isActive ? " active" : ""}`;
    button.innerHTML = `
      <strong>${model.displayName}</strong>
      <div class="muted">${model.modelId}</div>
      <div class="muted">${model.family} · ${model.artifactType}</div>
      <div class="muted">${model.selectedEngine}</div>
      <p>${model.description}</p>
    `;
    button.addEventListener("click", () => {
      state.selectedModelId = model.modelId;
      selectionStatusEl.textContent = `${model.displayName} selected on ${model.selectedEngine}`;
      renderCatalog();
    });
    catalogEl.appendChild(button);
  }

  renderSelectionDetails();
}

function renderPublication() {
  const summary = publicationSummary(state.publication, state.runtimeMode);
  runtimeModeEl.textContent = summary.runtimeMode;
  controlPlaneContextEl.textContent = summary.controlPlaneContext;
  daemonLocationEl.textContent = summary.daemonLocation;
  catalogSourceEl.textContent = summary.catalogSource;
  edgePortEl.textContent = summary.edgePort;
  apiUpstreamModeEl.textContent = summary.apiUpstreamMode;
  demoConfigPathEl.textContent = summary.demoConfigPath;
  routeListEl.replaceChildren(
    ...summary.routes.map((route) => {
      const item = document.createElement("li");
      item.textContent = `${route.path} -> ${route.purpose}`;
      return item;
    }),
  );
  upstreamListEl.replaceChildren(
    ...summary.upstreams.map((upstream) => {
      const item = document.createElement("li");
      item.textContent = `${upstream.id} -> ${upstream.healthStatus} via ${upstream.targetSurface} (${upstream.durableBackendState})`;
      return item;
    }),
  );
}

async function loadCatalog() {
  try {
    const response = await fetch(`${apiBasePath}/models`);
    if (!response.ok) {
      throw new Error(`Catalog request failed with ${response.status}`);
    }
    state.models = await response.json();
    state.runtimeMode = state.models[0]?.runtimeMode ?? state.runtimeMode;
    if (!state.models.find((model) => model.modelId === state.selectedModelId)) {
      state.selectedModelId = state.models[0]?.modelId ?? null;
    }
    selectionStatusEl.textContent = `Model catalog loaded for ${state.runtimeMode}`;
    selectionStatusEl.className = "status success";
  } catch (error) {
    state.models = [];
    state.selectedModelId = null;
    selectionStatusEl.textContent = error.message;
    selectionStatusEl.className = "status error";
  }
  renderCatalog();
  renderPublication();
}

async function loadPublication() {
  try {
    const response = await fetch(`${apiBasePath}/publication`);
    if (!response.ok) {
      throw new Error(`Publication request failed with ${response.status}`);
    }
    state.publication = await response.json();
  } catch (error) {
    state.publication = null;
  }
  renderPublication();
}

async function submitInference(event) {
  event.preventDefault();
  requestStatusEl.textContent = "Submitting request…";
  requestStatusEl.className = "status muted";
  objectLinkContainerEl.textContent = "";
  try {
    const model = selectedModel(state.models, state.selectedModelId);
    const response = await fetch(`${apiBasePath}/inference`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        requestModelId: state.selectedModelId,
        inputText: inputEl.value,
      }),
    });
    const payload = await response.json();
    if (!response.ok) {
      throw new Error(payload.message ?? "Request failed");
    }
    const requestSummary = describeCompletedRequest(payload, model);
    requestStatusEl.textContent = requestSummary.statusText;
    requestStatusEl.className = "status success";
    resultLabelEl.textContent = requestSummary.resultLabel;
    resultOutputEl.textContent = requestSummary.outputText;
    if (requestSummary.objectHref) {
      const link = document.createElement("a");
      link.href = requestSummary.objectHref;
      link.textContent = requestSummary.objectLinkLabel ?? "Open large output";
      objectLinkContainerEl.replaceChildren(link);
    }
  } catch (error) {
    requestStatusEl.textContent = error.message;
    requestStatusEl.className = "status error";
    resultOutputEl.textContent = "No result yet.";
    objectLinkContainerEl.textContent = "";
  }
}

searchEl.addEventListener("input", renderCatalog);
formEl.addEventListener("submit", submitInference);

await Promise.all([loadCatalog(), loadPublication()]);
