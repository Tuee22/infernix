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

// Phase 7 Sprint 7.27: in-browser MIDI / MusicXML / ZIP rendering. The
// renderer libraries are loaded with dynamic import() so they are only
// resolved at bundle time (esbuild code-splits each into its own chunk) and
// never at module-load time, keeping the unit suite free of the runtime deps.
// Self-hosted assets (smplr samples) are served from the app origin.
const SMPLR_SAMPLE_BASE = "/samples/smplr";

async function authedBytes(url, token) {
  const response = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
  if (!response.ok) {
    throw new Error(`object download failed with HTTP ${response.status}: ${await response.text()}`);
  }
  return response.arrayBuffer();
}

async function authedText(url, token) {
  const response = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
  if (!response.ok) {
    throw new Error(`object download failed with HTTP ${response.status}: ${await response.text()}`);
  }
  return response.text();
}

function renderGuard(mount) {
  if (mount.__infernixRendered) {
    return false;
  }
  mount.__infernixRendered = true;
  return true;
}

// The in-browser renderers are best-effort: a failure to parse/render a given
// artifact (or to load the dynamically-imported library) must not fail the
// download itself, so each catches internally and marks the mount node rather
// than throwing to the download handler.
function markRenderFailed(mount, message) {
  mount.textContent = message;
  mount.dataset.previewStatus = "error";
}

async function renderMidiInto(mount, token, bytesUrl) {
  if (!renderGuard(mount)) {
    return;
  }
  try {
    mount.textContent = "";
    const buffer = await authedBytes(bytesUrl, token);
    const { Midi } = await import("@tonejs/midi");
    const midi = new Midi(buffer);
    // Piano-roll: one row per note across the timeline.
    const canvas = document.createElement("canvas");
    canvas.className = "artifact-midi-pianoroll";
    canvas.width = 640;
    canvas.height = 200;
    const context = canvas.getContext("2d");
    const notes = midi.tracks.flatMap((track) => track.notes);
    const duration = Math.max(midi.duration, 0.001);
    context.fillStyle = "#1f6feb";
    for (const note of notes) {
      const x = (note.time / duration) * canvas.width;
      const w = Math.max((note.duration / duration) * canvas.width, 1);
      const y = canvas.height - ((note.midi - 21) / 88) * canvas.height;
      context.fillRect(x, y, w, 3);
    }
    const play = document.createElement("button");
    play.type = "button";
    play.className = "artifact-midi-play";
    play.textContent = "Play";
    play.addEventListener("click", () => {
      (async () => {
        const smplr = await import("smplr");
        const audioContext = new AudioContext();
        const piano = new smplr.SplendidGrandPiano(audioContext, { baseUrl: SMPLR_SAMPLE_BASE });
        await piano.loaded();
        for (const note of notes) {
          piano.start({ note: note.midi, time: audioContext.currentTime + note.time, duration: note.duration, velocity: Math.round(note.velocity * 127) });
        }
      })().catch(() => {});
    });
    mount.appendChild(canvas);
    mount.appendChild(play);
    mount.dataset.previewStatus = "ready";
  } catch (error) {
    markRenderFailed(mount, "Unable to render MIDI in the browser.");
  }
}

async function renderMusicXmlInto(mount, token, bytesUrl) {
  if (!renderGuard(mount)) {
    return;
  }
  try {
    mount.textContent = "";
    const text = await authedText(bytesUrl, token);
    const osmdModule = await import("opensheetmusicdisplay");
    const osmd = new osmdModule.OpenSheetMusicDisplay(mount, { autoResize: true, backend: "svg" });
    await osmd.load(text);
    osmd.render();
    mount.dataset.previewStatus = "ready";
  } catch (error) {
    markRenderFailed(mount, "Unable to render notation in the browser.");
  }
}

