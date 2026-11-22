import { readFile } from "node:fs/promises";
import { test, expect } from "playwright/test";

test("retains a file selected as its upload form is replaced", async ({ page }) => {
  const source = await readFile(new URL("../src/Infernix/Web/ArtifactTransport.js", import.meta.url), "utf8");
  const result = await page.evaluate(async (moduleSource) => {
    const moduleUrl = URL.createObjectURL(new Blob([moduleSource], { type: "text/javascript" }));
    const transport = await import(moduleUrl);
    window.__infernixAccessToken = "test-token";
    const uploads = [];
    const errors = [];
    let finishUpload;
    const uploadFinished = new Promise(resolve => { finishUpload = resolve; });
    window.fetch = async (url, options) => {
      uploads.push({ url, body: await options.body.text() });
      return {
        ok: true,
        json: async () => ({ artifactUploadGrantObjectRef: { objectBucket: "bucket", objectKey: "object" } }),
      };
    };
    const root = document.createElement("div");
    document.body.append(root);
    transport.bindArtifactTransportImpl(root)(() => () => finishUpload())(message => () => {
      errors.push(message);
      finishUpload();
    })();
    const renderForm = () => {
      const form = document.createElement("form");
      form.dataset.role = "artifact-upload";
      form.dataset.contextId = "context";
      form.innerHTML = '<input type="file" name="artifact-file"><input name="artifact-display-name"><button type="submit">Upload</button>';
      root.append(form);
      transport.refreshUploadDraftBindings(root)();
      transport.refreshUploadDraftBindings(root)();
      return form;
    };
    const original = renderForm();
    const input = original.querySelector("input[type='file']");
    const files = new DataTransfer();
    files.items.add(new File(["audio bytes"], "sample.wav", { type: "audio/wav" }));
    input.files = files.files;
    original.remove();
    input.dispatchEvent(new Event("change", { bubbles: true }));
    const replacement = renderForm();
    replacement.querySelector("input[name='artifact-display-name']").value = "sample.wav";
    replacement.requestSubmit();
    await uploadFinished;
    return { uploads, errors };
  }, source);
  expect(result.errors).toEqual([]);
  expect(result.uploads).toHaveLength(1);
  expect(result.uploads[0].body).toBe("audio bytes");
  expect(result.uploads[0].url).toContain("contextId=context");
});
