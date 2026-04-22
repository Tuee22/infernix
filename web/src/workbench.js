import { filterModels } from "./catalog.js";

export function selectedModel(models, selectedModelId) {
  return models.find((model) => model.modelId === selectedModelId) ?? null;
}

export function catalogCards(models, query, selectedModelId) {
  return filterModels(models, query).map((model) => ({
    modelId: model.modelId,
    displayName: model.displayName,
    description: model.description,
    family: model.family,
    artifactType: model.artifactType,
    selectedEngine: model.selectedEngine,
    isActive: model.modelId === selectedModelId,
  }));
}

export function selectionSummary(model) {
  if (!model) {
    return {
      name: "No model selected",
      engine: "No engine",
      lane: "No runtime lane",
      familyLabel: "No workload family",
      artifactType: "No artifact type",
      notes: "No notes",
      inputLabel: "Input Text",
      placeholder: "Type a request payload",
      requestGuidance: "Select a model to load family-specific request guidance.",
      submitLabel: "Run Inference",
      resultLabel: "Result payload",
    };
  }

  const familyView = familyPresentation(model);
  return {
    name: model.displayName,
    engine: model.selectedEngine,
    lane: model.runtimeLane,
    familyLabel: familyView.familyLabel,
    artifactType: model.artifactType,
    notes: model.notes,
    inputLabel: model.requestShape[0]?.label ?? "Input Text",
    placeholder: familyView.placeholder,
    requestGuidance: familyView.requestGuidance,
    submitLabel: familyView.submitLabel,
    resultLabel: familyView.resultLabel,
  };
}

export function describeCompletedRequest(result, model) {
  const familyView = familyPresentation(model);
  const selectedEngine = result.selectedEngine ?? model?.selectedEngine ?? "the active engine";
  const objectRef = result.payload?.objectRef ?? null;
  const inlineOutput = result.payload?.inlineOutput ?? null;
  return {
    statusText: `Completed request ${result.requestId} on ${selectedEngine}`,
    resultLabel: familyView.resultLabel,
    outputText: inlineOutput ?? (objectRef ? `Stored object reference: ${objectRef}` : "No result yet."),
    objectHref: objectRef ? `/objects/${objectRef}` : null,
    objectLinkLabel: objectRef ? familyView.objectLinkLabel : null,
  };
}

export function publicationSummary(publication, fallbackRuntimeMode) {
  const routes = Array.isArray(publication?.routes) ? publication.routes : [];
  const upstreams = Array.isArray(publication?.upstreams) ? publication.upstreams : [];
  return {
    runtimeMode: publication?.runtimeMode ?? fallbackRuntimeMode ?? "unknown",
    controlPlaneContext: publication?.controlPlaneContext ?? "Unavailable",
    daemonLocation: publication?.daemonLocation ?? "Unavailable",
    catalogSource: publication?.catalogSource ?? "Unavailable",
    edgePort: publication?.edgePort == null ? "Not published" : String(publication.edgePort),
    apiUpstreamMode: publication?.apiUpstream?.mode ?? "Unavailable",
    demoConfigPath:
      publication?.demoConfigPath ??
      publication?.generatedDemoConfigPath ??
      publication?.mountedDemoConfigPath ??
      "Unavailable",
    routes,
    upstreams,
  };
}

function familyPresentation(model) {
  switch (model?.family) {
    case "llm":
      return {
        familyLabel: "Text generation",
        placeholder: "Ask for an answer, rewrite, or summary.",
        requestGuidance: "This lane accepts free-form prompts and returns generated text.",
        submitLabel: "Generate Text",
        resultLabel: "Generated text",
        objectLinkLabel: "Open large text output",
      };
    case "speech":
      return {
        familyLabel: "Speech transcription",
        placeholder: "Describe the transcript or spoken phrase to process.",
        requestGuidance: "Speech rows present the request as a transcription job and return transcript-oriented output.",
        submitLabel: "Transcribe Speech",
        resultLabel: "Transcript",
        objectLinkLabel: "Open large transcript output",
      };
    case "audio":
      return {
        familyLabel: "Audio workflow",
        placeholder: "Describe the audio transformation or generation request.",
        requestGuidance: "Audio rows render workflow guidance rather than generic text-generation copy.",
        submitLabel: "Run Audio Flow",
        resultLabel: "Audio workflow output",
        objectLinkLabel: "Open large audio workflow output",
      };
    case "music":
      return {
        familyLabel: "Music workflow",
        placeholder: "Describe the composition, style, or music task to run.",
        requestGuidance: "Music rows frame the request as a composition or music workflow.",
        submitLabel: "Run Music Flow",
        resultLabel: "Music workflow output",
        objectLinkLabel: "Open large music workflow output",
      };
    case "image":
      return {
        familyLabel: "Image prompt",
        placeholder: "Describe the image concept, scene, or edit request.",
        requestGuidance: "Image rows keep the same API but present prompt language that matches visual generation tasks.",
        submitLabel: "Render Image Prompt",
        resultLabel: "Image workflow output",
        objectLinkLabel: "Open large image output",
      };
    case "video":
      return {
        familyLabel: "Video prompt",
        placeholder: "Describe the scene, motion, or shot sequence to generate.",
        requestGuidance: "Video rows treat the request as a shot or sequence prompt and label results accordingly.",
        submitLabel: "Render Video Prompt",
        resultLabel: "Video workflow output",
        objectLinkLabel: "Open large video output",
      };
    default:
      return {
        familyLabel: "Tool workflow",
        placeholder: "Describe the tool or structured workflow request.",
        requestGuidance: "Tool rows keep one request field while presenting tool-oriented workflow copy.",
        submitLabel: "Run Tool Flow",
        resultLabel: "Tool workflow output",
        objectLinkLabel: "Open large tool output",
      };
  }
}