async function renderZipStemsInto(mount, token, bytesUrl) {
  if (!renderGuard(mount)) {
    return;
  }
  try {
    mount.textContent = "";
    const buffer = await authedBytes(bytesUrl, token);
    const fflate = await import("fflate");
    const files = fflate.unzipSync(new Uint8Array(buffer));
    let stemCount = 0;
    for (const name of Object.keys(files)) {
      if (!/\.(wav|mp3|ogg|flac)$/i.test(name)) {
        continue;
      }
      stemCount += 1;
      const label = document.createElement("p");
      label.className = "artifact-zip-stem-name";
      label.textContent = name;
      const audio = document.createElement("audio");
      audio.className = "artifact-zip-stem-audio";
      audio.controls = true;
      const blob = new Blob([files[name]], { type: "audio/" + name.split(".").pop().toLowerCase() });
      audio.src = URL.createObjectURL(blob);
      mount.appendChild(label);
      mount.appendChild(audio);
    }
    if (stemCount === 0) {
      mount.textContent = "No audio stems in archive.";
    }
    mount.dataset.previewStatus = "ready";
  } catch (error) {
    markRenderFailed(mount, "Unable to render archive in the browser.");
  }
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

// Phase 7 Sprint 7.25: the webapp is the sole object mediator. The browser
// uploads bytes to the webapp and downloads bytes from the webapp; it never
// holds a MinIO credential or a presigned MinIO URL.
function objectBytesUrl(objectKey, mimeType) {
  return (
    "/api/objects/download?key=" +
    encodeURIComponent(objectKey) +
    "&mimeType=" +
    encodeURIComponent(mimeType)
  );
}

function currentArtifactCards(card, objectKey) {
  const documentValue = card?.ownerDocument || document;
  const cards = Array.from(documentValue.querySelectorAll(".artifact-entry")).filter(
    (entry) => entry.dataset.objectKey === objectKey,
  );
  if (cards.length > 0) {
    return cards;
  }
  return card ? [card] : [];
}

function markDownloadReady(cards, bytesUrl, disposition) {
  for (const card of cards) {
    card.dataset.renderDisposition = disposition || "";
    for (const download of card.querySelectorAll("[data-role='artifact-download']")) {
      download.dataset.downloadStatus = "ready";
      download.dataset.downloadUrl = bytesUrl;
    }
  }
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

  setUploadStatus(form, "pending", "Uploading");
  setUploadProgress(form, 30);
  // One leg: stream the bytes to the webapp object-proxy. The object key is
  // derived server-side from the verified token subject plus the sanitized
  // display name (sent as a query parameter); the body is the raw file bytes.
  const uploadUrl =
    "/api/objects/upload?contextId=" +
    encodeURIComponent(contextId) +
    "&displayName=" +
    encodeURIComponent(displayName);
  const response = await fetch(uploadUrl, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": mimeType,
    },
    body: file,
  });
  if (!response.ok) {
    throw new Error(`object upload failed with HTTP ${response.status}: ${await response.text()}`);
  }
  const grant = await response.json();

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
  const objectKey = button.dataset.objectKey || "";
  const displayName = button.dataset.displayName || displayNameFromKey(objectKey);
  const card = button.closest(".artifact-entry");
  if (!contextId || !displayName || !objectKey) {
    throw new Error("Artifact download metadata is incomplete");
  }

  button.dataset.downloadStatus = "pending";
  // The grant carries the authoritative render disposition for this MIME type.
  const grant = await postJson("/api/objects/download", token, {
    artifactUploadRequestContextId: contextId,
    artifactUploadRequestMimeType: mimeType,
    artifactUploadRequestDisplayName: displayName,
  });
  const disposition = renderDispositionTag(grant.artifactDownloadGrantRenderDisposition);
  // The bytes are streamed from the webapp object-proxy keyed by the card's
  // own object key, so both `uploads/` and `generated/` artifacts resolve.
  const bytesUrl = objectBytesUrl(objectKey, mimeType);

  if (disposition === "BoundedTextPreview") {
    const text = await authedText(bytesUrl, token);
    const cards = currentArtifactCards(card, objectKey);
    for (const currentCard of cards) {
      const preview = currentCard.querySelector(".artifact-preview-text");
      if (preview) {
        preview.textContent = text;
        preview.dataset.previewStatus = "ready";
      }
    }
    markDownloadReady(cards, bytesUrl, disposition);
    return;
  }

  if (disposition === "RenderInline" || disposition === "BrowserNativePdf") {
    const cards = currentArtifactCards(card, objectKey);
    for (const currentCard of cards) {
      const media = currentCard.querySelector(
        ".artifact-preview-image, .artifact-preview-audio, .artifact-preview-video, .artifact-preview-pdf",
      );
      if (media) {
        // Browser-issued media src GET authenticates via the operator cookie
        // (Path=/; set at login) since img/audio/video/iframe cannot set headers.
        media.setAttribute("src", bytesUrl);
        media.dataset.previewStatus = "ready";
      }
    }
    markDownloadReady(cards, bytesUrl, disposition);
    return;
  }

  if (disposition === "RenderMidi") {
    const cards = currentArtifactCards(card, objectKey);
    for (const currentCard of cards) {
      const mount = currentCard.querySelector(".artifact-preview-midi");
      if (mount) {
        await renderMidiInto(mount, token, bytesUrl);
      }
    }
    markDownloadReady(cards, bytesUrl, disposition);
    return;
  }

  if (disposition === "RenderMusicXml") {
    const cards = currentArtifactCards(card, objectKey);
    for (const currentCard of cards) {
      const mount = currentCard.querySelector(".artifact-preview-musicxml");
      if (mount) {
        await renderMusicXmlInto(mount, token, bytesUrl);
      }
    }
    markDownloadReady(cards, bytesUrl, disposition);
    return;
  }

  if (disposition === "RenderZipStems") {
    const cards = currentArtifactCards(card, objectKey);
    for (const currentCard of cards) {
      const mount = currentCard.querySelector(".artifact-preview-zip");
      if (mount) {
        await renderZipStemsInto(mount, token, bytesUrl);
      }
    }
    markDownloadReady(cards, bytesUrl, disposition);
    return;
  }

  const cards = currentArtifactCards(card, objectKey);
  for (const currentCard of cards) {
    const placeholder = currentCard.querySelector(".artifact-preview-download-only");
    if (placeholder) {
      placeholder.textContent = "Download ready.";
      placeholder.dataset.previewStatus = "ready";
    }
  }
  markDownloadReady(cards, bytesUrl, disposition);
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
