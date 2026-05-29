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

  root.addEventListener("submit", (event) => {
    const form = event.target?.closest?.("form[data-role='chat-draft-editor']");
    if (form && root.contains(form)) {
      event.preventDefault();
      const draftInput = form.querySelector("textarea[name='prompt']");
      onSubmitPrompt(draftInput?.value || "")();
    }
  });
};
