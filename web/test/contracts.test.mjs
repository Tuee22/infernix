import assert from "node:assert/strict";
import { apiBasePath, maxInlineOutputLength, models } from "../dist/generated/contracts.js";
import { filterModels } from "../dist/catalog.js";

assert.equal(apiBasePath, "/api");
assert.equal(maxInlineOutputLength, 80);
assert.equal(models.length, 3);
assert.equal(filterModels(models, "upper")[0].modelId, "uppercase-text");

console.log("web unit tests passed");
