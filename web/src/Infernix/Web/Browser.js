export const currentOrigin = () => window.location.origin;

const activeContextKey = "infernix.activeContext";

export const readStoredActiveContext = () => {
  const raw = window.sessionStorage.getItem(activeContextKey);
  if (!raw) {
    return "";
  }
  try {
    const parsed = JSON.parse(raw);
    if (typeof parsed?.contextId === "string" && typeof parsed?.modelId === "string") {
      return raw;
    }
  } catch {
    // Ignore stale or malformed session state.
  }
  window.sessionStorage.removeItem(activeContextKey);
  return "";
};

export const writeStoredActiveContext = (contextId) => (modelId) => () => {
  window.sessionStorage.setItem(activeContextKey, JSON.stringify({ contextId, modelId }));
};

export const clearStoredActiveContext = () => {
  window.sessionStorage.removeItem(activeContextKey);
};

export const installForceWebSocketClose = (action) => () => {
  window.__infernixForceWebSocketClose = () => action();
};

export const newUuid = () => {
  if (window.crypto && typeof window.crypto.randomUUID === "function") {
    return window.crypto.randomUUID();
  }
  const bytes = new Uint8Array(16);
  window.crypto.getRandomValues(bytes);
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0"));
  return `${hex.slice(0, 4).join("")}-${hex.slice(4, 6).join("")}-${hex
    .slice(6, 8)
    .join("")}-${hex.slice(8, 10).join("")}-${hex.slice(10).join("")}`;
};

export const scheduleEffect = (delayMs) => (action) => () => {
  window.setTimeout(() => action(), delayMs);
};
