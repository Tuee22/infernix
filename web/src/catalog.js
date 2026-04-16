export function filterModels(models, query) {
  const normalized = query.trim().toLowerCase();
  if (!normalized) {
    return models;
  }
  return models.filter((model) =>
    [model.modelId, model.displayName, model.family].some((value) => value.toLowerCase().includes(normalized)),
  );
}
