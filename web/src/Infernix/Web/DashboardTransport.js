function requireAccessToken() {
  const token = window.__infernixAccessToken || "";
  if (!token) {
    throw new Error("Sign in to view cluster monitoring");
  }
  return token;
}

export const refreshAdminOverviewImpl = (onLoaded) => (onError) => () => {
  (async () => {
    const token = requireAccessToken();
    const response = await fetch("/api/admin/overview", {
      headers: { Authorization: `Bearer ${token}` },
    });
    if (!response.ok) {
      throw new Error(`admin overview failed with HTTP ${response.status}: ${await response.text()}`);
    }
    onLoaded(await response.text())();
  })().catch((error) => onError(error.message)());
};
