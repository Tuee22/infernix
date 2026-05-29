function accessToken() {
  return window.__infernixAccessToken || "";
}

function requireToken() {
  const token = accessToken();
  if (!token) {
    throw new Error("Sign in before uploading or downloading artifacts");
  }
  return token;
}

function renderDispositionTag(disposition) {
  return typeof disposition === "string" ? disposition : disposition?.tag;
}

function displayNameFromKey(objectKey) {
  const parts = objectKey.split("/");
  return parts[parts.length - 1] || objectKey;
}

function setUploadProgress(form, value) {
  const progress = form.querySelector(".artifact-upload-progress");
  if (progress) {
    progress.value = value;
  }
}

function setUploadStatus(form, className, message) {
  const status = form.querySelector(".artifact-upload-status");
  if (status) {
    status.className = `artifact-upload-status ${className}`;
    status.textContent = message;
  }
}

async function postJson(url, token, body) {
  const response = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });
  if (!response.ok) {
    throw new Error(`${url} failed with HTTP ${response.status}: ${await response.text()}`);
  }
  return response.json();
}

async function handleUpload(form, onUploaded) {
  const token = requireToken();
  const contextId = form.dataset.contextId;
  if (!contextId) {
    throw new Error("Create or select a context before uploading");
  }
  const fileInput = form.querySelector("input[name='artifact-file']");
  const file = fileInput?.files?.[0];
  if (!file) {
    throw new Error("Choose a file before uploading");
  }
  const mimeInput = form.querySelector("input[name='artifact-mime']");
  const displayInput = form.querySelector("input[name='artifact-display-name']");
  const mimeType = (mimeInput?.value || file.type || "application/octet-stream").trim();
  const displayName = (displayInput?.value || file.name).trim();
  if (!displayName) {
    throw new Error("Artifact display name is required");
  }

  setUploadStatus(form, "pending", "Requesting upload grant");
  setUploadProgress(form, 15);
  const grant = await postJson("/api/objects/upload", token, {
    artifactUploadRequestContextId: contextId,
    artifactUploadRequestMimeType: mimeType,
    artifactUploadRequestDisplayName: displayName,
  });

  setUploadStatus(form, "pending", "Uploading");
  setUploadProgress(form, 45);
  const putResponse = await fetch(grant.artifactUploadGrantPresignedUrl, {
    method: "PUT",
    headers: {
      "Content-Type": mimeType,
    },
    body: file,
  });
  if (!putResponse.ok) {
    throw new Error(`presigned PUT failed with HTTP ${putResponse.status}: ${await putResponse.text()}`);
  }

  setUploadProgress(form, 100);
  setUploadStatus(form, "ready", "Uploaded");
  const objectRef = grant.artifactUploadGrantObjectRef;
  onUploaded(
    JSON.stringify({
      contextId,
      objectBucket: objectRef.objectBucket,
      objectKey: objectRef.objectKey,
      mimeType,
      displayName,
    }),
  )();
}

async function handleDownload(button) {
  const token = requireToken();
  const contextId = button.dataset.contextId;
  const mimeType = button.dataset.mimeType || "application/octet-stream";
  const displayName = button.dataset.displayName || displayNameFromKey(button.dataset.objectKey || "");
  const card = button.closest(".artifact-entry");
  if (!contextId || !displayName) {
    throw new Error("Artifact download metadata is incomplete");
  }

  button.dataset.downloadStatus = "pending";
  const grant = await postJson("/api/objects/download", token, {
    artifactUploadRequestContextId: contextId,
    artifactUploadRequestMimeType: mimeType,
    artifactUploadRequestDisplayName: displayName,
  });
  const disposition = renderDispositionTag(grant.artifactDownloadGrantRenderDisposition);
  button.dataset.downloadStatus = "ready";
  button.dataset.presignedUrl = grant.artifactDownloadGrantPresignedUrl;
  if (card) {
    card.dataset.renderDisposition = disposition || "";
  }

  if (disposition === "BoundedTextPreview") {
    const preview = card?.querySelector(".artifact-preview-text");
    if (preview) {
      const textResponse = await fetch(grant.artifactDownloadGrantPresignedUrl);
      if (!textResponse.ok) {
        throw new Error(`presigned GET failed with HTTP ${textResponse.status}: ${await textResponse.text()}`);
      }
      preview.textContent = await textResponse.text();
      preview.dataset.previewStatus = "ready";
    }
    return;
  }

  if (disposition === "RenderInline" || disposition === "BrowserNativePdf") {
    const media = card?.querySelector(
      ".artifact-preview-image, .artifact-preview-audio, .artifact-preview-video, .artifact-preview-pdf",
    );
    if (media) {
      media.setAttribute("src", grant.artifactDownloadGrantPresignedUrl);
      media.dataset.previewStatus = "ready";
    }
    return;
  }

  const placeholder = card?.querySelector(".artifact-preview-download-only");
  if (placeholder) {
    placeholder.textContent = "Download ready.";
    placeholder.dataset.previewStatus = "ready";
  }
}

export const bindArtifactTransportImpl = (root) => (onUploaded) => (onError) => () => {
  if (root.__infernixArtifactTransportBound) {
    return;
  }
  root.__infernixArtifactTransportBound = true;

  root.addEventListener("submit", (event) => {
    const form = event.target?.closest?.("form[data-role='artifact-upload']");
    if (!form) {
      return;
    }
    event.preventDefault();
    handleUpload(form, onUploaded).catch((error) => {
      setUploadProgress(form, 0);
      setUploadStatus(form, "error", error.message);
      onError(error.message)();
    });
  });

  root.addEventListener("click", (event) => {
    const button = event.target?.closest?.("[data-role='artifact-download']");
    if (!button) {
      return;
    }
    event.preventDefault();
    handleDownload(button).catch((error) => {
      button.dataset.downloadStatus = "error";
      onError(error.message)();
    });
  });
};
