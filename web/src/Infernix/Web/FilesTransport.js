function accessToken() {
  return window.__infernixAccessToken || "";
}

function requireToken() {
  const token = accessToken();
  if (!token) {
    throw new Error("Sign in to view files");
  }
  return token;
}

export const refreshFilesListImpl = (onLoaded) => (onError) => () => {
  (async () => {
    const token = requireToken();
    const response = await fetch("/api/objects/list", {
      headers: { Authorization: `Bearer ${token}` },
    });
    if (!response.ok) {
      throw new Error(`file listing failed with HTTP ${response.status}: ${await response.text()}`);
    }
    const body = await response.text();
    onLoaded(body)();
  })().catch((error) => onError(error.message)());
};

export const bindFilesActionsImpl = (root) => (onDeleted) => (onError) => () => {
  if (root.__infernixFilesActionsBound) {
    return;
  }
  root.__infernixFilesActionsBound = true;

  root.addEventListener("click", (event) => {
    const button = event.target?.closest?.("[data-role='file-delete']");
    if (!button) {
      return;
    }
    event.preventDefault();
    const objectKey = button.dataset.objectKey || "";
    (async () => {
      const token = requireToken();
      button.dataset.deleteStatus = "pending";
      const response = await fetch(`/api/objects?key=${encodeURIComponent(objectKey)}`, {
        method: "DELETE",
        headers: { Authorization: `Bearer ${token}` },
      });
      if (!response.ok && response.status !== 404) {
        throw new Error(`file delete failed with HTTP ${response.status}: ${await response.text()}`);
      }
      button.dataset.deleteStatus = "ready";
      onDeleted(objectKey)();
    })().catch((error) => {
      button.dataset.deleteStatus = "error";
      onError(error.message)();
    });
  });
};
