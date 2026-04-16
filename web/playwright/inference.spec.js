import { test, expect } from "playwright/test";

test("manual inference workbench loads and submits a request", async ({ page }) => {
  await page.goto("/");
  await expect(page.getByRole("heading", { name: "Infernix" })).toBeVisible();

  await page.getByRole("textbox", { name: "Input Text" }).fill("hello infernix");
  await page.getByRole("button", { name: "Run Inference" }).click();

  await expect(page.locator("#request-status")).toContainText("Completed request");
  await expect(page.locator("#result-output")).toContainText("hello infernix");
});
