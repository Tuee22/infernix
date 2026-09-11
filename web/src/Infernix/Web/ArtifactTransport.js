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

// Phase 7 Sprint 7.33: the preview budget, and it is the backend's number.
//
// A bound that the two sides pick separately is not a bound — whichever is
// larger is the real limit. This mirrors
// Infernix.Web.Contracts.boundedTextPreviewBytes, and the backend refuses to
// send more than it regardless, so the browser cap is the second of two.
const BOUNDED_TEXT_PREVIEW_BYTES = 64 * 1024;

async function authedBytes(url, token) {
  const response = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
  if (!response.ok) {
    throw new Error(`object download failed with HTTP ${response.status}: ${await response.text()}`);
  }
  return response.arrayBuffer();
}

// Phase 7 Sprint 7.33: read at most the preview budget, stopping the stream
// rather than buffering the object and slicing it afterwards.
//
// Decoding is incremental and stops at the same bound, so a multi-gigabyte text
// artifact costs a bounded read and a bounded decode instead of a tab. The
// decoder is given the chunks in order with `stream: true`, which is what keeps
// a multi-byte character split across a chunk boundary from decoding as
// replacement characters.
async function authedText(url, token) {
  const response = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
  if (!response.ok) {
    throw new Error(`object download failed with HTTP ${response.status}: ${await response.text()}`);
  }
  return response.text();
}

async function authedBoundedText(url, token, byteBudget) {
  const response = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
  if (!response.ok) {
    throw new Error(`object download failed with HTTP ${response.status}: ${await response.text()}`);
  }
  const declaredTruncation = response.headers.get("X-Infernix-Preview-Truncated") === "true";
  if (!response.body) {
    // No streaming body available: fall back to a bounded slice of the text the
    // backend already bounded.
    const whole = await response.text();
    return { text: whole.slice(0, byteBudget), truncated: declaredTruncation };
  }
  const reader = response.body.getReader();
  const decoder = new TextDecoder("utf-8");
  let consumed = 0;
  let text = "";
  let truncated = declaredTruncation;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) {
      break;
    }
    const remaining = byteBudget - consumed;
    if (remaining <= 0) {
      truncated = true;
      await reader.cancel();
      break;
    }
    const chunk = value.length > remaining ? value.subarray(0, remaining) : value;
    if (chunk.length < value.length) {
      truncated = true;
    }
    consumed += chunk.length;
    text += decoder.decode(chunk, { stream: true });
    if (consumed >= byteBudget) {
      await reader.cancel();
      break;
    }
  }
  text += decoder.decode();
  return { text, truncated };
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
    // Phase 7 Sprint 7.33: playback is synthesized from the decoded MIDI.
    //
    // The retired form loaded a sampled piano from "/samples/smplr", which the
    // served bundle never carried, and swallowed the resulting failure — so the
    // Play button existed, did nothing, and reported nothing, and a test that
    // asserted the button was present passed against silence. Scheduling
    // oscillators from the notes this renderer already decoded removes the
    // missing asset rather than shipping tens of megabytes of samples to
    // restore it, and makes the observable signal the note events themselves.
    //
    // Browser autoplay policy means a context may start suspended; the click
    // that triggers this is the user gesture that resumes it, and a context
    // that will not resume is reported rather than hidden.
    const play = document.createElement("button");
    play.type = "button";
    play.className = "artifact-midi-play";
    play.textContent = "Play";
    play.dataset.playbackStatus = "idle";
    play.addEventListener("click", () => {
      (async () => {
        play.dataset.playbackStatus = "starting";
        const audioContext = new AudioContext();
        if (audioContext.state === "suspended") {
          await audioContext.resume();
        }
        if (audioContext.state !== "running") {
          throw new Error(`audio context did not start: ${audioContext.state}`);
        }
        let scheduled = 0;
        for (const note of notes) {
          const oscillator = audioContext.createOscillator();
          const gain = audioContext.createGain();
          oscillator.type = "triangle";
          oscillator.frequency.value = 440 * Math.pow(2, (note.midi - 69) / 12);
          gain.gain.value = Math.min(Math.max(note.velocity, 0), 1) * 0.2;
          oscillator.connect(gain);
          gain.connect(audioContext.destination);
          const startAt = audioContext.currentTime + note.time;
          oscillator.start(startAt);
          oscillator.stop(startAt + Math.max(note.duration, 0.05));
          scheduled += 1;
        }
        play.dataset.playbackScheduledNotes = String(scheduled);
        play.dataset.playbackStatus = scheduled > 0 ? "playing" : "empty";
      })().catch((error) => {
        play.dataset.playbackStatus = "error";
        play.dataset.playbackError = String(error && error.message ? error.message : error);
      });
    });
    mount.appendChild(canvas);
    mount.appendChild(play);
    mount.dataset.previewRenderedNotes = String(notes.length);
    mount.dataset.previewStatus = notes.length > 0 ? "ready" : "empty";
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

// Phase 7 Sprint 7.33: the preview intent is named in the request rather than
// inferred, so the full-download intent is the same route without it and a
// truncated preview always has an unbounded counterpart to offer.
function objectPreviewUrl(objectKey, mimeType) {
  return objectBytesUrl(objectKey, mimeType) + "&intent=preview";
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
    const { text, truncated } = await authedBoundedText(
      objectPreviewUrl(objectKey, mimeType),
      token,
      BOUNDED_TEXT_PREVIEW_BYTES,
    );
    const cards = currentArtifactCards(card, objectKey);
    for (const currentCard of cards) {
      const preview = currentCard.querySelector(".artifact-preview-text");
      if (preview) {
        preview.textContent = text;
        // Truncation is stated rather than left for the reader to notice. The
        // full object is still one click away on the same authorized route.
        preview.dataset.previewTruncated = truncated ? "true" : "false";
        preview.dataset.previewByteBudget = String(BOUNDED_TEXT_PREVIEW_BYTES);
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
