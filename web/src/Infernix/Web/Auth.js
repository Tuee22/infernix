const verifierKey = "infernix.pkce.verifier";
const stateKey = "infernix.pkce.state";
const nonceKey = "infernix.pkce.nonce";
const refreshMarginSeconds = 30;
const minimumRefreshDelayMs = 5000;

let refreshToken = null;
let refreshTimeoutId = null;

function absoluteUrl(value) {
  return new URL(value, window.location.origin).toString();
}

function randomBase64Url(byteCount) {
  const bytes = new Uint8Array(byteCount);
  window.crypto.getRandomValues(bytes);
  return bytesToBase64Url(bytes);
}

function bytesToBase64Url(bytes) {
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return window.btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

async function sha256Base64Url(value) {
  const encoded = new TextEncoder().encode(value);
  if (window.crypto?.subtle?.digest) {
    const digest = await window.crypto.subtle.digest("SHA-256", encoded);
    return bytesToBase64Url(new Uint8Array(digest));
  }
  return bytesToBase64Url(sha256BytesFallback(encoded));
}

function rotateRight(value, bits) {
  return (value >>> bits) | (value << (32 - bits));
}

function sha256BytesFallback(input) {
  const h = [
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
  ];
  const k = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
    0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
    0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
    0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ];
  const bitLength = input.length * 8;
  const paddedLength = Math.ceil((input.length + 1 + 8) / 64) * 64;
  const padded = new Uint8Array(paddedLength);
  padded.set(input);
  padded[input.length] = 0x80;
  const highLength = Math.floor(bitLength / 0x100000000);
  const lowLength = bitLength >>> 0;
  padded[paddedLength - 8] = (highLength >>> 24) & 0xff;
  padded[paddedLength - 7] = (highLength >>> 16) & 0xff;
  padded[paddedLength - 6] = (highLength >>> 8) & 0xff;
  padded[paddedLength - 5] = highLength & 0xff;
  padded[paddedLength - 4] = (lowLength >>> 24) & 0xff;
  padded[paddedLength - 3] = (lowLength >>> 16) & 0xff;
  padded[paddedLength - 2] = (lowLength >>> 8) & 0xff;
  padded[paddedLength - 1] = lowLength & 0xff;

  const w = new Uint32Array(64);
  for (let offset = 0; offset < padded.length; offset += 64) {
    for (let i = 0; i < 16; i += 1) {
      const base = offset + i * 4;
      w[i] =
        ((padded[base] << 24) |
          (padded[base + 1] << 16) |
          (padded[base + 2] << 8) |
          padded[base + 3]) >>> 0;
    }
    for (let i = 16; i < 64; i += 1) {
      const s0 = rotateRight(w[i - 15], 7) ^ rotateRight(w[i - 15], 18) ^ (w[i - 15] >>> 3);
      const s1 = rotateRight(w[i - 2], 17) ^ rotateRight(w[i - 2], 19) ^ (w[i - 2] >>> 10);
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) >>> 0;
    }

    let a = h[0];
    let b = h[1];
    let c = h[2];
    let d = h[3];
    let e = h[4];
    let f = h[5];
    let g = h[6];
    let hh = h[7];

    for (let i = 0; i < 64; i += 1) {
      const s1 = rotateRight(e, 6) ^ rotateRight(e, 11) ^ rotateRight(e, 25);
      const ch = (e & f) ^ (~e & g);
      const temp1 = (hh + s1 + ch + k[i] + w[i]) >>> 0;
      const s0 = rotateRight(a, 2) ^ rotateRight(a, 13) ^ rotateRight(a, 22);
      const maj = (a & b) ^ (a & c) ^ (b & c);
      const temp2 = (s0 + maj) >>> 0;

      hh = g;
      g = f;
      f = e;
      e = (d + temp1) >>> 0;
      d = c;
      c = b;
      b = a;
      a = (temp1 + temp2) >>> 0;
    }

    h[0] = (h[0] + a) >>> 0;
    h[1] = (h[1] + b) >>> 0;
    h[2] = (h[2] + c) >>> 0;
    h[3] = (h[3] + d) >>> 0;
    h[4] = (h[4] + e) >>> 0;
    h[5] = (h[5] + f) >>> 0;
    h[6] = (h[6] + g) >>> 0;
    h[7] = (h[7] + hh) >>> 0;
  }

  const output = new Uint8Array(32);
  for (let i = 0; i < h.length; i += 1) {
    output[i * 4] = (h[i] >>> 24) & 0xff;
    output[i * 4 + 1] = (h[i] >>> 16) & 0xff;
    output[i * 4 + 2] = (h[i] >>> 8) & 0xff;
    output[i * 4 + 3] = h[i] & 0xff;
  }
  return output;
}

function clearPkce() {
  window.sessionStorage.removeItem(verifierKey);
  window.sessionStorage.removeItem(stateKey);
  window.sessionStorage.removeItem(nonceKey);
}

