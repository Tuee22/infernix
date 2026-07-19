// Phase 7 follow-on (May 26, 2026): the legacy stateless workbench
// surface that this spec used to exercise (`POST /api/inference`,
// the workbench SPA DOM, the `/objects/:objectRef` shape) is retired
// in favor of the durable-context Chat surface. This suite now covers
// the routed SPA, Keycloak auth, `/ws` WebSocket transport,
// `/api/objects` presigned MinIO flow, durable Chat behavior, artifact
// rendering, and per-model browser smoke matrix. The integration suite
// still covers the deeper per-model Pulsar roundtrip against the same
// cluster.
import { Buffer } from "node:buffer";
import { execFileSync } from "node:child_process";
import { createHash, randomUUID } from "node:crypto";
import { test as base, expect } from "playwright/test";
import {
  binaryArtifactBuffer,
  instrumentArpeggioWavBuffer,
  jsonPreviewBody,
  musicXmlBuffer,
  scoreImagePngBuffer,
  separationMixtureWavBuffer,
  speechWavBuffer,
  textPreviewBody,
  tinyMidiBuffer,
  tinyMp4Buffer,
  tinyPdfBuffer,
  tinyPngBuffer,
  tinyWavBuffer,
} from "../test/fixtures/artifactSamples.js";

const test = base.extend({
  infernixFixture: [undefined, { option: true }],
});

const serviceConsumerAckTimeoutMs = 900000;
// Sprint 5.12 (managed-state-transition doctrine): the model-bootstrap readiness
// deadline is single-sourced from the server ceiling; the client deadline is the
// ceiling plus a margin, so the client never waits less than the server can take.
// Mirrors Infernix.Web.Contracts.clientModelBootstrapDeadlineSeconds
// (modelBootstrapReadyServerCeilingSeconds + clientModelBootstrapDeadlineMarginSeconds).
const modelBootstrapReadyServerCeilingSeconds = 3600;
const clientModelBootstrapDeadlineMarginSeconds = 900;
const clientModelBootstrapDeadlineMs =
  (modelBootstrapReadyServerCeilingSeconds + clientModelBootstrapDeadlineMarginSeconds) * 1000;
const browserMatrixResultTimeoutMs = Math.max(
  serviceConsumerAckTimeoutMs + 900000,
  clientModelBootstrapDeadlineMs,
);
const browserMatrixTestTimeoutMs = 5400000;
const websocketReconnectTimeoutMs = 120000;
const accountCleanupRedirectTimeoutMs = 420000;
const accountDeletionTestTimeoutMs = 480000;

test("routed edge surfaces the SPA + the published platform state", async ({ page, request, infernixFixture }) => {
  const fixture = infernixFixture;
  expect(fixture?.host).toBeTruthy();
  expect(fixture?.edgePort).toBeTruthy();
  const baseUrl = `http://${fixture.host}:${fixture.edgePort}`;

  const publicationResponse = await request.get(`${baseUrl}/api/publication`);
  expect(publicationResponse.ok()).toBeTruthy();
  const publication = await publicationResponse.json();
  expect(publication.runtimeMode).toBeTruthy();

  const demoConfigResponse = await request.get(`${baseUrl}/api/demo-config`);
  expect(demoConfigResponse.ok()).toBeTruthy();
  const demoConfig = await demoConfigResponse.json();
  expect(Array.isArray(demoConfig.models)).toBe(true);

  const catalogResponse = await request.get(`${baseUrl}/api/models`);
  expect(catalogResponse.ok()).toBeTruthy();
  const routedModels = await catalogResponse.json();
  expect(routedModels).toEqual(demoConfig.models);

  await page.goto(baseUrl);
  await expect(page.locator(".app-landing h1, .app-header h1").first()).toHaveText("Infernix");
});

test("routed keycloak auth supports self-registration without email verification", async ({ page, infernixFixture }) => {
  test.setTimeout(90000);
  const fixture = infernixFixture;
  expect(fixture?.host).toBeTruthy();
  expect(fixture?.edgePort).toBeTruthy();
  const baseUrl = `http://${fixture.host}:${fixture.edgePort}`;
  const registration = await registerFreshKeycloakUser(page, baseUrl);

  expect(registration.state).toBeTruthy();
  expect(registration.code).toBeTruthy();
});

test("pre-auth landing exposes sign-in and create-account entry points", async ({ page, infernixFixture }) => {
  test.setTimeout(90000);
  const fixture = infernixFixture;
  expect(fixture?.host).toBeTruthy();
  expect(fixture?.edgePort).toBeTruthy();
  const baseUrl = `http://${fixture.host}:${fixture.edgePort}`;

  await page.goto(baseUrl);
  await expect(page.locator("body")).toHaveClass("auth-signed-out");
  await expect(page.locator(".app-landing")).toBeVisible();
  await expect(page.locator(".app-shell")).toBeHidden();
  await expect(page.locator(".operator-ribbon")).toBeHidden();
  await expect(page.locator(".app-landing h1")).toHaveText("Infernix");
  await expectReadableContrast(page, ".app-landing h1");
  await expectReadableContrast(page, ".app-landing-subtitle");
  await expectReadableContrast(page, "#login-button");
  await expectUnobscuredAtCenter(page, ".app-landing h1");
  await expect(page.locator(".app-landing-actions button")).toHaveCount(2);
  await expect(page.locator("#login-button")).toHaveText("Sign in");
  await expect(page.locator("#register-button")).toHaveText("Create account");

  await page.locator("#login-button").click();
  await expect(page.locator("#username, input[name='username']").first()).toBeVisible({ timeout: 60000 });
  await expect(page.getByText("Sign in to Infernix")).toBeVisible();
  await expectReadableContrast(page, "#kc-page-title");
  await expectReadableContrast(page, "#kc-registration a");
  await expectUnobscuredAtCenter(page, "#kc-header-wrapper");
  await expect(page.locator("#kc-registration a")).toBeVisible();
  await expect(page.locator("#kc-register-form, form[action*='registration']")).toHaveCount(0);

  await page.goto(baseUrl);
  await expect(page.locator("body")).toHaveClass("auth-signed-out");
  await page.locator("#register-button").click();
  await expect(page.locator("#kc-register-form, form[action*='registration'], form[action*='registrations']")).toBeVisible({ timeout: 60000 });
  await expect(page.getByText("Create your Infernix account")).toBeVisible();
  await expectReadableContrast(page, "#kc-page-title");
  await expectUnobscuredAtCenter(page, "#kc-header-wrapper");
  expect(page.url()).toContain("/auth/realms/infernix/");
});

test("browser auth lifecycle covers logout re-login and token refresh", async ({ page, infernixFixture }) => {
  test.setTimeout(120000);
  const fixture = infernixFixture;
  expect(fixture?.host).toBeTruthy();
  expect(fixture?.edgePort).toBeTruthy();
  const baseUrl = `http://${fixture.host}:${fixture.edgePort}`;
  const wsFrames = collectWebSocketFrames(page);

  await page.goto(baseUrl);
  await page.locator("#login-button").click();
  const credentials = await submitFreshRegistrationForm(page, baseUrl);
  await expect(page.locator("#connection-state")).toHaveText("Authenticated", { timeout: 60000 });
  // Phase 9 Sprint 9.8: this self-service user is non-admin, so the operator
  // ribbon (and the cluster-wide surfaces) stay hidden.
  await expectNoOperatorRibbon(page);
  await waitForSentFrame(wsFrames, (frame) => frame.tag === "ClientHello");
  await waitForReceivedFrame(wsFrames, (frame) => frame.tag === "ServerContextListSnapshot");
  const firstToken = await browserAccessToken(page);
  expect(firstToken).toBeTruthy();
  expect(await browserCookieValue(page, baseUrl, "infernix_operator_token")).toBe(firstToken);

  await page.locator("#logout-button").click();
  await expect(page.locator("#connection-state")).toHaveText("Signed out");
  expect(await browserAccessToken(page)).toBe("");
  expect(await browserCookieValue(page, baseUrl, "infernix_operator_token")).toBe("");

  const reloginStartIndex = wsFrames.sent.length;
  await page.locator("#login-button").click();
  await completeLoginPrompt(page, credentials);
  await expect(page.locator("#connection-state")).toHaveText("Authenticated", { timeout: 60000 });
  await waitForSentFrameAfter(wsFrames, reloginStartIndex, (frame) => frame.tag === "ClientHello");
  const reloginToken = await browserAccessToken(page);
  expect(reloginToken).toBeTruthy();
  expect(await browserCookieValue(page, baseUrl, "infernix_operator_token")).toBe(reloginToken);

  const refreshSentStartIndex = wsFrames.sent.length;
  const refreshReceivedStartIndex = wsFrames.received.length;
  const refreshedToken = await page.evaluate(async () => {
    if (typeof window.__infernixRefreshAccessToken !== "function") {
      throw new Error("refresh hook was not installed");
    }
    return window.__infernixRefreshAccessToken();
  });
  expect(refreshedToken).toBeTruthy();
  await expect.poll(() => browserAccessToken(page), { timeout: 60000 }).toBe(refreshedToken);
  await expect.poll(() => browserCookieValue(page, baseUrl, "infernix_operator_token"), { timeout: 60000 }).toBe(refreshedToken);
  await waitForSentFrameAfter(wsFrames, refreshSentStartIndex, (frame) => frame.tag === "ClientHello");
  await waitForReceivedFrameAfter(wsFrames, refreshReceivedStartIndex, (frame) => frame.tag === "ServerDraftMapSnapshot");
});

test("routed WebSocket validates JWTs and reports malformed frames", async ({ page, request, infernixFixture }) => {
  test.setTimeout(240000);
  const fixture = infernixFixture;
  expect(fixture?.host).toBeTruthy();
  expect(fixture?.edgePort).toBeTruthy();
  const baseUrl = `http://${fixture.host}:${fixture.edgePort}`;
  const registration = await registerFreshKeycloakUser(page, baseUrl);
  const tokenPayload = await exchangeRegistrationCodeForToken(request, baseUrl, registration);
  const accessToken = tokenPayload.access_token;
  expect(accessToken).toBeTruthy();

  // Phase 9 Sprint 9.8: the operator routes are admin-authorized at the edge.
  // A valid self-registered (non-admin) token authenticates but is authorized
  // away with 403 on every operator route; an unauthenticated request is 401.
  for (const operatorRoute of [
    `${baseUrl}/harbor`,
    `${baseUrl}/harbor/api`,
    `${baseUrl}/pulsar/admin/admin/v2/clusters`,
    `${baseUrl}/pulsar/ws`,
  ]) {
    await expectJwtGatedOperatorRoute(request, operatorRoute, accessToken);
  }
  // Phase 3 Sprint 3.13: the /minio/s3 external gateway route is removed, so it
  // no longer reaches MinIO (it falls through to the demo SPA route, non-2xx).
  const minioRouteResponse = await request.get(`${baseUrl}/minio/s3/models/demo.bin`);
  expect(minioRouteResponse.ok()).toBeFalsy();

  const validResult = await probeWebSocket(page, websocketUrl(baseUrl, accessToken));
  expect(validResult.opened).toBe(true);

  const decodeErrorResult = await probeWebSocketDecodeError(page, websocketUrl(baseUrl, accessToken));
  expect(decodeErrorResult.opened).toBe(true);
  expect(decodeErrorResult.message?.tag).toBe("ServerError");
  expect(decodeErrorResult.message?.serverErrorErrorCode).toBe("ws_frame_decode_failed");

  const missingModelId = `missing-model-${randomUUID()}`;
  const unknownModelResult = await probeWebSocketMessage(page, websocketUrl(baseUrl, accessToken), {
    tag: "ClientCreateContext",
    clientCreateContextId: `ctx-${randomUUID()}`,
    clientCreateContextModelId: missingModelId,
    clientCreateContextTitle: "Unknown model",
  });
  expect(unknownModelResult.opened).toBe(true);
  expect(unknownModelResult.message?.tag).toBe("ServerError");
  expect(unknownModelResult.message?.serverErrorErrorCode).toBe("unknown-model");
  expect(unknownModelResult.message?.serverErrorMessage).toContain(missingModelId);

  const invalidResult = await probeWebSocket(page, websocketUrl(baseUrl, "not-a-real-token"));
  expect(invalidResult.opened).toBe(false);

  const wrongRealmToken = await keycloakAdminAccessToken(request, baseUrl);
  const wrongRealmResult = await probeWebSocket(page, websocketUrl(baseUrl, wrongRealmToken));
  expect(wrongRealmResult.opened).toBe(false);

  const expiredAccessToken = await mintExpiredAccessTokenViaRealmLifespan(request, page, baseUrl);
  await expect
    .poll(
      async () => {
        const expiredResult = await probeWebSocket(page, websocketUrl(baseUrl, expiredAccessToken));
        return expiredResult.opened;
      },
      {
        timeout: 150000,
        intervals: [1000, 2000, 5000],
      },
    )
    .toBe(false);
});

