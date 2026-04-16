import { apiBasePath, models as generatedModels } from "./generated/contracts.js";
import { filterModels } from "./catalog.js";

const state = {
  models: generatedModels,
  selectedModelId: generatedModels[0]?.modelId ?? null,
};

const catalogEl = document.querySelector("#catalog");
const searchEl = document.querySelector("#search");
const formEl = document.querySelector("#inference-form");
const inputEl = document.querySelector("#inputText");
const selectionStatusEl = document.querySelector("#selection-status");
const requestStatusEl = document.querySelector("#request-status");
const resultOutputEl = document.querySelector("#result-output");
const objectLinkContainerEl = document.querySelector("#object-link-container");

function renderCatalog() {
  const query = searchEl.value;
  const visibleModels = filterModels(state.models, query);

  catalogEl.innerHTML = "";
  if (visibleModels.length === 0) {
    catalogEl.innerHTML = `<p class="muted">No models match “${query}”.</p>`;
    return;
  }

  for (const model of visibleModels) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = `catalog-item${model.modelId === state.selectedModelId ? " active" : ""}`;
    button.innerHTML = `
      <strong>${model.displayName}</strong>
      <div class="muted">${model.modelId}</div>
      <p>${model.description}</p>
    `;
    button.addEventListener("click", () => {
      state.selectedModelId = model.modelId;
      selectionStatusEl.textContent = `${model.displayName} selected`;
      renderCatalog();
    });
    catalogEl.appendChild(button);
  }
}

async function loadCatalog() {
  try {
    const response = await fetch(`${apiBasePath}/models`);
    if (!response.ok) {
      throw new Error(`Catalog request failed with ${response.status}`);
    }
    state.models = await response.json();
    if (!state.models.find((model) => model.modelId === state.selectedModelId)) {
      state.selectedModelId = state.models[0]?.modelId ?? null;
    }
    selectionStatusEl.textContent = "Model catalog loaded";
    selectionStatusEl.className = "status success";
  } catch (error) {
    selectionStatusEl.textContent = `Using generated catalog fallback: ${error.message}`;
    selectionStatusEl.className = "status muted";
  }
  renderCatalog();
}

async function submitInference(event) {
  event.preventDefault();
  requestStatusEl.textContent = "Submitting request…";
  requestStatusEl.className = "status muted";
  objectLinkContainerEl.textContent = "";
  try {
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
    requestStatusEl.textContent = `Completed request ${payload.requestId}`;
    requestStatusEl.className = "status success";
    const output = payload.payload.inlineOutput ?? `Stored object reference: ${payload.payload.objectRef}`;
    resultOutputEl.textContent = output;
    if (payload.payload.objectRef) {
      const link = document.createElement("a");
      link.href = `/objects/${payload.payload.objectRef}`;
      link.textContent = "Open large output";
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

await loadCatalog();