function clearRefreshTimer() {
  if (refreshTimeoutId !== null) {
    window.clearTimeout(refreshTimeoutId);
    refreshTimeoutId = null;
  }
}

function refreshDelayMs(expiresIn) {
  const seconds = Number(expiresIn);
  if (!Number.isFinite(seconds) || seconds <= refreshMarginSeconds) {
    return minimumRefreshDelayMs;
  }
  return Math.max(minimumRefreshDelayMs, (seconds - refreshMarginSeconds) * 1000);
}

function handleTokenPayload(config, onToken, payload) {
  if (!payload.access_token) {
    throw new Error("token response did not include access_token");
  }
  if (payload.refresh_token) {
    refreshToken = payload.refresh_token;
  }
  window.__infernixAccessToken = payload.access_token;
  window.__infernixRefreshAccessToken = () => refreshAccessToken(config, onToken);
  scheduleRefresh(config, onToken, payload.expires_in);
  onToken(payload.access_token)();
  return payload.access_token;
}

function scheduleRefresh(config, onToken, expiresIn) {
  clearRefreshTimer();
  if (!refreshToken) {
    return;
  }
  refreshTimeoutId = window.setTimeout(() => {
    refreshAccessToken(config, onToken).catch((error) => {
      console.error("Unable to refresh Keycloak access token", error);
    });
  }, refreshDelayMs(expiresIn));
}

async function refreshAccessToken(config, onToken) {
  if (!refreshToken) {
    throw new Error("No Keycloak refresh token is available");
  }

  const form = new URLSearchParams();
  form.set("grant_type", "refresh_token");
  form.set("client_id", config.clientId);
  form.set("refresh_token", refreshToken);

  const response = await fetch(`${absoluteUrl(config.issuerUrl)}/protocol/openid-connect/token`, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: form,
  });
  if (!response.ok) {
    throw new Error(`token refresh failed with HTTP ${response.status}: ${await response.text()}`);
  }
  return handleTokenPayload(config, onToken, await response.json());
}

export const beginLoginRedirectImpl = (config) => () => {
  (async () => {
    const verifier = randomBase64Url(48);
    const state = `state-${randomBase64Url(18)}`;
    const nonce = `nonce-${randomBase64Url(18)}`;
    const challenge = await sha256Base64Url(verifier);
    window.sessionStorage.setItem(verifierKey, verifier);
    window.sessionStorage.setItem(stateKey, state);
    window.sessionStorage.setItem(nonceKey, nonce);

    const authUrl = new URL(`${absoluteUrl(config.issuerUrl)}/protocol/openid-connect/auth`);
    authUrl.searchParams.set("client_id", config.clientId);
    authUrl.searchParams.set("redirect_uri", absoluteUrl(config.redirectUri));
    authUrl.searchParams.set("response_type", "code");
    authUrl.searchParams.set("scope", "openid");
    authUrl.searchParams.set("state", state);
    authUrl.searchParams.set("nonce", nonce);
    authUrl.searchParams.set("code_challenge", challenge);
    authUrl.searchParams.set("code_challenge_method", "S256");
    window.location.assign(authUrl.toString());
  })().catch((error) => {
    console.error("Unable to begin Keycloak login", error);
  });
};

export const completeRedirectImpl = (config) => (onToken) => () => {
  const currentUrl = new URL(window.location.href);
  const code = currentUrl.searchParams.get("code");
  if (!code) {
    return;
  }

  const expectedState = window.sessionStorage.getItem(stateKey);
  const actualState = currentUrl.searchParams.get("state");
  const verifier = window.sessionStorage.getItem(verifierKey);
  if (!expectedState || !verifier || actualState !== expectedState) {
    console.error("Keycloak redirect state did not match the in-memory PKCE state");
    clearPkce();
    return;
  }

  const form = new URLSearchParams();
  form.set("grant_type", "authorization_code");
  form.set("client_id", config.clientId);
  form.set("redirect_uri", absoluteUrl(config.redirectUri));
  form.set("code", code);
  form.set("code_verifier", verifier);

  fetch(`${absoluteUrl(config.issuerUrl)}/protocol/openid-connect/token`, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: form,
  })
    .then(async (response) => {
      if (!response.ok) {
        throw new Error(`token exchange failed with HTTP ${response.status}: ${await response.text()}`);
      }
      return response.json();
    })
    .then((payload) => {
      clearPkce();
      window.history.replaceState(null, "", absoluteUrl(config.redirectUri));
      handleTokenPayload(config, onToken, payload);
    })
    .catch((error) => {
      clearPkce();
      console.error("Unable to complete Keycloak login", error);
    });
};

export const clearBrowserAuthSession = () => {
  clearRefreshTimer();
  clearPkce();
  refreshToken = null;
  window.__infernixAccessToken = undefined;
  window.__infernixRefreshAccessToken = undefined;
};