test("webapp object-proxy isolates users by Keycloak subject", async ({ page, browser, request, infernixFixture }) => {
  test.setTimeout(120000);
  const fixture = infernixFixture;
  expect(fixture?.host).toBeTruthy();
  expect(fixture?.edgePort).toBeTruthy();
  const baseUrl = `http://${fixture.host}:${fixture.edgePort}`;
  const registration = await registerFreshKeycloakUser(page, baseUrl);
  const tokenPayload = await exchangeRegistrationCodeForToken(request, baseUrl, registration);
  expect(tokenPayload.access_token).toBeTruthy();

  const accessToken = tokenPayload.access_token;
  const claims = decodeJwtPayload(accessToken);
  expect(claims.sub).toBeTruthy();
  const contextId = `ctx-${randomUUID()}`;
  const displayName = `proxy-object-${randomUUID()}.txt`;
  const expectedKey = `users/${claims.sub}/contexts/${contextId}/uploads/${displayName}`;
  const objectBody = `hello from ${contextId}\n`;
  const uploadUrl = (ctx, name) =>
    `${baseUrl}/api/objects/upload?contextId=${encodeURIComponent(ctx)}&displayName=${encodeURIComponent(name)}`;
  const bytesUrl = (key, mime) =>
    `${baseUrl}/api/objects/download?key=${encodeURIComponent(key)}&mimeType=${encodeURIComponent(mime)}`;
  const downloadGrantRequest = {
    artifactUploadRequestContextId: contextId,
    artifactUploadRequestMimeType: "text/plain",
    artifactUploadRequestDisplayName: displayName,
  };

  // Phase 7 Sprint 7.25: the upload proxy requires a valid bearer JWT.
  const invalidUpload = await request.post(uploadUrl(contextId, displayName), {
    headers: { Authorization: "Bearer not-a-real-token", "Content-Type": "text/plain" },
    data: objectBody,
  });
  expect(invalidUpload.status()).toBe(401);

  const wrongRealmToken = await keycloakAdminAccessToken(request, baseUrl);
  const wrongRealmUpload = await request.post(uploadUrl(contextId, displayName), {
    headers: { Authorization: `Bearer ${wrongRealmToken}`, "Content-Type": "text/plain" },
    data: objectBody,
  });
  expect(wrongRealmUpload.status()).toBe(401);

  // Upload bytes through the webapp proxy; the response carries only the
  // server-derived ObjectRef (no browser presigned URL).
  const uploadResponse = await request.post(uploadUrl(contextId, displayName), {
    headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "text/plain" },
    data: objectBody,
  });
  expect(uploadResponse.ok()).toBeTruthy();
  const uploadGrant = await uploadResponse.json();
  expect(uploadGrant.artifactUploadGrantObjectRef.objectBucket).toBe("infernix-demo-objects");
  expect(uploadGrant.artifactUploadGrantObjectRef.objectKey).toBe(expectedKey);
  expect(uploadGrant.artifactUploadGrantPresignedUrl).toBeUndefined();

  // The download grant carries the authoritative disposition, no URL.
  const downloadGrantResponse = await request.post(`${baseUrl}/api/objects/download`, {
    headers: { Authorization: `Bearer ${accessToken}` },
    data: downloadGrantRequest,
  });
  expect(downloadGrantResponse.ok()).toBeTruthy();
  const downloadGrant = await downloadGrantResponse.json();
  expect(downloadGrant.artifactDownloadGrantObjectRef.objectKey).toBe(expectedKey);
  expect(downloadGrant.artifactDownloadGrantMimeType).toBe("text/plain");
  expect(renderDispositionTag(downloadGrant)).toBe("BoundedTextPreview");
  expect(downloadGrant.artifactDownloadGrantPresignedUrl).toBeUndefined();

  // Bytes stream from the webapp proxy under header auth and under the
  // operator cookie (the browser media src path).
  const headerGet = await request.get(bytesUrl(expectedKey, "text/plain"), {
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  expect(headerGet.ok()).toBeTruthy();
  expect(await headerGet.text()).toBe(objectBody);

  const cookieGet = await request.get(bytesUrl(expectedKey, "text/plain"), {
    headers: { Cookie: operatorTokenCookieHeader(accessToken) },
  });
  expect(cookieGet.ok()).toBeTruthy();
  expect(await cookieGet.text()).toBe(objectBody);

  // Render-disposition matrix (Phase 7 Sprint 7.27 flips MIDI/MusicXML/ZIP).
  const dispositionCases = [
    { mimeType: "image/png", displayName: "inline-image.png", disposition: "RenderInline" },
    { mimeType: "audio/wav", displayName: "inline-audio.wav", disposition: "RenderInline" },
    { mimeType: "video/mp4", displayName: "inline-video.mp4", disposition: "RenderInline" },
    { mimeType: "application/pdf", displayName: "document.pdf", disposition: "BrowserNativePdf" },
    { mimeType: "application/json", displayName: "preview.json", disposition: "BoundedTextPreview" },
    { mimeType: "audio/midi", displayName: "score.mid", disposition: "RenderMidi" },
    { mimeType: "application/vnd.recordare.musicxml+xml", displayName: "score.musicxml", disposition: "RenderMusicXml" },
    { mimeType: "application/zip", displayName: "stems.zip", disposition: "RenderZipStems" },
    { mimeType: "application/octet-stream", displayName: "artifact.bin", disposition: "DownloadOnly" },
  ];

  for (const artifactCase of dispositionCases) {
    const caseGrantResponse = await request.post(`${baseUrl}/api/objects/download`, {
      headers: { Authorization: `Bearer ${accessToken}` },
      data: {
        artifactUploadRequestContextId: contextId,
        artifactUploadRequestMimeType: artifactCase.mimeType,
        artifactUploadRequestDisplayName: artifactCase.displayName,
      },
    });
    expect(caseGrantResponse.ok()).toBeTruthy();
    const caseGrant = await caseGrantResponse.json();
    expect(caseGrant.artifactDownloadGrantMimeType).toBe(artifactCase.mimeType);
    expect(renderDispositionTag(caseGrant)).toBe(artifactCase.disposition);
  }

  // The Files list (Phase 7 Sprint 7.26) includes the uploaded object.
  const listResponse = await request.get(`${baseUrl}/api/objects/list`, {
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  expect(listResponse.ok()).toBeTruthy();
  const listJson = await listResponse.json();
  expect(listJson.some((ref) => ref.objectKey === expectedKey)).toBe(true);
  expect(listJson.every((ref) => ref.objectKey.startsWith(`users/${claims.sub}/`))).toBe(true);

  // Cross-user isolation: a second user cannot read, list, or delete the
  // first user's object key.
  const secondContext = await browser.newContext();
  const secondPage = await secondContext.newPage();
  try {
    const secondRegistration = await registerFreshKeycloakUser(secondPage, baseUrl);
    const secondTokenPayload = await exchangeRegistrationCodeForToken(request, baseUrl, secondRegistration);
    const secondAccessToken = secondTokenPayload.access_token;
    expect(secondAccessToken).toBeTruthy();
    const secondClaims = decodeJwtPayload(secondAccessToken);
    expect(secondClaims.sub).not.toBe(claims.sub);

    const crossUserGet = await request.get(bytesUrl(expectedKey, "text/plain"), {
      headers: { Authorization: `Bearer ${secondAccessToken}` },
    });
    expect(crossUserGet.status()).toBe(403);

    const crossUserDelete = await request.delete(`${baseUrl}/api/objects?key=${encodeURIComponent(expectedKey)}`, {
      headers: { Authorization: `Bearer ${secondAccessToken}` },
    });
    expect(crossUserDelete.status()).toBe(403);

    const secondList = await request.get(`${baseUrl}/api/objects/list`, {
      headers: { Authorization: `Bearer ${secondAccessToken}` },
    });
    expect(secondList.ok()).toBeTruthy();
    const secondListJson = await secondList.json();
    expect(secondListJson.every((ref) => ref.objectKey.startsWith(`users/${secondClaims.sub}/`))).toBe(true);

    const firstStillReadable = await request.get(bytesUrl(expectedKey, "text/plain"), {
      headers: { Authorization: `Bearer ${accessToken}` },
    });
    expect(firstStillReadable.ok()).toBeTruthy();
    expect(await firstStillReadable.text()).toBe(objectBody);
  } finally {
    await secondContext.close();
  }

  // Delete (Phase 7 Sprint 7.26) removes the caller's own object.
  const deleteResponse = await request.delete(`${baseUrl}/api/objects?key=${encodeURIComponent(expectedKey)}`, {
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  expect(deleteResponse.ok()).toBeTruthy();
  const missingAfterDelete = await request.get(bytesUrl(expectedKey, "text/plain"), {
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  expect(missingAfterDelete.status()).toBe(404);
});

test("self-service account deletion reaps demo state before Keycloak account action", async ({ page, request, infernixFixture }) => {
  test.setTimeout(accountDeletionTestTimeoutMs);
  const fixture = infernixFixture;
  expect(fixture?.host).toBeTruthy();
  expect(fixture?.edgePort).toBeTruthy();
  const baseUrl = `http://${fixture.host}:${fixture.edgePort}`;
  const wsFrames = collectWebSocketFrames(page);

  const unauthenticatedDelete = await request.delete(`${baseUrl}/api/account`);
  expect(unauthenticatedDelete.status()).toBe(401);

  page.on("dialog", async (dialog) => {
    expect(dialog.message()).toContain("Delete this account");
    await dialog.accept();
  });

  await page.goto(baseUrl);
  await page.locator("#login-button").click();
  await submitFreshRegistrationForm(page, baseUrl);
  await expect(page.locator("#connection-state")).toHaveText("Authenticated", { timeout: 60000 });
  await expect(page.locator("#delete-account-button")).toBeVisible();
  await waitForSentFrame(wsFrames, (frame) => frame.tag === "ClientHello");
  await waitForReceivedFrame(wsFrames, (frame) => frame.tag === "ServerContextListSnapshot");
  await waitForReceivedFrame(wsFrames, (frame) => frame.tag === "ServerDraftMapSnapshot");
  await expect(page.locator("#catalog-count")).not.toHaveText("0", { timeout: 60000 });

  const accessToken = await browserAccessToken(page);
  expect(accessToken).toBeTruthy();
  const claims = decodeJwtPayload(accessToken);
  expect(claims.sub).toBeTruthy();

  await page.locator("[data-role='open-new-context']").click();
  await expect(page.locator("[data-role='new-context-dialog']")).toBeVisible();
  await selectFirstSupportedModel(page);
  const createContextSentStartIndex = wsFrames.sent.length;
  await page.locator("[data-role='create-context']").click();
  const createContextFrame = await waitForSentFrameAfter(
    wsFrames,
    createContextSentStartIndex,
    (frame) => frame.tag === "ClientCreateContext",
  );
  const contextId = createContextFrame.clientCreateContextId;
  await waitForReceivedFrame(
    wsFrames,
    (frame) => frame.tag === "ServerContextListPatch" && JSON.stringify(frame).includes(contextId),
  );

  const draftReceivedStartIndex = wsFrames.received.length;
  const draftText = `account deletion draft ${randomUUID()}`;
  await fillDraftAndWaitForUpdate(page, wsFrames, wsFrames.sent.length, contextId, draftText);
  await waitForReceivedFrameAfter(
    wsFrames,
    draftReceivedStartIndex,
    (frame) => frame.tag === "ServerDraftMapPatch" && JSON.stringify(frame).includes(draftText),
  );

  const displayName = `account-delete-${randomUUID()}.txt`;
  const objectKey = `users/${claims.sub}/contexts/${contextId}/uploads/${displayName}`;
  const objectBytesUrl = `${baseUrl}/api/objects/download?key=${encodeURIComponent(objectKey)}&mimeType=${encodeURIComponent("text/plain")}`;
  const objectBody = `delete me ${randomUUID()}\n`;
  const uploadResponse = await request.post(
    `${baseUrl}/api/objects/upload?contextId=${encodeURIComponent(contextId)}&displayName=${encodeURIComponent(displayName)}`,
    {
      headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "text/plain" },
      data: objectBody,
    },
  );
  expect(uploadResponse.ok()).toBeTruthy();
  const uploadGrant = await uploadResponse.json();
  expect(uploadGrant.artifactUploadGrantObjectRef.objectKey).toBe(objectKey);
  const readableBeforeDelete = await request.get(objectBytesUrl, {
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  expect(readableBeforeDelete.ok()).toBeTruthy();
  expect(await readableBeforeDelete.text()).toBe(objectBody);

  const cleanupReports = [];
  await page.route("**/api/account", async (route) => {
    const routeResponse = await route.fetch();
    const body = await routeResponse.text();
    if (route.request().method() === "DELETE" && routeResponse.status() === 200) {
      cleanupReports.push(JSON.parse(body));
    }
    await route.fulfill({ response: routeResponse, body });
  });

  const deleteResponsePromise = page.waitForResponse(
    (response) =>
      response.url() === `${baseUrl}/api/account` &&
      response.request().method() === "DELETE" &&
      response.status() === 200,
    { timeout: accountCleanupRedirectTimeoutMs },
  );
  const cleanupReportPromise = (async () => {
    await expect
      .poll(
        () => cleanupReports.some((report) => report && report.cleanupComplete !== false),
        { timeout: accountCleanupRedirectTimeoutMs },
      )
      .toBeTruthy();
    return cleanupReports.find((report) => report && report.cleanupComplete !== false);
  })();
  const deleteActionRequestPromise = page.waitForRequest(
    (requestValue) =>
      requestValue.url().includes("/protocol/openid-connect/auth") &&
      requestValue.url().includes("kc_action=delete_account"),
    { timeout: accountCleanupRedirectTimeoutMs },
  );
  await page.locator("#delete-account-button").click();
  const [deleteResponse, deleteActionRequest, cleanupReport] = await Promise.all([
    deleteResponsePromise,
    deleteActionRequestPromise,
    cleanupReportPromise,
  ]);
  expect(deleteResponse.ok()).toBeTruthy();
  expect(cleanupReport.userId).toBe(claims.sub);
  expect(cleanupReport.cleanupComplete).toBe(true);
  expect(cleanupReport.minioObjectsDeleted).toBeGreaterThanOrEqual(1);
  expect(cleanupReport.pulsarTopicsDeleted).toBeGreaterThan(0);
  expect(cleanupReport.pulsarTopicsRemaining).toEqual([]);
  expect(new URL(deleteActionRequest.url()).searchParams.get("kc_action")).toBe("delete_account");

  const missingAfterDelete = await request.get(objectBytesUrl, {
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  expect(missingAfterDelete.status()).toBe(404);
});

// Phase 9 Sprint 9.8: RBAC + dashboard + lifecycle coverage. The hardcoded demo
// admin (chart values keycloak.realm.demoAdmin) carries the infernix-admin realm
// role and unlocks every cluster-wide surface; self-registered users are
// non-admin by construction and are denied at both the edge SecurityPolicy and
// the backend admin gate.
test("admin sees cluster-wide surfaces", async ({ page, request, infernixFixture }) => {
  test.setTimeout(120000);
  const fixture = infernixFixture;
  expect(fixture?.host).toBeTruthy();
  expect(fixture?.edgePort).toBeTruthy();
  const baseUrl = `http://${fixture.host}:${fixture.edgePort}`;

  // The published platform state is the cross-check source for the admin's
  // cluster-summary + monitoring surfaces.
  const publicationResponse = await request.get(`${baseUrl}/api/publication`);
  expect(publicationResponse.ok()).toBeTruthy();
  const publication = await publicationResponse.json();
  expect(publication.runtimeMode).toBeTruthy();

  await loginExistingKeycloakUser(page, baseUrl, "admin", "infernix-admin-demo");
  await expect(page.locator("html")).toHaveClass(/infernix-admin/, { timeout: 30000 });

  await expectOperatorRibbon(page);
  await expectAdminPanel(page);
  await expect(page.locator("#personal-dashboard")).toBeVisible();

  const clusterSummary = page.locator(".summary-item.cluster-summary");
  await expect(clusterSummary).toHaveCount(5);
  for (let index = 0; index < 5; index += 1) {
    await expect(clusterSummary.nth(index)).toBeVisible();
  }

  // The five cluster cells are real platform state, not the "loading" /
  // "Unavailable" placeholders; #runtime-mode mirrors the published runtimeMode.
  await expect(page.locator("#runtime-mode")).toHaveText(publication.runtimeMode, { timeout: 60000 });
  for (const cellId of ["#edge-port", "#control-plane-context", "#daemon-location", "#inference-dispatch-mode"]) {
    await expect(page.locator(cellId)).not.toHaveText("loading", { timeout: 60000 });
    await expect(page.locator(cellId)).not.toHaveText("Unavailable", { timeout: 60000 });
  }

  // The admin's browser token passes the edge SecurityPolicy on every operator
  // route and the backend admin gate.
  const adminToken = await browserAccessToken(page);
  expect(adminToken).toBeTruthy();
  const adminClaims = decodeJwtPayload(adminToken);
  expect(adminClaims.realm_access?.roles).toContain("infernix-admin");

  for (const operatorRoute of [
    `${baseUrl}/harbor`,
    `${baseUrl}/harbor/api`,
    `${baseUrl}/pulsar/admin/admin/v2/clusters`,
    `${baseUrl}/pulsar/ws`,
  ]) {
    await expectOperatorRouteAllowed(request, operatorRoute, adminToken);
  }

  const overviewResponse = await request.get(`${baseUrl}/api/admin/overview`, {
    headers: { Authorization: `Bearer ${adminToken}` },
  });
  expect(overviewResponse.status()).toBe(200);
  const overview = await overviewResponse.json();
  expect(typeof overview.catalogModelCount).toBe("number");
  expect(overview.runtimeMode).toBe(publication.runtimeMode);

  const cacheResponse = await request.get(`${baseUrl}/api/cache`, {
    headers: { Authorization: `Bearer ${adminToken}` },
  });
  expect(cacheResponse.status()).toBe(200);
});

test("non-admin is denied cluster-wide surfaces", async ({ page, request, infernixFixture }) => {
  test.setTimeout(120000);
  const fixture = infernixFixture;
  expect(fixture?.host).toBeTruthy();
  expect(fixture?.edgePort).toBeTruthy();
  const baseUrl = `http://${fixture.host}:${fixture.edgePort}`;

  await page.goto(baseUrl);
  await page.locator("#login-button").click();
  await submitFreshRegistrationForm(page, baseUrl);
  await expect(page.locator("#connection-state")).toHaveText("Authenticated", { timeout: 60000 });

  // A self-registered user is non-admin: no operator ribbon, no admin panel, and
  // the five cluster-summary cells are hidden.
  await expectNoOperatorRibbon(page);
  await expectNoAdminPanel(page);
  const clusterSummary = page.locator(".summary-item.cluster-summary");
  await expect(clusterSummary).toHaveCount(5);
  for (let index = 0; index < 5; index += 1) {
    await expect(clusterSummary.nth(index)).toBeHidden();
  }
  // The user-scoped surfaces stay visible to every authenticated user.
  await expect(page.locator("#personal-dashboard")).toBeVisible();
  await expect(page.locator("#catalog-count")).toBeVisible();

  const nonAdminToken = await browserAccessToken(page);
  expect(nonAdminToken).toBeTruthy();

  // The edge SecurityPolicy authorizes the operator routes to admins only: a
  // valid non-admin token is 403 everywhere.
  for (const operatorRoute of [
    `${baseUrl}/harbor`,
    `${baseUrl}/harbor/api`,
    `${baseUrl}/pulsar/admin/admin/v2/clusters`,
    `${baseUrl}/pulsar/ws`,
  ]) {
    await expectOperatorRouteForbidden(request, operatorRoute, nonAdminToken);
  }

  // The backend admin gate denies the same non-admin token on every admin API.
  const overviewForbidden = await request.get(`${baseUrl}/api/admin/overview`, {
    headers: { Authorization: `Bearer ${nonAdminToken}` },
  });
  expect(overviewForbidden.status()).toBe(403);
  const evictForbidden = await request.post(`${baseUrl}/api/cache/evict`, {
    headers: { Authorization: `Bearer ${nonAdminToken}` },
  });
  expect(evictForbidden.status()).toBe(403);
  const cacheForbidden = await request.get(`${baseUrl}/api/cache`, {
    headers: { Authorization: `Bearer ${nonAdminToken}` },
  });
  expect(cacheForbidden.status()).toBe(403);

  // Unauthenticated admin API access is 401.
  const overviewUnauthenticated = await request.get(`${baseUrl}/api/admin/overview`);
  expect(overviewUnauthenticated.status()).toBe(401);
});

test("sign out clears SSO before switching from user to admin", async ({ page, infernixFixture }) => {
  test.setTimeout(120000);
  const fixture = infernixFixture;
  expect(fixture?.host).toBeTruthy();
  expect(fixture?.edgePort).toBeTruthy();
  const baseUrl = `http://${fixture.host}:${fixture.edgePort}`;

  await page.goto(baseUrl);
  await page.locator("#login-button").click();
  await submitFreshRegistrationForm(page, baseUrl);
  await expect(page.locator("#connection-state")).toHaveText("Authenticated", { timeout: 60000 });
  await expectNoOperatorRibbon(page);

  await page.locator("#logout-button").click();
  await expect(page.locator("#connection-state")).toHaveText("Signed out", { timeout: 60000 });
  expect(await browserAccessToken(page)).toBe("");
  expect(await browserCookieValue(page, baseUrl, "infernix_operator_token")).toBe("");

  await page.locator("#login-button").click();
  await completeLoginPrompt(page, { username: "admin", password: "infernix-admin-demo" });
  await expect(page.locator("#connection-state")).toHaveText("Authenticated", { timeout: 60000 });
  await expect(page.locator("html")).toHaveClass(/infernix-admin/, { timeout: 30000 });
  await expectOperatorRibbon(page);
});

test("personal dashboard is disjoint per user", async ({ page, browser, request, infernixFixture }) => {
  test.setTimeout(120000);
  const fixture = infernixFixture;
  expect(fixture?.host).toBeTruthy();
  expect(fixture?.edgePort).toBeTruthy();
  const baseUrl = `http://${fixture.host}:${fixture.edgePort}`;

  // User A signs in through the SPA and uploads one object under their own
  // users/<sub>/ prefix.
  await page.goto(baseUrl);
  await page.locator("#login-button").click();
  await submitFreshRegistrationForm(page, baseUrl);
  await expect(page.locator("#connection-state")).toHaveText("Authenticated", { timeout: 60000 });
  const firstToken = await browserAccessToken(page);
  expect(firstToken).toBeTruthy();
  const firstClaims = decodeJwtPayload(firstToken);
  expect(firstClaims.sub).toBeTruthy();

  const contextId = `ctx-${randomUUID()}`;
  const displayName = `dashboard-object-${randomUUID()}.txt`;
  const expectedKey = `users/${firstClaims.sub}/contexts/${contextId}/uploads/${displayName}`;
  const objectBody = `dashboard body ${randomUUID()}\n`;
  const uploadResponse = await request.post(
    `${baseUrl}/api/objects/upload?contextId=${encodeURIComponent(contextId)}&displayName=${encodeURIComponent(displayName)}`,
    {
      headers: { Authorization: `Bearer ${firstToken}`, "Content-Type": "text/plain" },
      data: objectBody,
    },
  );
  expect(uploadResponse.ok()).toBeTruthy();
  const uploadGrant = await uploadResponse.json();
  expect(uploadGrant.artifactUploadGrantObjectRef.objectKey).toBe(expectedKey);

  // A's personal dashboard reflects A's own object (a focus nudge triggers the
  // /api/objects/list refresh so we do not wait a full 15s dashboard interval).
  await expect
    .poll(
      async () => {
        await page.evaluate(() => window.dispatchEvent(new Event("focus")));
        return Number((await page.locator("#personal-object-count").textContent()) || "");
      },
      { timeout: 30000 },
    )
    .toBeGreaterThanOrEqual(1);
  await expect(page.locator("#personal-object-list")).toContainText(displayName, { timeout: 30000 });

  // User B (a second browser context / fresh account) sees only their own data.
  const secondContext = await browser.newContext();
  const secondPage = await secondContext.newPage();
  try {
    await secondPage.goto(baseUrl);
    await secondPage.locator("#login-button").click();
    await submitFreshRegistrationForm(secondPage, baseUrl);
    await expect(secondPage.locator("#connection-state")).toHaveText("Authenticated", { timeout: 60000 });
    const secondToken = await browserAccessToken(secondPage);
    expect(secondToken).toBeTruthy();
    const secondClaims = decodeJwtPayload(secondToken);
    expect(secondClaims.sub).not.toBe(firstClaims.sub);

    // Poll the object COUNT (a stable value once the fetch lands), not the
    // status text — each focus nudge resets the status to "refreshing…", so
    // polling the status races the refresh. B's own dashboard settles to 0.
    await expect(secondPage.locator("#personal-dashboard")).toBeVisible();
    await expect
      .poll(
        async () => {
          await secondPage.evaluate(() => window.dispatchEvent(new Event("focus")));
          return (await secondPage.locator("#personal-object-count").textContent()) || "";
        },
        { timeout: 30000 },
      )
      .toBe("0");
    await expect(secondPage.locator("#personal-object-list")).not.toContainText(displayName);

    // B cannot read A's object through the server-scoped object proxy.
    const crossUserGet = await request.get(
      `${baseUrl}/api/objects/download?key=${encodeURIComponent(expectedKey)}&mimeType=${encodeURIComponent("text/plain")}`,
      { headers: { Authorization: `Bearer ${secondToken}` } },
    );
    expect(crossUserGet.status()).toBe(403);
  } finally {
    await secondContext.close();
  }

  // Clean up A's object.
  const deleteResponse = await request.delete(`${baseUrl}/api/objects?key=${encodeURIComponent(expectedKey)}`, {
    headers: { Authorization: `Bearer ${firstToken}` },
  });
  expect(deleteResponse.ok()).toBeTruthy();
});

test("returning user signs back in with the stored password", async ({ page, infernixFixture }) => {
  test.setTimeout(120000);
  const fixture = infernixFixture;
  expect(fixture?.host).toBeTruthy();
  expect(fixture?.edgePort).toBeTruthy();
  const baseUrl = `http://${fixture.host}:${fixture.edgePort}`;

  await page.goto(baseUrl);
  await page.locator("#login-button").click();
  const credentials = await submitFreshRegistrationForm(page, baseUrl);
  await expect(page.locator("#connection-state")).toHaveText("Authenticated", { timeout: 60000 });

  await page.locator("#logout-button").click();
  await expect(page.locator("#connection-state")).toHaveText("Signed out");

  // The returning user signs back in with the correct password after app
  // Sign out has cleared the upstream Keycloak SSO session.
  await page.locator("#login-button").click();
  await completeLoginPrompt(page, credentials);
  await expect(page.locator("#connection-state")).toHaveText("Authenticated", { timeout: 60000 });
});

test("sign-in with the wrong password is rejected at Keycloak", async ({ page, browser, infernixFixture }) => {
  test.setTimeout(120000);
  const fixture = infernixFixture;
  expect(fixture?.host).toBeTruthy();
  expect(fixture?.edgePort).toBeTruthy();
  const baseUrl = `http://${fixture.host}:${fixture.edgePort}`;

  // Register a user to obtain valid credentials.
  await page.goto(baseUrl);
  await page.locator("#login-button").click();
  const credentials = await submitFreshRegistrationForm(page, baseUrl);
  await expect(page.locator("#connection-state")).toHaveText("Authenticated", { timeout: 60000 });

  // Attempt the wrong password in a fresh context. A wrong password is rejected
  // by Keycloak: the error renders and the flow never redirects back to the app
  // with an auth code.
  const freshContext = await browser.newContext();
  const freshPage = await freshContext.newPage();
  try {
    await freshPage.goto(baseUrl);
    await freshPage.locator("#login-button").click();
    const usernameField = freshPage.locator("#username, input[name='username']").first();
    await expect(usernameField).toBeVisible({ timeout: 60000 });
    await usernameField.fill(credentials.username);
    await freshPage.locator("#password, input[name='password']").first().fill(`${credentials.password}-wrong`);
    await freshPage
      .locator("#kc-login, #kc-form-buttons input[type='submit'], button[type='submit'], input[type='submit']")
      .first()
      .click();

    await expect(
      freshPage
        .locator(".kc-feedback-text, #input-error, .pf-c-alert.pf-m-danger, .pf-v5-c-alert.pf-m-danger, .alert-error")
        .first(),
    ).toBeVisible({ timeout: 60000 });
    const stuckUrl = new URL(freshPage.url());
    expect(stuckUrl.pathname).toContain("/auth/realms/infernix/");
    expect(stuckUrl.searchParams.has("code")).toBe(false);
    await expect(freshPage.locator("#username, input[name='username']").first()).toBeVisible();
  } finally {
    await freshContext.close();
  }
});

test("deleted account credentials can no longer sign in", async ({ page, request, infernixFixture }) => {
  test.setTimeout(accountDeletionTestTimeoutMs);
  const fixture = infernixFixture;
  expect(fixture?.host).toBeTruthy();
  expect(fixture?.edgePort).toBeTruthy();
  const baseUrl = `http://${fixture.host}:${fixture.edgePort}`;

  await page.goto(baseUrl);
  await page.locator("#login-button").click();
  const credentials = await submitFreshRegistrationForm(page, baseUrl);
  await expect(page.locator("#connection-state")).toHaveText("Authenticated", { timeout: 60000 });

  // Sign out so no live SSO session survives the deletion, then delete the
  // account (the app's own DELETE /api/account reaping flow is covered by the
  // dedicated account-deletion test; here we reach the deleted-account state
  // deterministically via the Keycloak admin API and prove the auth loop fails).
  await page.locator("#logout-button").click();
  await expect(page.locator("#connection-state")).toHaveText("Signed out");
  await deleteKeycloakUserByUsername(request, baseUrl, credentials.username);

  // The deleted credentials no longer authenticate: Keycloak rejects them and
  // the app never reaches an authenticated session.
  await page.locator("#login-button").click();
  const usernameField = page.locator("#username, input[name='username']").first();
  await expect(usernameField).toBeVisible({ timeout: 60000 });
  await usernameField.fill(credentials.username);
  await page.locator("#password, input[name='password']").first().fill(credentials.password);
  await page
    .locator("#kc-login, #kc-form-buttons input[type='submit'], button[type='submit'], input[type='submit']")
    .first()
    .click();

  await expect(
    page
      .locator(".kc-feedback-text, #input-error, .pf-c-alert.pf-m-danger, .pf-v5-c-alert.pf-m-danger, .alert-error")
      .first(),
  ).toBeVisible({ timeout: 60000 });
  const stuckUrl = new URL(page.url());
  expect(stuckUrl.pathname).toContain("/auth/realms/infernix/");
  expect(stuckUrl.searchParams.has("code")).toBe(false);
});

test("browser artifact upload covers preview media PDF and download-only grants", async ({ page, request, infernixFixture }) => {
  test.setTimeout(900000);
  const fixture = infernixFixture;
  expect(fixture?.host).toBeTruthy();
  expect(fixture?.edgePort).toBeTruthy();
  const baseUrl = `http://${fixture.host}:${fixture.edgePort}`;
  const wsFrames = collectWebSocketFrames(page);
  const demoConfig = await fetchDemoConfig(request, baseUrl);

  await page.goto(baseUrl);
  await page.locator("#login-button").click();
  const credentials = await submitFreshRegistrationForm(page, baseUrl);
  await expect(page.locator("#connection-state")).toHaveText("Authenticated", { timeout: 60000 });
  await expect(page.locator("#catalog-count")).not.toHaveText("0", { timeout: 60000 });
  const helloFrame = await waitForSentFrame(wsFrames, (frame) => frame.tag === "ClientHello");
  expect(helloFrame.clientHelloUserId).toBeDefined();
  await waitForReceivedFrame(wsFrames, (frame) => frame.tag === "ServerContextListSnapshot");
  await waitForReceivedFrame(wsFrames, (frame) => frame.tag === "ServerDraftMapSnapshot");

  const cancelledContextStartIndex = wsFrames.sent.length;
  await page.locator("[data-role='open-new-context']").click();
  await expect(page.locator("[data-role='new-context-dialog']")).toBeVisible();
  await page.locator("[data-role='close-new-context']").click();
  await expect(page.locator("[data-role='new-context-dialog']")).toHaveCount(0);
  await page.waitForTimeout(250);
  expect(wsFrames.sent.slice(cancelledContextStartIndex).some((frame) => frame.tag === "ClientCreateContext")).toBe(false);
  await expect(page.locator(".chat-context-item")).toHaveCount(0);

  await page.locator("[data-role='open-new-context']").click();
  await expect(page.locator("[data-role='new-context-dialog']")).toBeVisible();
  const selectedModelId = await selectFirstSupportedModel(page);
  const createContextSentStartIndex = wsFrames.sent.length;
  await page.locator("[data-role='create-context']").click();
  await expect(page.locator("[data-role='new-context-dialog']")).toHaveCount(0);
  await expect(page.locator(".chat-context-item.active")).toBeVisible();
  const createContextFrame = await waitForSentFrameAfter(
    wsFrames,
    createContextSentStartIndex,
    (frame) => frame.tag === "ClientCreateContext" && frame.clientCreateContextModelId === selectedModelId,
  );
  expect(createContextFrame.clientCreateContextId).toBeTruthy();
  expect(createContextFrame.clientCreateContextTitle).toBe("New context");
  const subscribeFrame = await waitForSentFrameAfter(
    wsFrames,
    createContextSentStartIndex,
    (frame) => frame.tag === "ClientSubscribeContext" && frame.clientSubscribeContextId === createContextFrame.clientCreateContextId,
  );
  expect(subscribeFrame.clientSubscribeContextId).toBeTruthy();
  const contextPatchFrame = await waitForReceivedFrame(
    wsFrames,
    (frame) =>
      frame.tag === "ServerContextListPatch" &&
      JSON.stringify(frame).includes(subscribeFrame.clientSubscribeContextId) &&
      JSON.stringify(frame).includes(selectedModelId),
  );
  expect(JSON.stringify(contextPatchFrame)).toContain("ContextListUpsert");
  await expect(page.locator(".chat-context-item.active")).toHaveAttribute("data-model-id", selectedModelId);
  await expect(page.locator(".chat-context-item.active .chat-context-model")).toHaveText(selectedModelId);

  const renamedContextTitle = `Renamed context ${randomUUID()}`;
  const renameSentStartIndex = wsFrames.sent.length;
  const renameReceivedStartIndex = wsFrames.received.length;
  await page.locator(".chat-context-item.active [data-role='context-rename-title']").fill(renamedContextTitle);
  await page.locator(".chat-context-item.active [data-role='rename-context']").click();
  const renameFrame = await waitForSentFrameAfter(
    wsFrames,
    renameSentStartIndex,
    (frame) =>
      frame.tag === "ClientRenameContext" &&
      frame.clientRenameContextId === subscribeFrame.clientSubscribeContextId &&
      frame.clientRenameContextTitle === renamedContextTitle,
  );
  expect(renameFrame.clientRenameContextTitle).toBe(renamedContextTitle);
  const renamePatchFrame = await waitForReceivedFrameAfter(
    wsFrames,
    renameReceivedStartIndex,
    (frame) =>
      frame.tag === "ServerContextListPatch" &&
      JSON.stringify(frame).includes(subscribeFrame.clientSubscribeContextId) &&
      JSON.stringify(frame).includes(renamedContextTitle),
  );
  expect(JSON.stringify(renamePatchFrame)).toContain("ContextListUpsert");
  await expect(page.locator(".chat-context-item.active .chat-context-title")).toHaveText(renamedContextTitle);

  const softDeleteSentStartIndex = wsFrames.sent.length;
  const softDeleteReceivedStartIndex = wsFrames.received.length;
  await page.locator(".chat-context-item.active [data-role='soft-delete-context']").click();
  const softDeleteFrame = await waitForSentFrameAfter(
    wsFrames,
    softDeleteSentStartIndex,
    (frame) => frame.tag === "ClientSoftDeleteContext" && frame.clientSoftDeleteContextId === subscribeFrame.clientSubscribeContextId,
  );
  expect(softDeleteFrame.clientSoftDeleteContextId).toBe(subscribeFrame.clientSubscribeContextId);
  const softDeletePatchFrame = await waitForReceivedFrameAfter(
    wsFrames,
    softDeleteReceivedStartIndex,
    (frame) =>
      frame.tag === "ServerContextListPatch" &&
      JSON.stringify(frame).includes(subscribeFrame.clientSubscribeContextId) &&
      JSON.stringify(frame).includes("contextSummarySoftDeleted") &&
      JSON.stringify(frame).includes("true"),
  );
  expect(JSON.stringify(softDeletePatchFrame)).toContain("ContextListUpsert");
  await expect(page.locator(".chat-context-item.active")).toHaveAttribute("data-soft-deleted", "true");

  await page.locator("#route-artifacts").click();
  const artifactDownloadOptions = { frames: wsFrames, contextId: subscribeFrame.clientSubscribeContextId };

  const textName = `browser-upload-${randomUUID()}.txt`;
  const textCard = await uploadAndDownloadArtifact(page, {
    name: textName,
    mimeType: "text/plain",
    buffer: Buffer.from(textPreviewBody, "utf8"),
  }, artifactDownloadOptions);
  await expect(textCard.locator(".artifact-preview-text")).toHaveText(textPreviewBody);

  const jsonName = `browser-json-${randomUUID()}.json`;
  const jsonCard = await uploadAndDownloadArtifact(page, {
    name: jsonName,
    mimeType: "application/json",
    buffer: Buffer.from(jsonPreviewBody, "utf8"),
  }, artifactDownloadOptions);
  await expect(jsonCard.locator(".artifact-preview-text")).toHaveText(jsonPreviewBody);

  const pngName = `browser-inline-${randomUUID()}.png`;
  const imageCard = await uploadAndDownloadArtifact(page, {
    name: pngName,
    mimeType: "image/png",
    buffer: tinyPngBuffer(),
  }, artifactDownloadOptions);
  await expectRoutedPreviewSource(imageCard, ".artifact-preview-image");

  const audioName = `browser-audio-${randomUUID()}.wav`;
  const audioCard = await uploadAndDownloadArtifact(page, {
    name: audioName,
    mimeType: "audio/wav",
    buffer: tinyWavBuffer(),
  }, artifactDownloadOptions);
  await expectRoutedPreviewSource(audioCard, ".artifact-preview-audio");

  const videoName = `browser-video-${randomUUID()}.mp4`;
  const videoCard = await uploadAndDownloadArtifact(page, {
    name: videoName,
    mimeType: "video/mp4",
    buffer: tinyMp4Buffer(),
  }, artifactDownloadOptions);
  await expectRoutedPreviewSource(videoCard, ".artifact-preview-video");

  const pdfName = `browser-pdf-${randomUUID()}.pdf`;
  const pdfCard = await uploadAndDownloadArtifact(page, {
    name: pdfName,
    mimeType: "application/pdf",
    buffer: tinyPdfBuffer(),
  }, artifactDownloadOptions);
  await expect(pdfCard).toHaveAttribute("data-render-disposition", "BrowserNativePdf");
  await expectRoutedPreviewSource(pdfCard, ".artifact-preview-pdf");

  const midiName = `browser-midi-${randomUUID()}.mid`;
  const midiCard = await uploadAndDownloadArtifact(page, {
    name: midiName,
    mimeType: "audio/midi",
    buffer: tinyMidiBuffer(),
  }, artifactDownloadOptions);
  await expectInBrowserRenderReady(midiCard, "RenderMidi", ".artifact-preview-midi");

  const musicXmlName = `browser-musicxml-${randomUUID()}.musicxml`;
  const musicXmlCard = await uploadAndDownloadArtifact(page, {
    name: musicXmlName,
    mimeType: "application/vnd.recordare.musicxml+xml",
    buffer: musicXmlBuffer(),
  }, artifactDownloadOptions);
  await expectInBrowserRenderReady(musicXmlCard, "RenderMusicXml", ".artifact-preview-musicxml");

  const binaryName = `browser-binary-${randomUUID()}.bin`;
  const binaryCard = await uploadAndDownloadArtifact(page, {
    name: binaryName,
    mimeType: "application/octet-stream",
    buffer: binaryArtifactBuffer(),
  }, artifactDownloadOptions);
  await expectDownloadOnlyReady(binaryCard);

  await page.locator("#route-chat").click();
  const uploadedArtifacts = [
    { name: textName, mimeType: "text/plain" },
    { name: jsonName, mimeType: "application/json" },
    { name: pngName, mimeType: "image/png" },
    { name: audioName, mimeType: "audio/wav" },
    { name: videoName, mimeType: "video/mp4" },
    { name: pdfName, mimeType: "application/pdf" },
    { name: midiName, mimeType: "audio/midi" },
    { name: musicXmlName, mimeType: "application/vnd.recordare.musicxml+xml" },
    { name: binaryName, mimeType: "application/octet-stream" },
  ];
  for (const artifact of uploadedArtifacts) {
    await expectConversationUploadVisible(page, wsFrames, artifact, subscribeFrame.clientSubscribeContextId);
  }

  prepareEngineDeploymentForModelId(fixture, demoConfig, selectedModelId);
  const promptText = `summarize uploaded artifacts ${randomUUID()}`;
  await page.locator("textarea[name='prompt']").fill(promptText);
  const draftFrame = await waitForSentFrame(
    wsFrames,
    (frame) => frame.tag === "ClientUpdateDraft" && frame.clientUpdateDraftText === promptText,
  );
  expect(draftFrame.clientUpdateDraftContextId).toBe(subscribeFrame.clientSubscribeContextId);
  const draftPatchFrame = await waitForReceivedFrame(
    wsFrames,
    (frame) => frame.tag === "ServerDraftMapPatch" && JSON.stringify(frame).includes(promptText),
  );
  expect(JSON.stringify(draftPatchFrame)).toContain("DraftMapUpsert");
  await expect(page.locator("textarea[name='prompt']")).toHaveValue(promptText);

  const draftReconnectSentStartIndex = wsFrames.sent.length;
  const draftReconnectReceivedStartIndex = wsFrames.received.length;
  await page.evaluate(() => {
    if (typeof window.__infernixForceWebSocketClose !== "function") {
      throw new Error("WebSocket diagnostic close hook was not installed");
    }
    window.__infernixForceWebSocketClose();
  });
  await waitForSentFrameAfter(
    wsFrames,
    draftReconnectSentStartIndex,
    (frame) => frame.tag === "ClientHello",
    websocketReconnectTimeoutMs,
  );
  await waitForSentFrameAfter(
    wsFrames,
    draftReconnectSentStartIndex,
    (frame) => frame.tag === "ClientSubscribeContext" && frame.clientSubscribeContextId === subscribeFrame.clientSubscribeContextId,
    websocketReconnectTimeoutMs,
  );
  await waitForReceivedFrameAfter(
    wsFrames,
    draftReconnectReceivedStartIndex,
    (frame) => frame.tag === "ServerDraftMapPatch" && JSON.stringify(frame).includes(promptText),
    websocketReconnectTimeoutMs,
  );
  await expect(page.locator("textarea[name='prompt']")).toHaveValue(promptText, { timeout: 60000 });

  await page.locator("form[data-role='chat-draft-editor']").evaluate((form) => form.requestSubmit());

  const submitFrame = await waitForSentFrame(
    wsFrames,
    (frame) => frame.tag === "ClientSubmitPrompt" && frame.clientSubmitPromptPayload?.promptText === promptText,
  );
  const patchFrame = await waitForReceivedFrame(
    wsFrames,
    (frame) => frame.tag === "ServerConversationPatch" && JSON.stringify(frame).includes(promptText),
  );
  const promptMessageId = conversationPatchMessageId(patchFrame);
  expect(promptMessageId).toBeTruthy();
  await expect(page.locator(".chat-message.prompt").last()).toContainText(promptText);
  expect(JSON.stringify(patchFrame)).toContain("ConversationStateAppendMessage");
  const uploadedKeys = submitFrame.clientSubmitPromptPayload.promptUserUploads.map((ref) => ref.objectKey);
  expect(uploadedKeys).toEqual(
    expect.arrayContaining([
      expect.stringContaining(textName),
      expect.stringContaining(jsonName),
      expect.stringContaining(pngName),
      expect.stringContaining(audioName),
      expect.stringContaining(videoName),
      expect.stringContaining(pdfName),
    ]),
  );
  expect(submitFrame.clientSubmitPromptPayload.promptClientIdempotencyKey).toContain("prompt-");

  const queuedPromptText = `second queued prompt ${randomUUID()}`;
  const queuedPromptSentStartIndex = wsFrames.sent.length;
  const queuedPromptReceivedStartIndex = wsFrames.received.length;
  await page.locator("textarea[name='prompt']").fill(queuedPromptText);
  await waitForSentFrameAfter(
    wsFrames,
    queuedPromptSentStartIndex,
    (frame) => frame.tag === "ClientUpdateDraft" && frame.clientUpdateDraftText === queuedPromptText,
  );
  await waitForReceivedFrameAfter(
    wsFrames,
    queuedPromptReceivedStartIndex,
    (frame) =>
      frame.tag === "ServerDraftMapPatch" &&
      JSON.stringify(frame).includes(subscribeFrame.clientSubscribeContextId) &&
      JSON.stringify(frame).includes(queuedPromptText),
  );
  await expect(page.locator("textarea[name='prompt']")).toHaveValue(queuedPromptText, { timeout: 30000 });
  await page.locator("form[data-role='chat-draft-editor']").evaluate((form) => form.requestSubmit());
  const queuedSubmitFrame = await waitForSentFrameAfter(
    wsFrames,
    queuedPromptSentStartIndex,
    (frame) => frame.tag === "ClientSubmitPrompt" && frame.clientSubmitPromptPayload?.promptText === queuedPromptText,
  );
  expect(queuedSubmitFrame.clientSubmitPromptContextId).toBe(subscribeFrame.clientSubscribeContextId);
  expect(queuedSubmitFrame.clientSubmitPromptPayload.promptClientIdempotencyKey).toContain("prompt-");
  const queuedPatchFrame = await waitForReceivedFrameAfter(
    wsFrames,
    queuedPromptReceivedStartIndex,
    (frame) => frame.tag === "ServerConversationPatch" && JSON.stringify(frame).includes(queuedPromptText),
  );
  const queuedPromptMessageId = conversationPatchMessageId(queuedPatchFrame);
  expect(queuedPromptMessageId).toBeTruthy();
  await expect(page.locator(".chat-message.prompt").last()).toContainText(queuedPromptText);
  await expect(page.locator(".chat-pending-indicator.warning")).toHaveText("2 queued prompts", { timeout: 60000 });

  const clearDraftFrame = await waitForSentFrame(
    wsFrames,
    (frame) => frame.tag === "ClientUpdateDraft" && frame.clientUpdateDraftText === "",
  );
  expect(clearDraftFrame.clientUpdateDraftContextId).toBe(subscribeFrame.clientSubscribeContextId);
  const draftRemovePatchFrame = await waitForReceivedFrame(
    wsFrames,
    (frame) => frame.tag === "ServerDraftMapPatch" && JSON.stringify(frame).includes("DraftMapRemove"),
  );
  expect(JSON.stringify(draftRemovePatchFrame)).toContain(subscribeFrame.clientSubscribeContextId);

  const cancelSentStartIndex = wsFrames.sent.length;
  const cancelReceivedStartIndex = wsFrames.received.length;
  await page.locator("[data-role='cancel-latest-prompt']").click();
  const cancelFrame = await waitForSentFrameAfter(
    wsFrames,
    cancelSentStartIndex,
    (frame) => frame.tag === "ClientCancelPrompt" && frame.clientCancelPromptUserPromptMessageId === queuedPromptMessageId,
  );
  expect(cancelFrame.clientCancelPromptContextId).toBe(subscribeFrame.clientSubscribeContextId);
  const cancelPatchFrame = await waitForReceivedFrameAfter(
    wsFrames,
    cancelReceivedStartIndex,
    (frame) =>
      frame.tag === "ServerConversationPatch" &&
      JSON.stringify(frame).includes("ConversationCancelEvent") &&
      JSON.stringify(frame).includes(queuedPromptMessageId),
  );
  expect(JSON.stringify(cancelPatchFrame)).toContain("ConversationStateAppendMessage");
  await expect(page.locator(".chat-message.cancel").last()).toContainText(queuedPromptMessageId);

  const reconnectSentStartIndex = wsFrames.sent.length;
  const reconnectReceivedStartIndex = wsFrames.received.length;
  await page.evaluate(() => {
    if (typeof window.__infernixForceWebSocketClose !== "function") {
      throw new Error("WebSocket diagnostic close hook was not installed");
    }
    window.__infernixForceWebSocketClose();
  });
  await expect(page.locator("#connection-state")).toHaveText("Authenticated");
  await waitForSentFrameAfter(
    wsFrames,
    reconnectSentStartIndex,
    (frame) => frame.tag === "ClientHello",
    websocketReconnectTimeoutMs,
  );
  const reconnectSubscribeFrame = await waitForSentFrameAfter(
    wsFrames,
    reconnectSentStartIndex,
    (frame) => frame.tag === "ClientSubscribeContext" && frame.clientSubscribeContextId === subscribeFrame.clientSubscribeContextId,
    websocketReconnectTimeoutMs,
  );
  expect(reconnectSubscribeFrame.clientSubscribeContextId).toBe(subscribeFrame.clientSubscribeContextId);
  await waitForReceivedFrameAfter(
    wsFrames,
    reconnectReceivedStartIndex,
    (frame) => frame.tag === "ServerConversationSnapshot" && JSON.stringify(frame).includes(subscribeFrame.clientSubscribeContextId),
    websocketReconnectTimeoutMs,
  );

  const postReconnectPrompt = `continue after websocket reconnect ${randomUUID()}`;
  const postReconnectSentStartIndex = wsFrames.sent.length;
  await fillDraftAndWaitForUpdate(
    page,
    wsFrames,
    postReconnectSentStartIndex,
    subscribeFrame.clientSubscribeContextId,
    postReconnectPrompt,
    60000,
  );
  const postReconnectSubmitStartIndex = wsFrames.sent.length;
  const postReconnectReceivedStartIndex = wsFrames.received.length;
  await page.locator("form[data-role='chat-draft-editor'] button[type='submit']").click();
  await waitForSentFrameAfter(
    wsFrames,
    postReconnectSubmitStartIndex,
    (frame) => frame.tag === "ClientSubmitPrompt" && frame.clientSubmitPromptPayload?.promptText === postReconnectPrompt,
  );
  await waitForReceivedFrameAfter(
    wsFrames,
    postReconnectReceivedStartIndex,
    (frame) => frame.tag === "ServerConversationPatch" && JSON.stringify(frame).includes(postReconnectPrompt),
  );

  const podReplacementSentStartIndex = wsFrames.sent.length;
  const podReplacementReceivedStartIndex = wsFrames.received.length;
  await replaceDemoPods(infernixFixture);
  await waitForSentFrameAfter(wsFrames, podReplacementSentStartIndex, (frame) => frame.tag === "ClientHello", 120000);
  await waitForSentFrameAfter(
    wsFrames,
    podReplacementSentStartIndex,
    (frame) => frame.tag === "ClientSubscribeContext" && frame.clientSubscribeContextId === subscribeFrame.clientSubscribeContextId,
    120000,
  );
  await waitForReceivedFrameAfter(
    wsFrames,
    podReplacementReceivedStartIndex,
    (frame) => frame.tag === "ServerConversationSnapshot" && JSON.stringify(frame).includes(subscribeFrame.clientSubscribeContextId),
    120000,
  );

  const postPodReplacementPrompt = `continue after frontend pod replacement ${randomUUID()}`;
  const postPodReplacementSentStartIndex = wsFrames.sent.length;
  const postPodReplacementReceivedStartIndex = wsFrames.received.length;
  await fillDraftAndWaitForUpdate(
    page,
    wsFrames,
    postPodReplacementSentStartIndex,
    subscribeFrame.clientSubscribeContextId,
    postPodReplacementPrompt,
    120000,
  );
  await waitForReceivedFrameAfter(
    wsFrames,
    postPodReplacementReceivedStartIndex,
    (frame) =>
      frame.tag === "ServerDraftMapPatch" &&
      JSON.stringify(frame).includes(subscribeFrame.clientSubscribeContextId) &&
      JSON.stringify(frame).includes(postPodReplacementPrompt),
    120000,
  );
  await expect(page.locator("textarea[name='prompt']")).toHaveValue(postPodReplacementPrompt, { timeout: 30000 });
  await page.locator("form[data-role='chat-draft-editor']").evaluate((form) => form.requestSubmit());
  await waitForSentFrameAfter(
    wsFrames,
    postPodReplacementSentStartIndex,
    (frame) => frame.tag === "ClientSubmitPrompt" && frame.clientSubmitPromptPayload?.promptText === postPodReplacementPrompt,
  );
  await waitForReceivedFrameAfter(
    wsFrames,
    postPodReplacementReceivedStartIndex,
    (frame) => frame.tag === "ServerConversationPatch" && JSON.stringify(frame).includes(postPodReplacementPrompt),
    120000,
  );

  const reloadDraftText = `restore this draft after reload ${randomUUID()}`;
  const reloadDraftSentStartIndex = wsFrames.sent.length;
  const reloadDraftReceivedStartIndex = wsFrames.received.length;
  await page.locator("textarea[name='prompt']").fill(reloadDraftText);
  await waitForSentFrameAfter(
    wsFrames,
    reloadDraftSentStartIndex,
    (frame) => frame.tag === "ClientUpdateDraft" && frame.clientUpdateDraftText === reloadDraftText,
  );
  await waitForReceivedFrameAfter(
    wsFrames,
    reloadDraftReceivedStartIndex,
    (frame) => frame.tag === "ServerDraftMapPatch" && JSON.stringify(frame).includes(reloadDraftText),
  );

  const reloadSentStartIndex = wsFrames.sent.length;
  const reloadReceivedStartIndex = wsFrames.received.length;
  await page.reload();
  await expect(page.locator("#connection-state")).toHaveText("Signed out");
  await page.locator("#login-button").click();
  await completeLoginPromptIfPresent(page, credentials);
  await expect(page.locator("#connection-state")).toHaveText("Authenticated", { timeout: 60000 });
  await waitForSentFrameAfter(wsFrames, reloadSentStartIndex, (frame) => frame.tag === "ClientHello");
  await waitForSentFrameAfter(
    wsFrames,
    reloadSentStartIndex,
    (frame) => frame.tag === "ClientSubscribeContext" && frame.clientSubscribeContextId === subscribeFrame.clientSubscribeContextId,
  );
  await waitForReceivedFrameAfter(
    wsFrames,
    reloadReceivedStartIndex,
    (frame) => frame.tag === "ServerDraftMapPatch" && JSON.stringify(frame).includes(reloadDraftText),
  );
  await expect(page.locator("textarea[name='prompt']")).toHaveValue(reloadDraftText, { timeout: 60000 });
});

// Phase 7 Sprint 7.15 (2026-05-31): browser-layer per-model smoke matrix.
// The integration suite exercises every catalog model via the engine
// daemon (`engineProcessed: ...` traces); this test mirrors the same
// coverage at the browser layer so the routed SPA + WebSocket + Pulsar
// + engine chain is proven against the full demo-config catalog, not
// just the representative model the durable-context prompt roundtrip
// spec exercises.
test("browser per-model smoke matrix exercises every catalog model", async ({ page, request, infernixFixture }) => {
  test.setTimeout(browserMatrixTestTimeoutMs);
  const fixture = infernixFixture;
  expect(fixture?.host).toBeTruthy();
  expect(fixture?.edgePort).toBeTruthy();
  const baseUrl = `http://${fixture.host}:${fixture.edgePort}`;
  const wsFrames = collectWebSocketFrames(page);

  const demoConfigResponse = await request.get(`${baseUrl}/api/demo-config`);
  expect(demoConfigResponse.ok()).toBeTruthy();
  const demoConfig = await demoConfigResponse.json();
  expect(Array.isArray(demoConfig.models)).toBe(true);
  expect(demoConfig.models.length).toBeGreaterThan(0);

  await page.goto(baseUrl);
  await page.locator("#login-button").click();
  await submitFreshRegistrationForm(page, baseUrl);
  await expect(page.locator("#connection-state")).toHaveText("Authenticated", { timeout: 60000 });
  await expect(page.locator("#catalog-count")).not.toHaveText("0", { timeout: 60000 });
  await waitForSentFrame(wsFrames, (frame) => frame.tag === "ClientHello");
  await waitForReceivedFrame(wsFrames, (frame) => frame.tag === "ServerContextListSnapshot");
  await waitForReceivedFrame(wsFrames, (frame) => frame.tag === "ServerDraftMapSnapshot");

  // The model picker only renders inside the new-context dialog;
  // open the dialog once to enumerate selectable models, then close
  // it so each per-model iteration starts from the same baseline.
  await page.locator("[data-role='open-new-context']").click();
  await expect(page.locator("[data-role='new-context-dialog']")).toBeVisible();
  const modelPickerOptions = await page
    .locator("[data-role='model-picker'] option")
    .evaluateAll((nodes) =>
      nodes
        .map((node) => ({ value: node.value, label: node.textContent || "" }))
        .filter((option) => option.value),
    );
  expect(modelPickerOptions.length).toBeGreaterThan(0);
  // Phase 6 Sprint 6.36: catalog-completeness guard. The picker must expose
  // EXACTLY the active substrate's published catalog (the README matrix rows
  // minus the active-mode residuals, since residuals never enter
  // catalogForMode), so a silently shrunken catalog cannot pass by exercising
  // fewer rows. Compare the picker option ids to the demo-config model ids as
  // sets.
  const pickerModelIds = modelPickerOptions.map((option) => option.value).sort();
  const catalogModelIds = demoConfig.models.map((model) => model.modelId).sort();
  expect(pickerModelIds).toEqual(catalogModelIds);
  await page.locator("[data-role='close-new-context']").click();
  await expect(page.locator("[data-role='new-context-dialog']")).toHaveCount(0);

  const matrixToken = randomUUID();
  const contextByModel = new Map();

  for (let index = 0; index < modelPickerOptions.length; index += 1) {
    const { value: modelId } = modelPickerOptions[index];
    const createSentStart = wsFrames.sent.length;
    const createReceivedStart = wsFrames.received.length;

    await page.locator("[data-role='open-new-context']").click();
    await expect(page.locator("[data-role='new-context-dialog']")).toBeVisible();
    await page.locator("[data-role='model-picker']").selectOption(modelId);
    await expect(page.locator("[data-role='model-picker']")).toHaveValue(modelId);
    await page.locator("[data-role='create-context']").click();
    await expect(page.locator("[data-role='new-context-dialog']")).toHaveCount(0);

    const createFrame = await waitForSentFrameAfter(
      wsFrames,
      createSentStart,
      (frame) => frame.tag === "ClientCreateContext" && frame.clientCreateContextModelId === modelId,
    );
    expect(createFrame.clientCreateContextId).toBeTruthy();
    contextByModel.set(modelId, createFrame.clientCreateContextId);

    await waitForReceivedFrameAfter(
      wsFrames,
      createReceivedStart,
      (frame) =>
        frame.tag === "ServerContextListPatch" &&
        JSON.stringify(frame).includes(createFrame.clientCreateContextId) &&
        JSON.stringify(frame).includes(modelId),
    );
  }

  // The per-context dispatcher polls every 30 seconds for new
  // conversation topics. Wait one poll cycle so every freshly created
  // context's worker has attached before we start submitting prompts;
  // otherwise the first prompt to a brand-new context would race the
  // dispatcher worker spawn and the test's bounded
  // waitForReceivedFrame envelope would expire before the engine
  // result flows back through the conversation topic.
  await page.waitForTimeout(35000);

  for (let index = 0; index < modelPickerOptions.length; index += 1) {
    const { value: modelId } = modelPickerOptions[index];
    const model = demoConfig.models.find((entry) => entry.modelId === modelId);
    expect(model).toBeTruthy();
    prepareEngineDeploymentForModelId(fixture, demoConfig, modelId);
    const contextId = contextByModel.get(modelId);
    expect(contextId).toBeTruthy();

    await selectContextAndWaitForSubscription(page, wsFrames, contextId);

    const inputArtifact = browserInputArtifactForModel(model, matrixToken, index);
    if (inputArtifact) {
      await page.locator("#route-artifacts").click();
      await refreshBrowserSession(page, wsFrames, contextId);
      const uploadSentStart = wsFrames.sent.length;
      const uploadReceivedStart = wsFrames.received.length;
      await uploadArtifactThroughBrowser(page, inputArtifact);
      await page.locator("#route-chat").click();
      await expectConversationUploadVisible(
        page,
        wsFrames,
        inputArtifact,
        contextId,
        uploadSentStart,
        uploadReceivedStart,
      );
      await selectContextAndWaitForSubscription(page, wsFrames, contextId);
    }
    await refreshBrowserSession(page, wsFrames, contextId);

    const submitSentStart = wsFrames.sent.length;
    const submitReceivedStart = wsFrames.received.length;
    const promptText = `smoke ${modelId} ${matrixToken}-${index}`;
    await page.locator("textarea[name='prompt']").fill(promptText);
    await waitForSentFrameAfter(
      wsFrames,
      submitSentStart,
      (frame) => frame.tag === "ClientUpdateDraft" && frame.clientUpdateDraftText === promptText,
    );

    // Wait for the broker echo before submitting so the SPA's
    // `state.chat.draftMap` has the new draft text. Without this, an
    // intervening `renderAll` (e.g. triggered by a late patch from a
    // prior iteration) would re-render the textarea from a stale
    // draftMap and reset its DOM value to empty before the submit
    // handler reads it, dropping the prompt text on the wire.
    await waitForReceivedFrameAfter(
      wsFrames,
      submitReceivedStart,
      (frame) =>
        frame.tag === "ServerDraftMapPatch" &&
        JSON.stringify(frame).includes(contextId) &&
        JSON.stringify(frame).includes(promptText),
    );
    await expect(page.locator("textarea[name='prompt']")).toHaveValue(promptText, { timeout: 30000 });

    await page
      .locator("form[data-role='chat-draft-editor']")
      .evaluate((form) => form.requestSubmit());

    const submitFrame = await waitForSentFrameAfter(
      wsFrames,
      submitSentStart,
      (frame) => frame.tag === "ClientSubmitPrompt" && frame.clientSubmitPromptPayload?.promptText === promptText,
    );
    const promptPatch = await waitForUserPromptConversationPatchAfter(
      wsFrames,
      submitReceivedStart,
      {
        contextId,
        promptText,
        minimumSocketId: submitFrame.__infernixSocketId,
      },
    );
    const userPromptMessageId = conversationPatchMessageId(promptPatch);
    expect(userPromptMessageId).toBeTruthy();

    const terminalResult = await waitForTerminalConversationPatchAfter(
      wsFrames,
      submitReceivedStart,
      {
        contextId,
        modelId,
        promptText,
        userPromptMessageId,
        minimumSocketId: submitFrame.__infernixSocketId,
      },
    );
    expect(JSON.stringify(terminalResult.frame)).toContain("ConversationStateAppendMessage");

    const expectedMemoryError = expectedModelMemoryLimitExceeded(model, demoConfig);
    if (expectedMemoryError) {
      expect(terminalResult.status).toBe("failed");
      expectModelMemoryLimitExceededPayload(terminalResult.result.inferenceResultError, expectedMemoryError);
      await expect(
        page.locator(`.chat-context-item.active[data-context-id="${contextId}"]`),
        `context ${contextId} should remain selected before rendering ${modelId}'s capacity result`,
      ).toBeVisible({ timeout: 10000 });
      await expectCapacityResultRendered(page, wsFrames, contextId, modelId, expectedMemoryError, userPromptMessageId);
      continue;
    }

    if (terminalResult.status === "failed") {
      throw new Error(
        `Model ${modelId} returned an unexpected failed inference result for prompt ${promptText}: ${JSON.stringify(
          terminalResult.frame,
        )}`,
      );
    }
    expect(terminalResult.status).toBe("completed");

    // Phase 6 Sprint 6.3: assert the per-family rendered result. The browser
    // is substrate-agnostic — it renders from the result payload's family
    // (inline text vs. an image/audio/video/download artifact) and never
    // branches on substrate id or engine binding. `infernix-demo` selected
    // the engine binding upstream from the active `.dhall`.
    const expectedKind = expectedResultRenderKind(model);
    const resultMessage = page.locator(".chat-message.result").last();
    await expect(resultMessage).toBeVisible({ timeout: 60000 });
    if (expectedKind === "text") {
      // Phase 6 Sprint 6.36: assert REAL inline text, not merely a non-empty
      // body. The "No inline output." placeholder is itself non-empty text, so
      // a fabricated or empty result would slip past a bare not-empty check.
      // Chat.purs marks the body with data-inline-output="present" only when
      // the result carried real inline output, so require that marker and
      // reject the placeholder outright.
      const resultBody = resultMessage.locator(".chat-message-body");
      await expect(resultBody).toHaveAttribute("data-inline-output", "present", {
        timeout: 60000,
      });
      await expect(resultBody).not.toHaveText("No inline output.");
      await expect(resultBody).not.toHaveText("", { timeout: 30000 });
      await expect(resultMessage.locator(".chat-result-artifact")).toHaveCount(0);
    } else {
      const artifacts = resultMessage.locator(`.chat-result-${expectedKind}`);
      await expect(artifacts).toHaveCount(1, { timeout: 30000 });
      const artifact = artifacts.first();
      await expect(artifact).toHaveAttribute("data-result-artifact-kind", expectedKind);
      await expect(artifact).toHaveAttribute("data-object-bucket", "infernix-demo-objects");
      await expect(artifact).toHaveAttribute("data-object-key", /.+/);
      // Phase 4 Sprint 4.23: fail-closed object-ref check. The completed-frame
      // wait above already FAILS the row on `inferenceResultStatus:"failed"`
      // (realness is the engine's job). Here we add a light existence check of
      // the returned object reference: read the rendered object ref and assert
      // a non-empty, well-formed engine-written key. The byte-level non-empty
      // fetch + magic-bytes probe runs in the integration suite, which holds
      // MinIO credentials (the browser download-grant API is user-key-scoped
      // and cannot mint a presigned GET for engine-written result keys). We
      // never assert dimensions / stem count / sample rate.
      const objectKey = await artifact.getAttribute("data-object-key");
      expect(objectKey && objectKey.trim().length).toBeGreaterThan(0);
      expect(objectKey).not.toMatch(/^\s*$/);
    }
  }
});

// Phase 6 Sprint 6.3: map a catalog model to its expected per-family result
// rendering, derived from the model's family + matrix-row metadata only
// (mirrors `Infernix.Models.resultFamilyForDescriptor`). Substrate-agnostic:
// no branch on substrate id or engine binding.
function expectedResultRenderKind(model) {
  const family = model?.family || "";
  const rowId = model?.matrixRowId || "";
  if (family === "llm" || family === "speech") return "text";
  if (family === "image") return "image";
  if (family === "video") return "video";
  if (family === "music" || family === "tool") return "download";
  if (family === "audio") {
    if (rowId.includes("bark")) return "audio";
    return "download";
  }
  return "text";
}

function expectedModelMemoryLimitExceeded(model, demoConfig) {
  const budget = demoConfig?.inferenceMemoryBudget;
  if (!budget || budget.kind !== "enforced") return null;
  const requiredMib = Number(model?.modelRamFootprintMib);
  const availableMib = Number(budget.availableMib);
  if (!Number.isFinite(requiredMib) || !Number.isFinite(availableMib)) return null;
  if (requiredMib <= availableMib) return null;
  return {
    modelId: model.modelId,
    requiredMib,
    availableMib,
    resource: budget.resource,
    source: budget.source,
  };
}

function expectModelMemoryLimitExceededPayload(error, expected) {
  expect(error).toBeTruthy();
  expect(error.modelMemoryLimitExceededModelId).toBe(expected.modelId);
  expect(error.modelMemoryLimitExceededRequiredMib).toBe(expected.requiredMib);
  expect(error.modelMemoryLimitExceededAvailableMib).toBe(expected.availableMib);
  expect(error.modelMemoryLimitExceededResource).toBe(expected.resource);
  expect(error.modelMemoryLimitExceededSource).toBe(expected.source);
}

// Phase 4 Sprint 4.23: route each input family to a REAL fixture, dispatched
// on the row's ResultFamily (mirrors `Infernix.Models.resultFamilyForDescriptor`).
// The OMR/tool row now receives a real single-staff score IMAGE (PNG) instead
// of MusicXML — this fixes the OMR input-type bug. Substrate-agnostic: no
// branch on substrate id or engine binding.
function browserInputArtifactForModel(model, matrixToken, index) {
  const family = browserInputFamily(model);
  if (!family) return null;
  const baseName = `matrix-input-${safeArtifactNameSegment(model?.modelId)}-${index}-${safeArtifactNameSegment(
    matrixToken,
  ).slice(0, 8)}`;
  switch (family) {
    case "speech":
      return { name: `${baseName}.wav`, mimeType: "audio/wav", buffer: speechWavBuffer() };
    case "source-separation":
      return {
        name: `${baseName}.wav`,
        mimeType: "audio/wav",
        buffer: separationMixtureWavBuffer(),
      };
    case "audio-to-midi":
    case "music-transcription":
      return {
        name: `${baseName}.wav`,
        mimeType: "audio/wav",
        buffer: instrumentArpeggioWavBuffer(),
      };
    case "optical-music-recognition":
      return { name: `${baseName}.png`, mimeType: "image/png", buffer: scoreImagePngBuffer() };
    default:
      return null;
  }
}

// Resolve a catalog row to the input-bearing ResultFamily that decides its
// fixture, or null for the prompt-only families. Mirrors
// `Infernix.Models.resultFamilyForDescriptor` / `modelRequiresInputObject`.
function browserInputFamily(model) {
  const family = model?.family || "";
  const rowId = model?.matrixRowId || "";
  if (family === "speech") return "speech";
  if (family === "music") return "music-transcription";
  if (family === "tool") return "optical-music-recognition";
  if (family === "audio") {
    if (rowId.includes("demucs") || rowId.includes("unmix")) return "source-separation";
    if (rowId.includes("basic-pitch")) return "audio-to-midi";
    return null; // bark / generative audio is prompt-only
  }
  return null;
}

function modelRequiresBrowserInputObject(model) {
  return browserInputFamily(model) !== null;
}

function safeArtifactNameSegment(value) {
  return String(value || "model").replace(/[^a-zA-Z0-9._-]+/g, "-").slice(0, 80);
}

function renderDispositionTag(downloadGrant) {
  const disposition = downloadGrant.artifactDownloadGrantRenderDisposition;
  return typeof disposition === "string" ? disposition : disposition?.tag;
}

async function expectReadableContrast(page, selector, minimumRatio = 4.5) {
  const ratio = await page.locator(selector).first().evaluate((element) => {
    function parseColor(value) {
      const match = value.match(/rgba?\(([^)]+)\)/);
      if (!match) {
        return { r: 255, g: 255, b: 255, a: 1 };
      }
      const parts = match[1].split(",").map((part) => part.trim());
      return {
        r: Number(parts[0]),
        g: Number(parts[1]),
        b: Number(parts[2]),
        a: parts.length >= 4 ? Number(parts[3]) : 1,
      };
    }

    function channel(value) {
      const normalized = value / 255;
      return normalized <= 0.03928 ? normalized / 12.92 : ((normalized + 0.055) / 1.055) ** 2.4;
    }

    function luminance(color) {
      return 0.2126 * channel(color.r) + 0.7152 * channel(color.g) + 0.0722 * channel(color.b);
    }

    function effectiveBackground(start) {
      let current = start;
      while (current && current.nodeType === Node.ELEMENT_NODE) {
        const color = parseColor(window.getComputedStyle(current).backgroundColor);
        if (color.a > 0.01) {
          return color;
        }
        current = current.parentElement;
      }
      return { r: 255, g: 255, b: 255, a: 1 };
    }

    const style = window.getComputedStyle(element);
    const foreground = parseColor(style.color);
    const background = effectiveBackground(element);
    const light = Math.max(luminance(foreground), luminance(background));
    const dark = Math.min(luminance(foreground), luminance(background));
    return (light + 0.05) / (dark + 0.05);
  });
  expect(ratio, `${selector} contrast ratio`).toBeGreaterThanOrEqual(minimumRatio);
}

async function expectUnobscuredAtCenter(page, selector) {
  const result = await page.locator(selector).first().evaluate((element) => {
    const rect = element.getBoundingClientRect();
    if (rect.width <= 0 || rect.height <= 0) {
      return false;
    }
    const top = document.elementFromPoint(rect.left + rect.width / 2, rect.top + rect.height / 2);
    return top === element || element.contains(top) || Boolean(top && top.contains(element));
  });
  expect(result, `${selector} is not covered at its center point`).toBe(true);
}

function conversationPatchMessageId(frame) {
  return frame?.serverConversationPatch?.appendMessage?.conversationMessageId || "";
}

function conversationPatchUserPromptPayload(frame) {
  const event = frame?.serverConversationPatch?.appendMessage?.conversationMessageEvent;
  if (event?.tag !== "ConversationUserPromptEvent") return null;
  return event.contents || null;
}

async function registerFreshKeycloakUser(page, baseUrl) {
  const state = `state-${randomUUID()}`;
  const nonce = `nonce-${randomUUID()}`;
  const codeVerifier = `infernix-e2e-${randomUUID().replaceAll("-", "")}`;
  const codeChallenge = createHash("sha256").update(codeVerifier).digest("base64url");
  const authUrl = new URL(`${baseUrl}/auth/realms/infernix/protocol/openid-connect/auth`);
  authUrl.searchParams.set("client_id", "infernix-spa");
  authUrl.searchParams.set("redirect_uri", `${baseUrl}/`);
  authUrl.searchParams.set("response_type", "code");
  authUrl.searchParams.set("scope", "openid");
  authUrl.searchParams.set("state", state);
  authUrl.searchParams.set("nonce", nonce);
  authUrl.searchParams.set("code_challenge", codeChallenge);
  authUrl.searchParams.set("code_challenge_method", "S256");

  await page.goto(authUrl.toString());
  await expect(page.locator("#username")).toBeVisible();
  await expect(page.locator("#kc-registration a")).toBeVisible();
  await page.locator("#kc-registration a").click();
  await expect(page.locator("#kc-register-form, form[action*='registration']")).toBeVisible();

  const username = `e2e-${randomUUID().slice(0, 8)}`;
  const password = `Infernix-${randomUUID().slice(0, 8)}-1`;
  await page.locator("#username, input[name='username']").fill(username);
  await fillIfPresent(page, "#email, input[name='email']", `${username}@example.invalid`);
  await fillIfPresent(page, "#firstName, input[name='firstName']", "Infernix");
  await fillIfPresent(page, "#lastName, input[name='lastName']", "E2E");
  await page.locator("#password, input[name='password']").fill(password);
  await fillIfPresent(page, "#password-confirm, input[name='password-confirm']", password);
  await page.locator("#kc-form-buttons input[type='submit'], button[type='submit'], input[type='submit']").first().click();

  const redirected = await waitForRegistrationRedirect(page, baseUrl);
  expect(redirected.searchParams.get("state")).toBe(state);
  expect(redirected.searchParams.get("code")).toBeTruthy();
  expect(redirected.searchParams.get("error")).toBeNull();
  return {
    code: redirected.searchParams.get("code"),
    codeVerifier,
    state,
  };
}

async function submitFreshRegistrationForm(page, baseUrl) {
  await expect(page.locator("#username")).toBeVisible();
  await expect(page.locator("#kc-registration a")).toBeVisible();
  await page.locator("#kc-registration a").click();
  await expect(page.locator("#kc-register-form, form[action*='registration']")).toBeVisible();

  const username = `e2e-${randomUUID().slice(0, 8)}`;
  const password = `Infernix-${randomUUID().slice(0, 8)}-1`;
  await page.locator("#username, input[name='username']").fill(username);
  await fillIfPresent(page, "#email, input[name='email']", `${username}@example.invalid`);
  await fillIfPresent(page, "#firstName, input[name='firstName']", "Infernix");
  await fillIfPresent(page, "#lastName, input[name='lastName']", "E2E");
  await page.locator("#password, input[name='password']").fill(password);
  await fillIfPresent(page, "#password-confirm, input[name='password-confirm']", password);
  await page.locator("#kc-form-buttons input[type='submit'], button[type='submit'], input[type='submit']").first().click();

  const redirected = await waitForRegistrationRedirect(page, baseUrl);
  expect(redirected.searchParams.get("code")).toBeTruthy();
  expect(redirected.searchParams.get("error")).toBeNull();
  return { redirected, username, password };
}

async function waitForRegistrationRedirect(page, baseUrl) {
  await page.waitForURL((url) => url.origin === baseUrl && url.pathname === "/" && url.searchParams.has("code"), { timeout: 60000 });
  const redirected = new URL(page.url());
  return redirected;
}

async function refreshBrowserSession(page, frames, expectedContextId = null) {
  const sentStart = frames.sent.length;
  const receivedStart = frames.received.length;
  const refreshedToken = await page.evaluate(async () => {
    if (typeof window.__infernixRefreshAccessToken !== "function") {
      return "";
    }
    return window.__infernixRefreshAccessToken();
  });
  expect(refreshedToken).toBeTruthy();
  const helloFrame = await waitForSentFrameAfter(
    frames,
    sentStart,
    (frame) => frame.tag === "ClientHello",
    websocketReconnectTimeoutMs,
  );
  const socketId = helloFrame.__infernixSocketId;
  if (expectedContextId) {
    await waitForSentFrameAfter(
      frames,
      sentStart,
      (frame) =>
        frame.__infernixSocketId === socketId &&
        frame.tag === "ClientSubscribeContext" &&
        frame.clientSubscribeContextId === expectedContextId,
      websocketReconnectTimeoutMs,
    );
    await waitForReceivedFrameAfter(
      frames,
      receivedStart,
      (frame) =>
        frame.__infernixSocketId === socketId &&
        frame.tag === "ServerConversationSnapshot" &&
        JSON.stringify(frame).includes(expectedContextId),
      websocketReconnectTimeoutMs,
    );
  }
  await waitForReceivedFrameAfter(
    frames,
    receivedStart,
    (frame) => frame.__infernixSocketId === socketId && frame.tag === "ServerDraftMapSnapshot",
    websocketReconnectTimeoutMs,
  );
  return socketId;
}

async function selectContextAndWaitForSubscription(page, frames, contextId) {
  const sentStart = frames.sent.length;
  const receivedStart = frames.received.length;
  await page
    .locator(`.chat-context-item[data-context-id="${contextId}"] [data-role='select-context']`)
    .click();
  await expect(
    page.locator(`.chat-context-item.active[data-context-id="${contextId}"]`),
  ).toBeVisible();
  try {
    const subscribeFrame = await waitForSentFrameAfter(
      frames,
      sentStart,
      (frame) => frame.tag === "ClientSubscribeContext" && frame.clientSubscribeContextId === contextId,
      15000,
    );
    const socketId = subscribeFrame.__infernixSocketId;
    await waitForReceivedFrameAfter(
      frames,
      receivedStart,
      (frame) =>
        frame.__infernixSocketId === socketId &&
        frame.tag === "ServerConversationSnapshot" &&
        JSON.stringify(frame).includes(contextId),
      websocketReconnectTimeoutMs,
    );
  } catch {
    await refreshBrowserSession(page, frames, contextId);
  }
}

function collectWebSocketFrames(page) {
  const frames = { sent: [], received: [], console: [], pageErrors: [] };
  let nextSocketId = 0;
  page.on("console", (message) => {
    pushCapped(frames.console, {
      type: message.type(),
      text: message.text(),
      location: message.location(),
    });
  });
  page.on("pageerror", (error) => {
    pushCapped(frames.pageErrors, {
      name: error.name,
      message: error.message,
      stack: error.stack,
    });
  });
  page.on("websocket", (socket) => {
    const socketId = nextSocketId;
    nextSocketId += 1;
    socket.on("framesent", (frame) => {
      try {
        frames.sent.push(parseWebSocketJsonFrame(frame, socketId));
      } catch {
        // The test only inspects Infernix JSON envelopes.
      }
    });
    socket.on("framereceived", (frame) => {
      try {
        frames.received.push(parseWebSocketJsonFrame(frame, socketId));
      } catch {
        // The test only inspects Infernix JSON envelopes.
      }
    });
  });
  return frames;
}

function pushCapped(items, item, limit = 200) {
  items.push(item);
  if (items.length > limit) {
    items.shift();
  }
}

function parseWebSocketJsonFrame(frame, socketId) {
  const parsed = JSON.parse(String(frame.payload));
  Object.defineProperty(parsed, "__infernixSocketId", {
    value: socketId,
    enumerable: false,
  });
  return parsed;
}

async function waitForSentFrame(frames, predicate) {
  return waitForFrame(frames.sent, predicate, "outbound");
}

async function waitForSentFrameAfter(frames, startIndex, predicate, timeoutMs) {
  return waitForFrameAfter(frames.sent, startIndex, predicate, "outbound", timeoutMs);
}

async function waitForReceivedFrame(frames, predicate) {
  return waitForFrame(frames.received, predicate, "inbound");
}

async function waitForReceivedFrameAfter(frames, startIndex, predicate, timeoutMs) {
  return waitForFrameAfter(frames.received, startIndex, predicate, "inbound", timeoutMs);
}

async function fillDraftAndWaitForUpdate(page, frames, startIndex, contextId, draftText, timeoutMs = 60000) {
  const deadline = Date.now() + timeoutMs;
  let lastError = null;
  while (Date.now() < deadline) {
    const remainingMs = Math.max(1000, deadline - Date.now());
    const activeContext = page.locator(`.chat-context-item.active[data-context-id="${contextId}"]`);
    const draftInput = page.locator("textarea[name='prompt']");
    await expect(activeContext).toBeVisible({ timeout: Math.min(5000, remainingMs) });
    await expect(draftInput).toBeVisible({ timeout: Math.min(5000, remainingMs) });
    await draftInput.fill(draftText);
    await expect(draftInput).toHaveValue(draftText, { timeout: Math.min(5000, remainingMs) });
    try {
      return await waitForSentFrameAfter(
        frames,
        startIndex,
        (frame) =>
          frame.tag === "ClientUpdateDraft" &&
          frame.clientUpdateDraftContextId === contextId &&
          frame.clientUpdateDraftText === draftText,
        Math.min(5000, Math.max(1000, deadline - Date.now())),
      );
    } catch (error) {
      lastError = error;
      await page.waitForTimeout(250);
    }
  }
  throw new Error(
    `Timed out waiting for outbound draft update for ${contextId} after ${timeoutMs}ms; last error: ${lastError?.message || "none"}`,
  );
}

async function waitForTerminalConversationPatchAfter(frames, startIndex, details) {
  // Service work uses Pulsar's 900-second ack timeout. A restarted engine can
  // redeliver just after that point, so the browser matrix waits through one
  // full redelivery window plus a second execution window before declaring the
  // row failed.
  const timeoutMs = browserMatrixResultTimeoutMs;
  const deadline = Date.now() + timeoutMs;
  let lastContextPatch = null;
  while (Date.now() < deadline) {
    const receivedFrames = frames.received.slice(startIndex);
    for (const frame of receivedFrames) {
      if (frame.tag !== "ServerConversationPatch") {
        continue;
      }
      const encoded = JSON.stringify(frame);
      if (!encoded.includes(details.contextId)) {
        continue;
      }
      if (
        typeof details.minimumSocketId === "number" &&
        typeof frame.__infernixSocketId === "number" &&
        frame.__infernixSocketId < details.minimumSocketId
      ) {
        continue;
      }
      lastContextPatch = frame;
      const result = conversationPatchInferenceResult(frame);
      if (!result) {
        continue;
      }
      if (details.userPromptMessageId && result.inferenceResultUserPromptMessageId !== details.userPromptMessageId) {
        continue;
      }
      if (result.inferenceResultStatus === "failed" || result.inferenceResultStatus === "completed") {
        // Sprint 6.39 (managed-state-transition doctrine): the readiness
        // transition must return typed evidence — a terminal conversation result
        // carrying one of the two typed terminal statuses plus a decoded result
        // object — not an unguarded or proxy signal. Assert the evidence shape so
        // a non-evidence readiness path fails closed here rather than silently
        // passing on an empty or malformed frame.
        expect(result).toBeTruthy();
        expect(["completed", "failed"]).toContain(result.inferenceResultStatus);
        return { frame, result, status: result.inferenceResultStatus };
      }
    }
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error(
    `Timed out waiting for terminal conversation result for model ${details.modelId} after ${timeoutMs}ms; received ${frames.received.length - startIndex} inbound frames after index ${startIndex}; last context patch: ${JSON.stringify(lastContextPatch)}`,
  );
}

async function waitForUserPromptConversationPatchAfter(frames, startIndex, details) {
  const timeoutMs = 60000;
  const deadline = Date.now() + timeoutMs;
  let lastContextPatch = null;
  while (Date.now() < deadline) {
    const receivedFrames = frames.received.slice(startIndex);
    for (const frame of receivedFrames) {
      if (frame.tag !== "ServerConversationPatch") {
        continue;
      }
      const encoded = JSON.stringify(frame);
      if (!encoded.includes(details.contextId)) {
        continue;
      }
      if (
        typeof details.minimumSocketId === "number" &&
        typeof frame.__infernixSocketId === "number" &&
        frame.__infernixSocketId < details.minimumSocketId
      ) {
        continue;
      }
      lastContextPatch = frame;
      const prompt = conversationPatchUserPromptPayload(frame);
      if (!prompt) {
        continue;
      }
      if (prompt.promptText === details.promptText) {
        return frame;
      }
    }
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error(
    `Timed out waiting for user-prompt conversation patch for context ${details.contextId} after ${timeoutMs}ms; last context patch: ${JSON.stringify(lastContextPatch)}`,
  );
}

function conversationPatchInferenceResult(frame) {
  const event = frame?.serverConversationPatch?.appendMessage?.conversationMessageEvent;
  if (event?.tag !== "ConversationInferenceResultEvent") return null;
  return event.contents || null;
}

async function waitForFrame(frames, predicate, direction) {
  const deadline = Date.now() + 10000;
  while (Date.now() < deadline) {
    const match = frames.find(predicate);
    if (match) {
      return match;
    }
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error(`Timed out waiting for ${direction} WebSocket frame`);
}

async function waitForFrameAfter(frames, startIndex, predicate, direction, timeoutMs = 10000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const match = frames.slice(startIndex).find(predicate);
    if (match) {
      return match;
    }
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error(`Timed out waiting for ${direction} WebSocket frame after index ${startIndex}`);
}

async function replaceDemoPods(fixture) {
  const originalPods = demoPodNames(fixture);
  expect(originalPods.length).toBeGreaterThan(0);
  runInfernixKubectl(fixture, [
    "-n",
    "platform",
    "delete",
    "pod",
    "-l",
    "app.kubernetes.io/name=infernix-demo",
    "--grace-period=0",
    "--force",
    "--wait=false",
  ]);
  const replacementPods = await waitForReplacementDemoPods(fixture, originalPods);
  for (const podName of replacementPods) {
    runInfernixKubectl(
      fixture,
      ["-n", "platform", "wait", "--for=condition=Ready", `pod/${podName}`, "--timeout=180s"],
      200000,
    );
  }
}

async function waitForReplacementDemoPods(fixture, originalPods) {
  const deadline = Date.now() + 180000;
  while (Date.now() < deadline) {
    const pods = demoPodNames(fixture);
    const originalsGone = originalPods.every((podName) => !pods.includes(podName));
    const replacements = pods.filter((podName) => !originalPods.includes(podName));
    if (originalsGone && replacements.length >= originalPods.length) {
      return replacements.slice(0, originalPods.length);
    }
    await new Promise((resolve) => setTimeout(resolve, 1000));
  }
  throw new Error(`Timed out waiting for replacement infernix-demo pods after deleting ${originalPods.join(", ")}`);
}

function demoPodNames(fixture) {
  return runInfernixKubectl(fixture, [
    "-n",
    "platform",
    "get",
    "pods",
    "-l",
    "app.kubernetes.io/name=infernix-demo",
    "-o",
    "jsonpath={.items[*].metadata.name}",
  ])
    .trim()
    .split(/\s+/)
    .filter((token) => /^infernix-demo-[a-z0-9-]+$/.test(token))
    .filter(Boolean);
}

async function fetchDemoConfig(request, baseUrl) {
  const demoConfigResponse = await request.get(`${baseUrl}/api/demo-config`);
  expect(demoConfigResponse.ok()).toBeTruthy();
  return demoConfigResponse.json();
}

function prepareEngineDeploymentForModelId(fixture, demoConfig, modelId) {
  if (demoConfig?.runtimeMode === "linux-cpu") {
    scaleGenericEngineDeployment(fixture, 1);
    return;
  }
  if (demoConfig?.runtimeMode !== "linux-gpu") {
    return;
  }
  const models = Array.isArray(demoConfig.models) ? demoConfig.models : [];
  const engineBindings = Array.isArray(demoConfig.engines) ? demoConfig.engines : [];
  const model = models.find((entry) => entry.modelId === modelId);
  if (!model) {
    throw new Error(`linux-gpu model ${modelId} is absent from the routed demo config`);
  }
  const binding = engineBindings.find((entry) => entry.engine === model.selectedEngine);
  if (!binding) {
    throw new Error(`linux-gpu model ${modelId} has no engine binding for ${model.selectedEngine}`);
  }
  const perEngineNames = Array.from(
    new Set(
      engineBindings
        .filter((entry) => entry.pythonNative)
        .map((entry) => perEngineNameFromAdapterId(entry.adapterId))
        .filter(Boolean),
    ),
  ).sort();
  const activeEngineName = binding.pythonNative ? perEngineNameFromAdapterId(binding.adapterId) : null;

  if (activeEngineName) {
    runInfernixKubectl(fixture, ["-n", "platform", "scale", "deployment/infernix-engine", "--replicas=0"]);
  }
  for (const engineName of perEngineNames) {
    const replicas = engineName === activeEngineName ? "1" : "0";
    runInfernixKubectl(fixture, [
      "-n",
      "platform",
      "scale",
      `deployment/infernix-engine-${engineName}`,
      `--replicas=${replicas}`,
    ]);
  }
  if (!activeEngineName) {
    scaleGenericEngineDeployment(fixture, 1);
  }
  // Sprint 5.12 (managed-state-transition doctrine): the kubectl rollout-status
  // proxy for readiness is removed. The engine deployment is scaled up above, but
  // readiness is now proven by the real model-bootstrap flow — the per-model
  // inference result only arrives after the ModelBootstrapReadyEvent stages the
  // weights and the engine runs the request. That result is awaited by the matrix
  // result wait bounded by clientModelBootstrapDeadlineMs (>= the server ceiling),
  // so the test waits on real readiness evidence rather than a pod-rollout proxy.
}

function scaleGenericEngineDeployment(fixture, replicas) {
  runInfernixKubectl(fixture, [
    "-n",
    "platform",
    "scale",
    "deployment/infernix-engine",
    `--replicas=${replicas}`,
  ]);
  // Sprint 5.12: no kubectl rollout-status readiness proxy — readiness is proven
  // by the real inference result awaited by the matrix result wait. See
  // scaleActiveEngineForBinding for the full rationale.
}

function perEngineNameFromAdapterId(adapterId) {
  if (typeof adapterId === "string" && adapterId.endsWith("-python")) {
    return adapterId.slice(0, -"-python".length);
  }
  return adapterId;
}

function runInfernixKubectl(fixture, args, timeoutMs = 120000) {
  expect(fixture?.infernixCommand).toBeTruthy();
  try {
    return execFileSync(fixture.infernixCommand, ["kubectl", ...args], {
      cwd: fixture.repoRoot || process.cwd(),
      encoding: "utf8",
      maxBuffer: 10 * 1024 * 1024,
      timeout: timeoutMs,
    });
  } catch (error) {
    const stdout = error.stdout ? String(error.stdout) : "";
    const stderr = error.stderr ? String(error.stderr) : "";
    throw new Error(`infernix kubectl ${args.join(" ")} failed\n${stdout}${stderr}`);
  }
}

async function completeLoginPromptIfPresent(page, credentials) {
  const usernameField = page.locator("#username, input[name='username']").first();
  if (await usernameField.isVisible({ timeout: 5000 }).catch(() => false)) {
    await fillLoginPrompt(page, usernameField, credentials);
  }
}

async function completeLoginPrompt(page, credentials) {
  const usernameField = page.locator("#username, input[name='username']").first();
  await expect(usernameField).toBeVisible({ timeout: 60000 });
  await fillLoginPrompt(page, usernameField, credentials);
}

async function fillLoginPrompt(page, usernameField, credentials) {
  await usernameField.fill(credentials.username);
  await page.locator("#password, input[name='password']").first().fill(credentials.password);
  await page.locator("#kc-login, #kc-form-buttons input[type='submit'], button[type='submit'], input[type='submit']").first().click();
}

async function expectOperatorRibbon(page) {
  const ribbon = page.locator(".operator-ribbon");
  await expect(ribbon).toBeVisible();
  await expect(ribbon.locator("[data-operator-route='/harbor']")).toHaveAttribute("href", "/harbor");
  await expect(ribbon.locator("[data-operator-route='/pulsar/admin']")).toHaveAttribute("href", "/pulsar/admin/admin/v2/clusters");
  // Phase 3 Sprint 3.13: the MinIO S3 operator-ribbon link is removed.
  await expect(ribbon.locator("[data-operator-route='/minio/s3']")).toHaveCount(0);
}

// Phase 9 Sprint 9.8: drive the SPA login for an EXISTING account (e.g. the
// hardcoded demo admin) so window.__infernixAccessToken + the operator cookie
// carry that account's token. Models registerFreshKeycloakUser but takes the
// Sign-in path and fills username/password instead of registering.
async function loginExistingKeycloakUser(page, baseUrl, username, password) {
  await page.goto(baseUrl);
  await page.locator("#login-button").click();
  const usernameField = page.locator("#username, input[name='username']").first();
  await expect(usernameField).toBeVisible({ timeout: 60000 });
  await usernameField.fill(username);
  await page.locator("#password, input[name='password']").first().fill(password);
  await page
    .locator("#kc-login, #kc-form-buttons input[type='submit'], button[type='submit'], input[type='submit']")
    .first()
    .click();
  await expect(page.locator("#connection-state")).toHaveText("Authenticated", { timeout: 60000 });
}

// Phase 9 Sprint 9.8: a non-admin never sees the operator ribbon — the ribbon is
// CSS-hidden and <html> never carries the .infernix-admin marker class.
async function expectNoOperatorRibbon(page) {
  await expect(page.locator(".operator-ribbon")).toBeHidden();
  await expect(page.locator("html")).not.toHaveClass(/infernix-admin/);
}

// Phase 9 Sprint 9.8: the admin monitoring panel is visible (CSS-gated on
// <html class="infernix-admin">, which already proves the admin gate applied)
// and populated by the admin-gated /api/admin/overview fetch. A real substrate
// id is alphanumeric and never the "loading"/"–" placeholder. The fetch only
// fires once the page is admin, so nudge a dashboard refresh each poll to avoid
// waiting a full 15s interval.
async function expectAdminPanel(page) {
  await expect(page.locator("#admin-panel")).toBeVisible({ timeout: 30000 });
  await expect
    .poll(
      async () => {
        await page.evaluate(() => window.dispatchEvent(new Event("focus")));
        return (await page.locator("#admin-substrate").textContent()) || "";
      },
      { timeout: 30000 },
    )
    .toMatch(/[a-z0-9]/i);
}

// Phase 9 Sprint 9.8: a non-admin never sees the cluster monitoring panel.
async function expectNoAdminPanel(page) {
  await expect(page.locator("#admin-panel")).toBeHidden();
}

// Phase 9 Sprint 9.8: the edge SecurityPolicy denies a valid non-admin token on
// every operator route with 403.
async function expectOperatorRouteForbidden(request, url, token) {
  const response = await request.get(url, {
    headers: { Authorization: `Bearer ${token}` },
  });
  expect(response.status()).toBe(403);
}

// Phase 9 Sprint 9.8: the edge SecurityPolicy lets an admin token PAST the
// admin authorization — i.e. it is never rejected 401/403. The precise property
// under test is "admin is not denied by the edge gate", so the backend's own
// status is allowed through: HTTP consoles (/harbor, /harbor/api, /pulsar/admin)
// answer 2xx/3xx, while a plain GET to the WebSocket route /pulsar/ws reaches the
// Pulsar servlet and legitimately answers a non-auth 4xx (upgrade required). The
// paired expectOperatorRouteForbidden proves the gate denies non-admins with 403,
// and the /api/admin/overview + /api/cache 200s prove real admin backend access.
async function expectOperatorRouteAllowed(request, url, token) {
  const response = await request.get(url, {
    headers: { Authorization: `Bearer ${token}` },
  });
  expect(response.status()).not.toBe(401);
  expect(response.status()).not.toBe(403);
}

// Phase 9 Sprint 9.8: reach the deleted-account state deterministically via the
// Keycloak admin API (the app's own DELETE /api/account reaping flow is covered
// by the dedicated account-deletion test). Uses the master-realm superuser to
// look up and delete the infernix-realm user by exact username.
async function deleteKeycloakUserByUsername(request, baseUrl, username) {
  const adminToken = await keycloakAdminAccessToken(request, baseUrl);
  const lookup = await request.get(
    `${baseUrl}/auth/admin/realms/infernix/users?username=${encodeURIComponent(username)}&exact=true`,
    { headers: { Authorization: `Bearer ${adminToken}` } },
  );
  expect(lookup.ok()).toBeTruthy();
  const users = await lookup.json();
  expect(Array.isArray(users)).toBe(true);
  expect(users.length).toBeGreaterThan(0);
  const userId = users[0].id;
  expect(userId).toBeTruthy();
  const deletion = await request.delete(
    `${baseUrl}/auth/admin/realms/infernix/users/${encodeURIComponent(userId)}`,
    { headers: { Authorization: `Bearer ${adminToken}` } },
  );
  expect(deletion.ok()).toBeTruthy();
  return userId;
}

async function browserAccessToken(page) {
  return page.evaluate(() => window.__infernixAccessToken || "");
}

async function browserCookieValue(page, baseUrl, name) {
  const cookies = await page.context().cookies(baseUrl);
  return cookies.find((cookie) => cookie.name === name)?.value || "";
}

function operatorTokenCookieHeader(accessToken) {
  return `infernix_operator_token=${accessToken}`;
}

// Phase 9 Sprint 9.8: the operator routes are admin-authorized at the edge
// (SecurityPolicy defaultAction Deny, allow only realm_access.roles ⊇
// infernix-admin), so a valid self-registered (non-admin) token is 403 and an
// unauthenticated request is 401.
async function expectJwtGatedOperatorRoute(request, url, nonAdminAccessToken) {
  const unauthenticated = await request.get(url);
  expect(unauthenticated.status()).toBe(401);

  const authenticated = await request.get(url, {
    headers: { Authorization: `Bearer ${nonAdminAccessToken}` },
  });
  expect(authenticated.status()).toBe(403);
}

async function exchangeRegistrationCodeForToken(request, baseUrl, registration) {
  const tokenResponse = await request.post(`${baseUrl}/auth/realms/infernix/protocol/openid-connect/token`, {
    form: {
      grant_type: "authorization_code",
      client_id: "infernix-spa",
      redirect_uri: `${baseUrl}/`,
      code: registration.code,
      code_verifier: registration.codeVerifier,
    },
  });
  expect(tokenResponse.ok()).toBeTruthy();
  return tokenResponse.json();
}

async function mintExpiredAccessTokenViaRealmLifespan(request, page, baseUrl) {
  const adminToken = await keycloakAdminAccessToken(request, baseUrl);
  const originalRealm = await keycloakAdminGetRealm(request, baseUrl, adminToken);
  const originalLifespan = originalRealm.accessTokenLifespan;
  expect(Number.isInteger(originalLifespan)).toBe(true);

  try {
    await keycloakAdminPutRealm(request, baseUrl, adminToken, { accessTokenLifespan: 1 });
    await expect.poll(async () => (await keycloakAdminGetRealm(request, baseUrl, adminToken)).accessTokenLifespan).toBe(1);

    const shortLivedRegistration = await requestAuthCodeForCurrentSession(page, baseUrl);
    const shortLivedTokenPayload = await exchangeRegistrationCodeForToken(request, baseUrl, shortLivedRegistration);
    const shortLivedToken = shortLivedTokenPayload.access_token;
    expect(shortLivedToken).toBeTruthy();
    const claims = decodeJwtPayload(shortLivedToken);
    expect(claims.exp - claims.iat).toBeLessThanOrEqual(5);
    await waitUntilJwtExpiresPastLeeway(claims);
    return shortLivedToken;
  } finally {
    await keycloakAdminPutRealm(request, baseUrl, adminToken, { accessTokenLifespan: originalLifespan });
    await expect.poll(async () => (await keycloakAdminGetRealm(request, baseUrl, adminToken)).accessTokenLifespan).toBe(originalLifespan);
  }
}

async function requestAuthCodeForCurrentSession(page, baseUrl) {
  const state = `state-${randomUUID()}`;
  const nonce = `nonce-${randomUUID()}`;
  const codeVerifier = `infernix-e2e-${randomUUID().replaceAll("-", "")}`;
  const codeChallenge = createHash("sha256").update(codeVerifier).digest("base64url");
  const authUrl = new URL(`${baseUrl}/auth/realms/infernix/protocol/openid-connect/auth`);
  authUrl.searchParams.set("client_id", "infernix-spa");
  authUrl.searchParams.set("redirect_uri", `${baseUrl}/`);
  authUrl.searchParams.set("response_type", "code");
  authUrl.searchParams.set("scope", "openid");
  authUrl.searchParams.set("state", state);
  authUrl.searchParams.set("nonce", nonce);
  authUrl.searchParams.set("code_challenge", codeChallenge);
  authUrl.searchParams.set("code_challenge_method", "S256");

  await page.goto(authUrl.toString());
  const usernameField = page.locator("#username, input[name='username']").first();
  if (await usernameField.isVisible({ timeout: 5000 }).catch(() => false)) {
    throw new Error("expected the existing Keycloak SSO session to issue a fresh auth code");
  }
  const redirected = await waitForRegistrationRedirect(page, baseUrl);
  expect(redirected.searchParams.get("state")).toBe(state);
  return {
    code: redirected.searchParams.get("code"),
    codeVerifier,
    state,
  };
}

async function keycloakAdminAccessToken(request, baseUrl) {
  const tokenResponse = await request.post(`${baseUrl}/auth/realms/master/protocol/openid-connect/token`, {
    form: {
      grant_type: "password",
      client_id: "admin-cli",
      username: "admin",
      password: "infernix-bootstrap-admin",
    },
  });
  expect(tokenResponse.ok()).toBeTruthy();
  const payload = await tokenResponse.json();
  expect(payload.access_token).toBeTruthy();
  return payload.access_token;
}

async function keycloakAdminGetRealm(request, baseUrl, adminToken) {
  const realmResponse = await request.get(`${baseUrl}/auth/admin/realms/infernix`, {
    headers: { Authorization: `Bearer ${adminToken}` },
  });
  expect(realmResponse.ok()).toBeTruthy();
  return realmResponse.json();
}

async function keycloakAdminPutRealm(request, baseUrl, adminToken, patch) {
  const realmResponse = await request.put(`${baseUrl}/auth/admin/realms/infernix`, {
    headers: { Authorization: `Bearer ${adminToken}` },
    data: patch,
  });
  expect(realmResponse.ok()).toBeTruthy();
}

async function waitUntilJwtExpiresPastLeeway(claims) {
  const waitMs = Math.max(0, claims.exp * 1000 + 33000 - Date.now());
  expect(waitMs).toBeLessThanOrEqual(45000);
  if (waitMs > 0) {
    await new Promise((resolve) => setTimeout(resolve, waitMs));
  }
}

function decodeJwtPayload(token) {
  const [, payload] = token.split(".");
  expect(payload).toBeTruthy();
  return JSON.parse(Buffer.from(payload, "base64url").toString("utf8"));
}

function websocketUrl(baseUrl, token) {
  const url = new URL(baseUrl);
  url.protocol = url.protocol === "https:" ? "wss:" : "ws:";
  url.pathname = "/ws";
  url.search = "";
  url.searchParams.set("token", token);
  return url.toString();
}

async function probeWebSocket(page, url) {
  return page.evaluate(
    async (targetUrl) =>
      new Promise((resolve) => {
        const socket = new WebSocket(targetUrl);
        let opened = false;
        const timeout = setTimeout(() => {
          resolve({ opened: false, closeCode: null, reason: "timeout" });
          socket.close();
        }, 10000);

        socket.addEventListener("open", () => {
          opened = true;
          clearTimeout(timeout);
          socket.close(1000, "probe complete");
          resolve({ opened: true, closeCode: null, reason: "open" });
        });

        socket.addEventListener("close", (event) => {
          if (!opened) {
            clearTimeout(timeout);
            resolve({ opened: false, closeCode: event.code, reason: event.reason });
          }
        });

        socket.addEventListener("error", () => {
          if (!opened) {
            clearTimeout(timeout);
            resolve({ opened: false, closeCode: null, reason: "error" });
          }
        });
      }),
    url,
  );
}

async function probeWebSocketDecodeError(page, url) {
  return page.evaluate(
    async (targetUrl) =>
      new Promise((resolve) => {
        const socket = new WebSocket(targetUrl);
        const timeout = setTimeout(() => {
          resolve({ opened: false, message: null, reason: "timeout" });
          socket.close();
        }, 10000);

        socket.addEventListener("open", () => {
          socket.send("{not valid json");
        });

        socket.addEventListener("message", (event) => {
          clearTimeout(timeout);
          socket.close(1000, "decode probe complete");
          resolve({ opened: true, message: JSON.parse(event.data), reason: "message" });
        });

        socket.addEventListener("close", (event) => {
          clearTimeout(timeout);
          resolve({ opened: false, message: null, reason: `closed:${event.code}` });
        });

        socket.addEventListener("error", () => {
          clearTimeout(timeout);
          resolve({ opened: false, message: null, reason: "error" });
        });
      }),
    url,
  );
}

async function probeWebSocketMessage(page, url, message) {
  return page.evaluate(
    async ({ targetUrl, payload }) =>
      new Promise((resolve) => {
        const socket = new WebSocket(targetUrl);
        const timeout = setTimeout(() => {
          resolve({ opened: false, message: null, reason: "timeout" });
          socket.close();
        }, 10000);

        socket.addEventListener("open", () => {
          socket.send(JSON.stringify(payload));
        });

        socket.addEventListener("message", (event) => {
          clearTimeout(timeout);
          socket.close(1000, "message probe complete");
          resolve({ opened: true, message: JSON.parse(event.data), reason: "message" });
        });

        socket.addEventListener("close", (event) => {
          clearTimeout(timeout);
          resolve({ opened: false, message: null, reason: `closed:${event.code}` });
        });

        socket.addEventListener("error", () => {
          clearTimeout(timeout);
          resolve({ opened: false, message: null, reason: "error" });
        });
      }),
    { targetUrl: url, payload: message },
  );
}

async function fillIfPresent(page, selector, value) {
  const field = page.locator(selector);
  if ((await field.count()) > 0) {
    await field.first().fill(value);
  }
}

async function uploadArtifactThroughBrowser(page, artifact) {
  // Phase 7 Sprint 7.26 added a Files view that reuses the upload panel, so the
  // upload selectors are scoped to the Artifacts view to stay unambiguous.
  const artifactsRoot = page.locator("#artifacts-root");
  await artifactsRoot.locator("input[name='artifact-file']").setInputFiles({
    name: artifact.name,
    mimeType: artifact.mimeType,
    buffer: artifact.buffer,
  });
  await artifactsRoot.locator("input[name='artifact-mime']").fill(artifact.mimeType);
  await artifactsRoot.locator("input[name='artifact-display-name']").fill(artifact.name);
  await artifactsRoot.locator("form[data-role='artifact-upload']").evaluate((form) => form.requestSubmit());
  await expect(artifactsRoot.locator(`.artifact-entry[data-display-name="${artifact.name}"]`).first()).toBeVisible({ timeout: 60000 });
}

async function uploadAndDownloadArtifact(page, artifact, options = {}) {
  const uploadSentStart = options.frames ? options.frames.sent.length : 0;
  const uploadReceivedStart = options.frames ? options.frames.received.length : 0;
  await uploadArtifactThroughBrowser(page, artifact);
  if (options.frames && options.contextId) {
    await waitForArtifactUploadRecorded(
      options.frames,
      artifact,
      options.contextId,
      uploadSentStart,
      uploadReceivedStart,
    );
  }
  const card = await clickArtifactDownloadUntilReady(page, artifact);
  if (artifact.mimeType === "text/plain" || artifact.mimeType === "application/json") {
    await expect(card.locator(".artifact-preview-text")).toHaveAttribute("data-preview-status", "ready", {
      timeout: 60000,
    });
  }
  return card;
}

async function waitForArtifactUploadRecorded(frames, artifact, contextId, sentStartIndex, receivedStartIndex) {
  const uploadFrame = await waitForSentFrameAfter(
    frames,
    sentStartIndex,
    (frame) =>
      frame.tag === "ClientRecordUpload" &&
      frame.clientRecordUploadContextId === contextId &&
      frame.clientRecordUploadPayload?.uploadDisplayName === artifact.name &&
      frame.clientRecordUploadPayload?.uploadMimeType === artifact.mimeType,
    60000,
  );
  expect(uploadFrame.clientRecordUploadPayload.uploadObjectRef.objectKey).toContain(artifact.name);

  await waitForReceivedFrameAfter(
    frames,
    receivedStartIndex,
    (frame) =>
      frame.tag === "ServerConversationPatch" &&
      JSON.stringify(frame).includes("ConversationUserUploadEvent") &&
      JSON.stringify(frame).includes(contextId) &&
      JSON.stringify(frame).includes(artifact.name) &&
      JSON.stringify(frame).includes(artifact.mimeType),
    60000,
  );
}

async function clickArtifactDownloadUntilReady(page, artifact, timeoutMs = 60000) {
  const deadline = Date.now() + timeoutMs;
  let lastError = null;
  while (Date.now() < deadline) {
    const remainingMs = Math.max(1000, deadline - Date.now());
    const card = page.locator("#artifacts-root").locator(`.artifact-entry[data-display-name="${artifact.name}"]`).first();
    await expect(card).toBeVisible({ timeout: Math.min(5000, remainingMs) });
    const downloadButton = card.locator("[data-role='artifact-download']");
    await downloadButton.click();
    try {
      await expect(downloadButton).toHaveAttribute("data-download-status", "ready", {
        timeout: Math.min(10000, remainingMs),
      });
      await expect(downloadButton).toHaveAttribute("data-download-url", /\/api\/objects\/download\?key=/, {
        timeout: Math.min(5000, Math.max(1000, deadline - Date.now())),
      });
      return card;
    } catch (error) {
      lastError = error;
      await page.waitForTimeout(250);
    }
  }
  throw new Error(
    `Timed out waiting for artifact download grant for ${artifact.name}; last error: ${lastError?.message || "none"}`,
  );
}

async function selectFirstSupportedModel(page) {
  const modelSelect = page.locator("[data-role='model-picker']");
  await expect(modelSelect).toBeVisible();
  const options = await modelSelect.locator("option").evaluateAll((nodes) =>
    nodes.map((node) => ({
      value: node.value,
      label: node.textContent || "",
    })),
  );
  const selected =
    options.find((option) => option.value && !option.label.includes("Not recommended")) ||
    options.find((option) => option.value);
  expect(selected?.value).toBeTruthy();
  await modelSelect.selectOption(selected.value);
  await expect(modelSelect).toHaveValue(selected.value);
  return selected.value;
}

async function expectConversationUploadVisible(
  page,
  frames,
  artifact,
  contextId,
  sentStartIndex = 0,
  receivedStartIndex = 0,
) {
  const uploadFrame = await waitForSentFrameAfter(
    frames,
    sentStartIndex,
    (frame) =>
      frame.tag === "ClientRecordUpload" &&
      frame.clientRecordUploadContextId === contextId &&
      frame.clientRecordUploadPayload?.uploadDisplayName === artifact.name &&
      frame.clientRecordUploadPayload?.uploadMimeType === artifact.mimeType,
    60000,
  );
  expect(uploadFrame.clientRecordUploadPayload.uploadObjectRef.objectKey).toContain(artifact.name);

  const patchFrame = await waitForReceivedFrameAfter(
    frames,
    receivedStartIndex,
    (frame) =>
      frame.tag === "ServerConversationPatch" &&
      JSON.stringify(frame).includes("ConversationUserUploadEvent") &&
      JSON.stringify(frame).includes(contextId) &&
      JSON.stringify(frame).includes(artifact.name) &&
      JSON.stringify(frame).includes(artifact.mimeType),
    60000,
  );
  expect(JSON.stringify(patchFrame)).toContain("ConversationStateAppendMessage");

  const uploadMessage = page.locator(".chat-message.upload").filter({ hasText: artifact.name }).first();
  await expect(uploadMessage).toContainText(artifact.mimeType);
}

async function expectRoutedPreviewSource(card, selector) {
  const preview = card.locator(selector);
  await expect(preview).toHaveAttribute("data-preview-status", "ready");
  // Phase 7 Sprint 7.25: media src is the webapp proxy, never a presigned MinIO URL.
  await expect(preview).toHaveAttribute("src", /\/api\/objects\/download\?key=/);
}

async function expectDownloadOnlyReady(card) {
  await expect(card).toHaveAttribute("data-render-disposition", "DownloadOnly");
  await expect(card.locator(".artifact-preview-download-only")).toHaveAttribute("data-preview-status", "ready");
}

// Phase 7 Sprint 7.27: MIDI / MusicXML / ZIP flip from download-only to an
// in-browser render disposition. The download handler sets the card's
// disposition and emits the matching mount node; the dynamically-imported FFI
// renderer (validated by the bundle) populates it from the fetched bytes. This
// asserts the disposition flip + mount node (the contract change); rendering a
// real score from a valid fixture is the deeper cohort check.
async function expectInBrowserRenderReady(card, dispositionTag, previewSelector) {
  await expect(card).toHaveAttribute("data-render-disposition", dispositionTag);
  await expect(card.locator(previewSelector)).toHaveCount(1);
}

async function expectCapacityResultRendered(page, frames, contextId, modelId, expectedMemoryError, userPromptMessageId = null) {
  const expectedText = `Model ${expectedMemoryError.modelId} requires ${expectedMemoryError.requiredMib} MiB; this daemon has ${expectedMemoryError.availableMib} MiB available.`;
  const resultMessage = page.locator(".chat-message.result").filter({ hasText: expectedText }).last();
  try {
    await expect(
      resultMessage,
      `capacity result for ${modelId} in context ${contextId} should render`,
    ).toBeVisible({ timeout: 60000 });
  } catch (error) {
    let lastError = error;
    for (let attempt = 1; attempt <= 3; attempt += 1) {
      const receivedStart = frames.received.length;
      const socketId = await refreshBrowserSession(page, frames, contextId);
      try {
        await waitForCapacityResultFrameAfter(
          frames,
          receivedStart,
          { contextId, expectedMemoryError, userPromptMessageId, minimumSocketId: socketId },
          60000,
        );
        await expect(
          resultMessage,
          `capacity result for ${modelId} in context ${contextId} should render after result-bearing resubscription attempt ${attempt}`,
        ).toBeVisible({ timeout: 60000 });
        break;
      } catch (retryError) {
        lastError = retryError;
        if (attempt === 3) {
          throw new Error(
            `capacity result for ${modelId} in context ${contextId} did not render after result-bearing resubscription attempt ${attempt}: ${lastError.message}\n${await capacityRenderDiagnostics(
              page,
              frames,
              contextId,
              expectedMemoryError,
              userPromptMessageId,
            )}`,
          );
        }
      }
    }
  }
  await expect(resultMessage.locator(".chat-message-body")).toHaveText(expectedText, { timeout: 60000 });
  await expect(resultMessage.locator(".chat-result-artifact")).toHaveCount(0);
}

async function capacityRenderDiagnostics(page, frames, contextId, expectedMemoryError, userPromptMessageId = null) {
  const pageState = await page.evaluate((activeContextId) => {
    const activeContext = document.querySelector(".chat-context-item.active");
    const messages = Array.from(document.querySelectorAll(".chat-message")).map((node) => ({
      className: node.className,
      text: (node.textContent || "").replace(/\s+/g, " ").trim(),
    }));
    return {
      url: window.location.href,
      bodyClass: document.body?.className || "",
      activeContextId: activeContext?.getAttribute("data-context-id") || "",
      activeContextText: (activeContext?.textContent || "").replace(/\s+/g, " ").trim(),
      expectedContextVisible: Boolean(document.querySelector(`.chat-context-item[data-context-id="${activeContextId}"]`)),
      resultMessageCount: document.querySelectorAll(".chat-message.result").length,
      messages,
    };
  }, contextId);
  const matchingFrame = [...frames.received]
    .reverse()
    .find(
      (frame) =>
        conversationFrameTargetsContext(frame, contextId) &&
        conversationFrameInferenceResults(frame).some((result) =>
          capacityResultMatches(result, expectedMemoryError, userPromptMessageId),
        ),
    );
  const consoleWarnings = frames.console
    .filter((entry) => ["warning", "error"].includes(entry.type) || entry.text.includes("WS decode error"))
    .slice(-20);
  return JSON.stringify(
    {
      pageState,
      matchingFrame,
      consoleWarnings,
      pageErrors: frames.pageErrors.slice(-10),
    },
    null,
    2,
  );
}

async function waitForCapacityResultFrameAfter(frames, startIndex, details, timeoutMs = 60000) {
  const deadline = Date.now() + timeoutMs;
  let lastContextFrame = null;
  while (Date.now() < deadline) {
    const receivedFrames = frames.received.slice(startIndex);
    for (const frame of receivedFrames) {
      if (!conversationFrameTargetsContext(frame, details.contextId)) {
        continue;
      }
      if (
        typeof details.minimumSocketId === "number" &&
        typeof frame.__infernixSocketId === "number" &&
        frame.__infernixSocketId < details.minimumSocketId
      ) {
        continue;
      }
      lastContextFrame = frame;
      const results = conversationFrameInferenceResults(frame);
      if (results.some((result) => capacityResultMatches(result, details.expectedMemoryError, details.userPromptMessageId))) {
        return frame;
      }
    }
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error(
    `Timed out waiting for result-bearing conversation frame for ${details.expectedMemoryError.modelId} in ${details.contextId} after ${timeoutMs}ms; last context frame: ${JSON.stringify(lastContextFrame)}`,
  );
}

function conversationFrameTargetsContext(frame, contextId) {
  if (frame?.tag === "ServerConversationPatch") {
    return frame.serverConversationPatchContextId === contextId;
  }
  if (frame?.tag === "ServerConversationSnapshot") {
    return frame.serverConversationSnapshot?.conversationStateContextId === contextId;
  }
  return false;
}

function conversationFrameInferenceResults(frame) {
  if (frame?.tag === "ServerConversationPatch") {
    const result = conversationPatchInferenceResult(frame);
    return result ? [result] : [];
  }
  if (frame?.tag === "ServerConversationSnapshot") {
    const messages = frame.serverConversationSnapshot?.conversationStateMessages || [];
    return messages.map(conversationMessageInferenceResult).filter(Boolean);
  }
  return [];
}

function conversationMessageInferenceResult(message) {
  const event = message?.conversationMessageEvent;
  if (event?.tag !== "ConversationInferenceResultEvent") return null;
  return event.contents || null;
}

function capacityResultMatches(result, expectedMemoryError, userPromptMessageId = null) {
  if (!result || result.inferenceResultStatus !== "failed") return false;
  if (userPromptMessageId && result.inferenceResultUserPromptMessageId !== userPromptMessageId) return false;
  const error = result.inferenceResultError;
  return (
    error &&
    error.modelMemoryLimitExceededModelId === expectedMemoryError.modelId &&
    error.modelMemoryLimitExceededRequiredMib === expectedMemoryError.requiredMib &&
    error.modelMemoryLimitExceededAvailableMib === expectedMemoryError.availableMib &&
    error.modelMemoryLimitExceededResource === expectedMemoryError.resource &&
    error.modelMemoryLimitExceededSource === expectedMemoryError.source
  );
}
