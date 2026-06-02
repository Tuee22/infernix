export const bindChatChromeImpl =
  (root) =>
  (onOpenNewContext) =>
  (onCreateContext) =>
  (onCloseNewContext) =>
  (onRenameContext) =>
  (onSoftDeleteContext) =>
  (onSelectContext) =>
  (onSelectModel) =>
  (onSubmitPrompt) =>
  (onCancelPrompt) =>
  (onDraftChanged) =>
  () => {
  if (root.__infernixChatChromeBound) {
    return;
  }
  root.__infernixChatChromeBound = true;

  root.addEventListener("click", (event) => {
    const openNewContextButton = event.target?.closest?.("[data-role='open-new-context']");
    if (openNewContextButton && root.contains(openNewContextButton)) {
      event.preventDefault();
      onOpenNewContext();
      return;
    }

    const createButton = event.target?.closest?.("[data-role='create-context']");
    if (createButton && root.contains(createButton)) {
      event.preventDefault();
      onCreateContext();
      return;
    }

    const closeNewContextButton = event.target?.closest?.("[data-role='close-new-context']");
    if (closeNewContextButton && root.contains(closeNewContextButton)) {
      event.preventDefault();
      onCloseNewContext();
      return;
    }

    const renameContextButton = event.target?.closest?.("[data-role='rename-context']");
    if (renameContextButton && root.contains(renameContextButton)) {
      event.preventDefault();
      const contextItem = renameContextButton.closest(".chat-context-item[data-context-id]");
      const titleInput = contextItem?.querySelector?.("[data-role='context-rename-title']");
      onRenameContext(contextItem?.dataset.contextId || "")(titleInput?.value || "")();
      return;
    }

    const softDeleteContextButton = event.target?.closest?.("[data-role='soft-delete-context']");
    if (softDeleteContextButton && root.contains(softDeleteContextButton)) {
      event.preventDefault();
      const contextItem = softDeleteContextButton.closest(".chat-context-item[data-context-id]");
      onSoftDeleteContext(contextItem?.dataset.contextId || "")();
      return;
    }

    const contextButton = event.target?.closest?.("[data-role='select-context'][data-context-id]");
    if (contextButton && root.contains(contextButton)) {
      event.preventDefault();
      onSelectContext(contextButton.dataset.contextId || "")(contextButton.dataset.modelId || "")();
      return;
    }

    const cancelButton = event.target?.closest?.("[data-role='cancel-latest-prompt']");
    if (cancelButton && root.contains(cancelButton)) {
      event.preventDefault();
      onCancelPrompt();
    }
  });

  root.addEventListener("change", (event) => {
    const select = event.target?.closest?.("[data-role='model-picker']");
    if (select && root.contains(select)) {
      onSelectModel(select.value || "")();
    }
  });

  root.addEventListener("input", (event) => {
    const draftInput = event.target?.closest?.("form[data-role='chat-draft-editor'] textarea[name='prompt']");
    if (draftInput && root.contains(draftInput)) {
      onDraftChanged(draftInput.value || "")();
    }
  });

  // Phase 7 Sprint 7.15 (2026-05-31): the chat draft form binds its
  // own `submit` listener at construction time instead of relying on
  // delegation from `root`. `renderChatSection` rebuilds the form on
  // every server patch; if the SPA receives a `ServerDraftMapPatch`
  // (e.g., after a WebSocket reconnect restores the draft) between
  // Playwright's `page.locator(...)` resolution and the
  // `form.requestSubmit()` call, the resolved form can be detached by
  // the time the submit event fires. Detached submits do not bubble to
  // ancestors, so a `root.addEventListener("submit", ...)` delegate
  // never fires. Binding directly on the form keeps the handler alive
  // on the form's own DOM listener list regardless of attachment, and
  // `attachDraftFormSubmitHandler` is idempotent so re-render does not
  // double-bind.
  const attachDraftFormSubmitHandler = (form) => {
    if (form.__infernixDraftSubmitBound) {
      return;
    }
    form.__infernixDraftSubmitBound = true;
    form.addEventListener("submit", (event) => {
      event.preventDefault();
      const draftInput = form.querySelector("textarea[name='prompt']");
      onSubmitPrompt(draftInput?.value || "")();
    });
  };

  root
    .querySelectorAll("form[data-role='chat-draft-editor']")
    .forEach(attachDraftFormSubmitHandler);

  const draftFormObserver = new MutationObserver((mutations) => {
    for (const mutation of mutations) {
      for (const node of mutation.addedNodes) {
        if (node.nodeType !== 1) {
          continue;
        }
        if (node.matches?.("form[data-role='chat-draft-editor']")) {
          attachDraftFormSubmitHandler(node);
        }
        node
          .querySelectorAll?.("form[data-role='chat-draft-editor']")
          .forEach(attachDraftFormSubmitHandler);
      }
    }
  });
  draftFormObserver.observe(root, { childList: true, subtree: true });
};
