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
  jsonPreviewBody,
  musicXmlBuffer,
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
  await expect(page.locator(".app-landing-actions button")).toHaveCount(2);
  await expect(page.locator("#login-button")).toHaveText("Sign in");
  await expect(page.locator("#register-button")).toHaveText("Create account");

  await page.locator("#login-button").click();
  await expect(page.locator("#username, input[name='username']").first()).toBeVisible({ timeout: 60000 });
  await expect(page.getByText("Sign in to Infernix")).toBeVisible();
  await expect(page.locator("#kc-registration a")).toBeVisible();
  await expect(page.locator("#kc-register-form, form[action*='registration']")).toHaveCount(0);

  await page.goto(baseUrl);
  await expect(page.locator("body")).toHaveClass("auth-signed-out");
  await page.locator("#register-button").click();
  await expect(page.locator("#kc-register-form, form[action*='registration'], form[action*='registrations']")).toBeVisible({ timeout: 60000 });
  await expect(page.getByText("Create your Infernix account")).toBeVisible();
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
  await expectOperatorRibbon(page);
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
  await completeLoginPromptIfPresent(page, credentials);
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
  test.setTimeout(120000);
  const fixture = infernixFixture;
  expect(fixture?.host).toBeTruthy();
  expect(fixture?.edgePort).toBeTruthy();
  const baseUrl = `http://${fixture.host}:${fixture.edgePort}`;
  const registration = await registerFreshKeycloakUser(page, baseUrl);
  const tokenPayload = await exchangeRegistrationCodeForToken(request, baseUrl, registration);
  const accessToken = tokenPayload.access_token;
  expect(accessToken).toBeTruthy();

  await expectJwtGatedOperatorRoute(request, `${baseUrl}/harbor`, accessToken);
  await expectJwtGatedOperatorRoute(request, `${baseUrl}/pulsar/admin/admin/v2/clusters`, accessToken);
  await expectJwtGatedOperatorRoute(request, `${baseUrl}/minio/s3`, accessToken);

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
  const expiredResult = await probeWebSocket(page, websocketUrl(baseUrl, expiredAccessToken));
  expect(expiredResult.opened).toBe(false);
});

