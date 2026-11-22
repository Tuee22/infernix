import { readFile } from "node:fs/promises";
import { test, expect } from "playwright/test";

test("a replaced form submits the typed draft only for the same context", async ({ page }) => {
  const source = await readFile(new URL("../src/Infernix/Web/DomEvents.js", import.meta.url), "utf8");
  const submitted = await page.evaluate(async (moduleSource) => {
    const moduleUrl = URL.createObjectURL(new Blob([moduleSource], { type: "text/javascript" }));
    const { bindChatChromeImpl } = await import(moduleUrl);
    const root = document.createElement("div");
    document.body.append(root);
    const results = [];
    const noEffect = () => {};
    const noopHandler = () => noEffect;
    bindChatChromeImpl(root)(noEffect)(noEffect)(noEffect)(noEffect)(noEffect)(noopHandler)(noopHandler)
      (text => () => results.push(text))(noEffect)(noopHandler)();
    const render = (contextId, text) => {
      const form = document.createElement("form");
      form.dataset.role = "chat-draft-editor";
      form.dataset.contextId = contextId;
      const textarea = document.createElement("textarea");
      textarea.name = "prompt";
      textarea.value = text;
      form.append(textarea);
      root.replaceChildren(form);
      return form;
    };
    const original = render("first", "typed draft");
    await Promise.resolve();
    const current = render("first", "");
    original.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }));
    await Promise.resolve();
    render("second", "another context");
    current.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }));
    URL.revokeObjectURL(moduleUrl);
    return results;
  }, source);
  expect(submitted).toEqual(["typed draft"]);
});

test("a stale redraw preserves the locally edited draft until submission", async ({ page }) => {
  const source = await readFile(new URL("../src/Infernix/Web/DomEvents.js", import.meta.url), "utf8");
  const result = await page.evaluate(async (moduleSource) => {
    const moduleUrl = URL.createObjectURL(new Blob([moduleSource], { type: "text/javascript" }));
    const { bindChatChromeImpl } = await import(moduleUrl);
    const root = document.createElement("div");
    document.body.append(root);
    const submitted = [];
    const noEffect = () => {};
    const noopHandler = () => noEffect;
    bindChatChromeImpl(root)(noEffect)(noEffect)(noEffect)(noEffect)(noEffect)(noopHandler)(noopHandler)
      (text => () => submitted.push(text))(noEffect)(noopHandler)();
    const render = (contextId, text) => {
      const form = document.createElement("form");
      form.dataset.role = "chat-draft-editor";
      form.dataset.contextId = contextId;
      const input = document.createElement("textarea");
      input.name = "prompt";
      input.value = text;
      form.append(input);
      root.replaceChildren(form);
      return form;
    };
    const first = render("first", "");
    await Promise.resolve();
    first.querySelector("textarea").value = "continue after reconnect";
    first.querySelector("textarea").dispatchEvent(new Event("input", { bubbles: true }));
    const replacement = render("first", "stale snapshot");
    await Promise.resolve();
    const visible = replacement.querySelector("textarea").value;
    replacement.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }));
    const afterSubmit = render("first", "server draft");
    await Promise.resolve();
    URL.revokeObjectURL(moduleUrl);
    return { visible, submitted, afterSubmit: afterSubmit.querySelector("textarea").value };
  }, source);
  expect(result).toEqual({
    visible: "continue after reconnect",
    submitted: ["continue after reconnect"],
    afterSubmit: "server draft",
  });
});
