import { test, expect } from "@playwright/test";
import { resolveExamplesPort, startExamplesServer, waitForServerReady, stopServer } from "./examples-server";

const examplesPort = resolveExamplesPort(5196);
const renderTimeoutMs = 15_000;

test.describe("Examples XForms render smoke", () => {
  test.describe.configure({ mode: "serial" });
  let examplesServer;

  test.beforeAll(async () => {
    examplesServer = startExamplesServer(examplesPort);
    // Run unified examples Node server in-test so pages can fetch SaxonJS3 + SEF assets and render controls
    await waitForServerReady(examplesServer);
  });

  test.afterAll(async () => {
    await stopServer(examplesServer);
  });

  test("examples fundamentals page renders XForms controls", async ({ page }) => {
    await page.goto(`${examplesServer.baseUrl}/demo-repeat.html`);
    // Assert rendered repeat controls exist after runtime transform
    await expect(page.locator("#xForm .xforms-repeat").first()).toBeVisible({ timeout: renderTimeoutMs });
  });

  test("examples booking page renders XForms controls", async ({ page }) => {
    await page.goto(`${examplesServer.baseUrl}/sample1.html`);
    // Assert rendered booking form controls exist after runtime transform
    await expect(page.locator("#xForm .xforms-input").first()).toBeVisible({ timeout: renderTimeoutMs });
  });
});