test("routed object grants isolate users by Keycloak subject", async ({ page, browser, request, infernixFixture }) => {
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
  const displayName = `jwt-grant-${randomUUID()}.txt`;
  const grantRequest = {
    artifactUploadRequestContextId: contextId,
    artifactUploadRequestMimeType: "text/plain",
    artifactUploadRequestDisplayName: displayName,
  };

  const invalidGrant = await request.post(`${baseUrl}/api/objects/upload`, {
    headers: { Authorization: "Bearer not-a-real-token" },
    data: grantRequest,
  });
  expect(invalidGrant.status()).toBe(401);

  const wrongRealmToken = await keycloakAdminAccessToken(request, baseUrl);
  const wrongRealmGrant = await request.post(`${baseUrl}/api/objects/upload`, {
    headers: { Authorization: `Bearer ${wrongRealmToken}` },
    data: grantRequest,
  });
  expect(wrongRealmGrant.status()).toBe(401);

  const uploadGrantResponse = await request.post(`${baseUrl}/api/objects/upload`, {
    headers: { Authorization: `Bearer ${accessToken}` },
    data: grantRequest,
  });
  expect(uploadGrantResponse.ok()).toBeTruthy();
  const uploadGrant = await uploadGrantResponse.json();
  expect(uploadGrant.artifactUploadGrantObjectRef.objectBucket).toBe("infernix-demo-objects");
  expect(uploadGrant.artifactUploadGrantObjectRef.objectKey).toBe(`users/${claims.sub}/contexts/${contextId}/uploads/${displayName}`);
  expect(uploadGrant.artifactUploadGrantPresignedUrl).toContain("/minio/s3/infernix-demo-objects/");

  const objectBody = `hello from ${contextId}\n`;
  const putObjectResponse = await request.put(uploadGrant.artifactUploadGrantPresignedUrl, {
    headers: {
      "Content-Type": "text/plain",
      Cookie: operatorTokenCookieHeader(accessToken),
    },
    data: objectBody,
  });
  expect(putObjectResponse.ok()).toBeTruthy();

  const downloadGrantResponse = await request.post(`${baseUrl}/api/objects/download`, {
    headers: { Authorization: `Bearer ${accessToken}` },
    data: grantRequest,
  });
  expect(downloadGrantResponse.ok()).toBeTruthy();
  const downloadGrant = await downloadGrantResponse.json();
  expect(downloadGrant.artifactDownloadGrantObjectRef).toEqual(uploadGrant.artifactUploadGrantObjectRef);
  expect(downloadGrant.artifactDownloadGrantMimeType).toBe("text/plain");
  expect(renderDispositionTag(downloadGrant)).toBe("BoundedTextPreview");
  expect(downloadGrant.artifactDownloadGrantPresignedUrl).toContain("/minio/s3/infernix-demo-objects/");

  const getObjectResponse = await request.get(downloadGrant.artifactDownloadGrantPresignedUrl, {
    headers: { Cookie: operatorTokenCookieHeader(accessToken) },
  });
  expect(getObjectResponse.ok()).toBeTruthy();
  expect(await getObjectResponse.text()).toBe(objectBody);

  const dispositionCases = [
    { mimeType: "image/png", displayName: "inline-image.png", disposition: "RenderInline" },
    { mimeType: "audio/wav", displayName: "inline-audio.wav", disposition: "RenderInline" },
    { mimeType: "video/mp4", displayName: "inline-video.mp4", disposition: "RenderInline" },
    { mimeType: "application/pdf", displayName: "document.pdf", disposition: "BrowserNativePdf" },
    { mimeType: "application/json", displayName: "preview.json", disposition: "BoundedTextPreview" },
    { mimeType: "audio/midi", displayName: "score.mid", disposition: "DownloadOnly" },
    { mimeType: "application/vnd.recordare.musicxml+xml", displayName: "score.musicxml", disposition: "DownloadOnly" },
    { mimeType: "application/octet-stream", displayName: "artifact.bin", disposition: "DownloadOnly" },
  ];

  for (const artifactCase of dispositionCases) {
    const caseRequest = {
      artifactUploadRequestContextId: contextId,
      artifactUploadRequestMimeType: artifactCase.mimeType,
      artifactUploadRequestDisplayName: artifactCase.displayName,
    };
    const caseGrantResponse = await request.post(`${baseUrl}/api/objects/download`, {
      headers: { Authorization: `Bearer ${accessToken}` },
      data: caseRequest,
    });
    expect(caseGrantResponse.ok()).toBeTruthy();
    const caseGrant = await caseGrantResponse.json();
    expect(caseGrant.artifactDownloadGrantMimeType).toBe(artifactCase.mimeType);
    expect(renderDispositionTag(caseGrant)).toBe(artifactCase.disposition);
    expect(caseGrant.artifactDownloadGrantObjectRef.objectKey).toBe(
      `users/${claims.sub}/contexts/${contextId}/uploads/${artifactCase.displayName}`,
    );
  }

  const secondContext = await browser.newContext();
  const secondPage = await secondContext.newPage();
  try {
    const secondRegistration = await registerFreshKeycloakUser(secondPage, baseUrl);
    const secondTokenPayload = await exchangeRegistrationCodeForToken(request, baseUrl, secondRegistration);
    const secondAccessToken = secondTokenPayload.access_token;
    expect(secondAccessToken).toBeTruthy();
    const secondClaims = decodeJwtPayload(secondAccessToken);
    expect(secondClaims.sub).toBeTruthy();
    expect(secondClaims.sub).not.toBe(claims.sub);

    const secondDownloadGrantResponse = await request.post(`${baseUrl}/api/objects/download`, {
      headers: { Authorization: `Bearer ${secondAccessToken}` },
      data: grantRequest,
    });
    expect(secondDownloadGrantResponse.ok()).toBeTruthy();
    const secondDownloadGrant = await secondDownloadGrantResponse.json();
    expect(secondDownloadGrant.artifactDownloadGrantObjectRef.objectKey).toBe(`users/${secondClaims.sub}/contexts/${contextId}/uploads/${displayName}`);
    expect(secondDownloadGrant.artifactDownloadGrantObjectRef.objectKey).not.toBe(uploadGrant.artifactUploadGrantObjectRef.objectKey);

    const secondMissingObjectResponse = await request.get(secondDownloadGrant.artifactDownloadGrantPresignedUrl, {
      headers: { Cookie: operatorTokenCookieHeader(secondAccessToken) },
    });
    expect(secondMissingObjectResponse.status()).toBe(404);

    const secondUploadGrantResponse = await request.post(`${baseUrl}/api/objects/upload`, {
      headers: { Authorization: `Bearer ${secondAccessToken}` },
      data: grantRequest,
    });
    expect(secondUploadGrantResponse.ok()).toBeTruthy();
    const secondUploadGrant = await secondUploadGrantResponse.json();
    expect(secondUploadGrant.artifactUploadGrantObjectRef).toEqual(secondDownloadGrant.artifactDownloadGrantObjectRef);

    const secondObjectBody = `hello from ${contextId} as ${secondClaims.sub}\n`;
    const secondPutObjectResponse = await request.put(secondUploadGrant.artifactUploadGrantPresignedUrl, {
      headers: {
        "Content-Type": "text/plain",
        Cookie: operatorTokenCookieHeader(secondAccessToken),
      },
      data: secondObjectBody,
    });
    expect(secondPutObjectResponse.ok()).toBeTruthy();

    const secondReadableObjectResponse = await request.get(secondDownloadGrant.artifactDownloadGrantPresignedUrl, {
      headers: { Cookie: operatorTokenCookieHeader(secondAccessToken) },
    });
    expect(secondReadableObjectResponse.ok()).toBeTruthy();
    expect(await secondReadableObjectResponse.text()).toBe(secondObjectBody);

    const firstObjectStillReadableResponse = await request.get(downloadGrant.artifactDownloadGrantPresignedUrl, {
      headers: { Cookie: operatorTokenCookieHeader(accessToken) },
    });
    expect(firstObjectStillReadableResponse.ok()).toBeTruthy();
    expect(await firstObjectStillReadableResponse.text()).toBe(objectBody);
  } finally {
    await secondContext.close();
  }
});

