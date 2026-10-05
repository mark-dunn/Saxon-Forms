import { test, expect } from "@playwright/test";
import { resolveExamplesPort, startExamplesServer, stopServer, waitForServerReady, type RunningServer } from "./examples-server";

const renderTimeoutMs = 15_000;
const examplesPort = resolveExamplesPort(5202);

test.describe("Examples demo-submission", () => {
  test.describe.configure({ mode: "serial" });
  let examplesServer: RunningServer;

  test.beforeAll(async () => {
    examplesServer = startExamplesServer(examplesPort);
    await waitForServerReady(examplesServer);
  });

  test.afterAll(async () => {
    await stopServer(examplesServer);
  });

  test("updates status node for submit success and failure paths", async ({ page }) => {
    const requests: string[] = [];
    page.on("request", (request) => {
      if (request.url().includes("/api/submit-ok") || request.url().includes("/api/submit-fail")) {
        requests.push(request.url());
      }
    });

    await page.goto(`${examplesServer.baseUrl}/demo-submission.html`);
    // Verify submission controls render and both lifecycle requests fire
    await expect(page.locator("#xForm .xforms-textarea").first()).toBeVisible({ timeout: renderTimeoutMs });

    await page.getByRole("button", { name: "Submit success path" }).click();
    await expect(page.locator("#xForm")).toContainText("Submission succeeded.");

    await page.getByRole("button", { name: "Submit failure path" }).click();
    await expect(page.locator("#xForm")).toContainText("Submission failed.");

    // Ensure both success and error endpoints were invoked by xf:submit actions
    expect(requests.some((url) => url.includes("/api/submit-ok"))).toBeTruthy();
    expect(requests.some((url) => url.includes("/api/submit-fail"))).toBeTruthy();
  });
});