test("self-service account deletion reaps demo state before Keycloak account action", async ({ page, request, infernixFixture }) => {
  test.setTimeout(180000);
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
  const grantRequest = {
    artifactUploadRequestContextId: contextId,
    artifactUploadRequestMimeType: "text/plain",
    artifactUploadRequestDisplayName: displayName,
  };
  const uploadGrantResponse = await request.post(`${baseUrl}/api/objects/upload`, {
    headers: { Authorization: `Bearer ${accessToken}` },
    data: grantRequest,
  });
  expect(uploadGrantResponse.ok()).toBeTruthy();
  const uploadGrant = await uploadGrantResponse.json();
  const objectBody = `delete me ${randomUUID()}\n`;
  const putObjectResponse = await request.put(uploadGrant.artifactUploadGrantPresignedUrl, {
    headers: {
      "Content-Type": "text/plain",
      Cookie: operatorTokenCookieHeader(accessToken),
    },
    data: objectBody,
  });
  expect(putObjectResponse.ok()).toBeTruthy();
  const downloadGrantResponse = await request.post(`${baseUrl}/api/objects/download`, {
    headers: { Authorization: `Bearer ${accessToken}` },
    data: grantRequest,
  });
  expect(downloadGrantResponse.ok()).toBeTruthy();
  const downloadGrant = await downloadGrantResponse.json();
  const readableBeforeDelete = await request.get(downloadGrant.artifactDownloadGrantPresignedUrl, {
    headers: { Cookie: operatorTokenCookieHeader(accessToken) },
  });
  expect(readableBeforeDelete.ok()).toBeTruthy();
  expect(await readableBeforeDelete.text()).toBe(objectBody);

  await expect
    .poll(async () => {
      const topics = await listDemoTopics(request, baseUrl, accessToken);
      return topics.filter((topic) => topic.includes(claims.sub)).length;
    }, { timeout: 60000 })
    .toBeGreaterThan(0);

  const deleteResponsePromise = page.waitForResponse(
    (response) => response.url() === `${baseUrl}/api/account` && response.request().method() === "DELETE",
  );
  const deleteActionRequestPromise = page.waitForRequest(
    (requestValue) =>
      requestValue.url().includes("/protocol/openid-connect/auth") &&
      requestValue.url().includes("kc_action=delete_account"),
  );
  await page.locator("#delete-account-button").click();
  const deleteResponse = await deleteResponsePromise;
  expect(deleteResponse.ok()).toBeTruthy();
  const deleteActionRequest = await deleteActionRequestPromise;
  expect(new URL(deleteActionRequest.url()).searchParams.get("kc_action")).toBe("delete_account");

  const missingAfterDelete = await request.get(downloadGrant.artifactDownloadGrantPresignedUrl, {
    headers: { Cookie: operatorTokenCookieHeader(accessToken) },
  });
  expect(missingAfterDelete.status()).toBe(404);

  await expect
    .poll(async () => {
      const topics = await listDemoTopics(request, baseUrl, accessToken);
      return topics.filter((topic) => topic.includes(claims.sub)).length;
    }, { timeout: 60000 })
    .toBe(0);
});

test("browser artifact upload covers preview media PDF and download-only grants", async ({ page, infernixFixture }) => {
  test.setTimeout(300000);
  const fixture = infernixFixture;
  expect(fixture?.host).toBeTruthy();
  expect(fixture?.edgePort).toBeTruthy();
  const baseUrl = `http://${fixture.host}:${fixture.edgePort}`;
  const wsFrames = collectWebSocketFrames(page);

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

  const textName = `browser-upload-${randomUUID()}.txt`;
  const textCard = await uploadAndDownloadArtifact(page, {
    name: textName,
    mimeType: "text/plain",
    buffer: Buffer.from(textPreviewBody, "utf8"),
  });
  await expect(textCard.locator(".artifact-preview-text")).toHaveText(textPreviewBody);

  const jsonName = `browser-json-${randomUUID()}.json`;
  const jsonCard = await uploadAndDownloadArtifact(page, {
    name: jsonName,
    mimeType: "application/json",
    buffer: Buffer.from(jsonPreviewBody, "utf8"),
  });
  await expect(jsonCard.locator(".artifact-preview-text")).toHaveText(jsonPreviewBody);

  const pngName = `browser-inline-${randomUUID()}.png`;
  const imageCard = await uploadAndDownloadArtifact(page, {
    name: pngName,
    mimeType: "image/png",
    buffer: tinyPngBuffer(),
  });
  await expectRoutedPreviewSource(imageCard, ".artifact-preview-image");

  const audioName = `browser-audio-${randomUUID()}.wav`;
  const audioCard = await uploadAndDownloadArtifact(page, {
    name: audioName,
    mimeType: "audio/wav",
    buffer: tinyWavBuffer(),
  });
  await expectRoutedPreviewSource(audioCard, ".artifact-preview-audio");

  const videoName = `browser-video-${randomUUID()}.mp4`;
  const videoCard = await uploadAndDownloadArtifact(page, {
    name: videoName,
    mimeType: "video/mp4",
    buffer: tinyMp4Buffer(),
  });
  await expectRoutedPreviewSource(videoCard, ".artifact-preview-video");

  const pdfName = `browser-pdf-${randomUUID()}.pdf`;
  const pdfCard = await uploadAndDownloadArtifact(page, {
    name: pdfName,
    mimeType: "application/pdf",
    buffer: tinyPdfBuffer(),
  });
  await expect(pdfCard).toHaveAttribute("data-render-disposition", "BrowserNativePdf");
  await expectRoutedPreviewSource(pdfCard, ".artifact-preview-pdf");

  const midiName = `browser-midi-${randomUUID()}.mid`;
  const midiCard = await uploadAndDownloadArtifact(page, {
    name: midiName,
    mimeType: "audio/midi",
    buffer: tinyMidiBuffer(),
  });
  await expectDownloadOnlyReady(midiCard);

  const musicXmlName = `browser-musicxml-${randomUUID()}.musicxml`;
  const musicXmlCard = await uploadAndDownloadArtifact(page, {
    name: musicXmlName,
    mimeType: "application/vnd.recordare.musicxml+xml",
    buffer: musicXmlBuffer(),
  });
  await expectDownloadOnlyReady(musicXmlCard);

  const binaryName = `browser-binary-${randomUUID()}.bin`;
  const binaryCard = await uploadAndDownloadArtifact(page, {
    name: binaryName,
    mimeType: "application/octet-stream",
    buffer: binaryArtifactBuffer(),
  });
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
  await waitForSentFrameAfter(wsFrames, draftReconnectSentStartIndex, (frame) => frame.tag === "ClientHello");
  await waitForSentFrameAfter(
    wsFrames,
    draftReconnectSentStartIndex,
    (frame) => frame.tag === "ClientSubscribeContext" && frame.clientSubscribeContextId === subscribeFrame.clientSubscribeContextId,
  );
  await waitForReceivedFrameAfter(
    wsFrames,
    draftReconnectReceivedStartIndex,
    (frame) => frame.tag === "ServerDraftMapPatch" && JSON.stringify(frame).includes(promptText),
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
  await waitForSentFrameAfter(wsFrames, reconnectSentStartIndex, (frame) => frame.tag === "ClientHello");
  const reconnectSubscribeFrame = await waitForSentFrameAfter(
    wsFrames,
    reconnectSentStartIndex,
    (frame) => frame.tag === "ClientSubscribeContext" && frame.clientSubscribeContextId === subscribeFrame.clientSubscribeContextId,
  );
  expect(reconnectSubscribeFrame.clientSubscribeContextId).toBe(subscribeFrame.clientSubscribeContextId);
  await waitForReceivedFrameAfter(
    wsFrames,
    reconnectReceivedStartIndex,
    (frame) => frame.tag === "ServerConversationSnapshot" && JSON.stringify(frame).includes(subscribeFrame.clientSubscribeContextId),
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
  test.setTimeout(900000);
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
    const contextId = contextByModel.get(modelId);
    expect(contextId).toBeTruthy();
    const submitSentStart = wsFrames.sent.length;
    const submitReceivedStart = wsFrames.received.length;

    await page
      .locator(`.chat-context-item[data-context-id="${contextId}"] [data-role='select-context']`)
      .click();
    await expect(
      page.locator(`.chat-context-item.active[data-context-id="${contextId}"]`),
    ).toBeVisible();

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

    await waitForSentFrameAfter(
      wsFrames,
      submitSentStart,
      (frame) => frame.tag === "ClientSubmitPrompt" && frame.clientSubmitPromptPayload?.promptText === promptText,
    );

    const completedFrame = await waitForCompletedConversationPatchAfter(
      wsFrames,
      submitReceivedStart,
      {
        contextId,
        modelId,
        promptText,
      },
    );
    expect(JSON.stringify(completedFrame)).toContain("ConversationStateAppendMessage");
  }
});

function renderDispositionTag(downloadGrant) {
  const disposition = downloadGrant.artifactDownloadGrantRenderDisposition;
  return typeof disposition === "string" ? disposition : disposition?.tag;
}

function conversationPatchMessageId(frame) {
  return frame?.serverConversationPatch?.appendMessage?.conversationMessageId || "";
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

function collectWebSocketFrames(page) {
  const frames = { sent: [], received: [] };
  page.on("websocket", (socket) => {
    socket.on("framesent", (frame) => {
      try {
        frames.sent.push(JSON.parse(String(frame.payload)));
      } catch {
        // The test only inspects Infernix JSON envelopes.
      }
    });
    socket.on("framereceived", (frame) => {
      try {
        frames.received.push(JSON.parse(String(frame.payload)));
      } catch {
        // The test only inspects Infernix JSON envelopes.
      }
    });
  });
  return frames;
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

async function waitForCompletedConversationPatchAfter(frames, startIndex, details) {
  const timeoutMs = 300000;
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
      lastContextPatch = frame;
      if (encoded.includes("\"inferenceResultStatus\":\"failed\"")) {
        throw new Error(
          `Model ${details.modelId} returned a failed inference result for prompt ${details.promptText}: ${encoded}`,
        );
      }
      if (encoded.includes("\"inferenceResultStatus\":\"completed\"")) {
        return frame;
      }
    }
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error(
    `Timed out waiting for completed conversation result for model ${details.modelId} after ${timeoutMs}ms; received ${frames.received.length - startIndex} inbound frames after index ${startIndex}; last context patch: ${JSON.stringify(lastContextPatch)}`,
  );
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
    await usernameField.fill(credentials.username);
    await page.locator("#password, input[name='password']").first().fill(credentials.password);
    await page.locator("#kc-login, #kc-form-buttons input[type='submit'], button[type='submit'], input[type='submit']").first().click();
  }
}

async function expectOperatorRibbon(page) {
  const ribbon = page.locator(".operator-ribbon");
  await expect(ribbon).toBeVisible();
  await expect(ribbon.locator("[data-operator-route='/harbor']")).toHaveAttribute("href", "/harbor");
  await expect(ribbon.locator("[data-operator-route='/pulsar/admin']")).toHaveAttribute("href", "/pulsar/admin/admin/v2/clusters");
  await expect(ribbon.locator("[data-operator-route='/minio/s3']")).toHaveAttribute("href", "/minio/s3");
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

async function expectJwtGatedOperatorRoute(request, url, accessToken) {
  const unauthenticated = await request.get(url);
  expect(unauthenticated.status()).toBe(401);

  const authenticated = await request.get(url, {
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  expect(authenticated.status()).not.toBe(401);
}

async function listDemoTopics(request, baseUrl, accessToken) {
  const response = await request.get(`${baseUrl}/pulsar/admin/admin/v2/persistent/infernix/demo`, {
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  expect(response.ok()).toBeTruthy();
  return response.json();
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
  await page.locator("input[name='artifact-file']").setInputFiles({
    name: artifact.name,
    mimeType: artifact.mimeType,
    buffer: artifact.buffer,
  });
  await page.locator("input[name='artifact-mime']").fill(artifact.mimeType);
  await page.locator("input[name='artifact-display-name']").fill(artifact.name);
  await page.locator("form[data-role='artifact-upload']").evaluate((form) => form.requestSubmit());
  await expect(page.locator(`.artifact-entry[data-display-name="${artifact.name}"]`).first()).toBeVisible({ timeout: 60000 });
}

async function uploadAndDownloadArtifact(page, artifact) {
  await uploadArtifactThroughBrowser(page, artifact);
  const card = page.locator(`.artifact-entry[data-display-name="${artifact.name}"]`).first();
  await expect(card).toBeVisible();
  const downloadButton = card.locator("[data-role='artifact-download']");
  await downloadButton.click();
  await expect(downloadButton).toHaveAttribute("data-download-status", "ready");
  await expect(downloadButton).toHaveAttribute("data-presigned-url", /\/minio\/s3\/infernix-demo-objects\//);
  return card;
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

async function expectConversationUploadVisible(page, frames, artifact, contextId) {
  const uploadFrame = await waitForSentFrame(
    frames,
    (frame) =>
      frame.tag === "ClientRecordUpload" &&
      frame.clientRecordUploadContextId === contextId &&
      frame.clientRecordUploadPayload?.uploadDisplayName === artifact.name &&
      frame.clientRecordUploadPayload?.uploadMimeType === artifact.mimeType,
  );
  expect(uploadFrame.clientRecordUploadPayload.uploadObjectRef.objectKey).toContain(artifact.name);

  const patchFrame = await waitForReceivedFrame(
    frames,
    (frame) =>
      frame.tag === "ServerConversationPatch" &&
      JSON.stringify(frame).includes("ConversationUserUploadEvent") &&
      JSON.stringify(frame).includes(contextId) &&
      JSON.stringify(frame).includes(artifact.name) &&
      JSON.stringify(frame).includes(artifact.mimeType),
  );
  expect(JSON.stringify(patchFrame)).toContain("ConversationStateAppendMessage");

  const uploadMessage = page.locator(".chat-message.upload").filter({ hasText: artifact.name }).first();
  await expect(uploadMessage).toContainText(artifact.mimeType);
}

async function expectRoutedPreviewSource(card, selector) {
  const preview = card.locator(selector);
  await expect(preview).toHaveAttribute("data-preview-status", "ready");
  await expect(preview).toHaveAttribute("src", /\/minio\/s3\/infernix-demo-objects\//);
}

async function expectDownloadOnlyReady(card) {
  await expect(card).toHaveAttribute("data-render-disposition", "DownloadOnly");
  await expect(card.locator(".artifact-preview-download-only")).toHaveAttribute("data-preview-status", "ready");
}
