import { test, expect } from "@playwright/test";
import { resolveExamplesPort, startExamplesServer, stopServer, waitForServerReady, type RunningServer } from "./examples-server";

const renderTimeoutMs = 15_000;
const examplesPort = resolveExamplesPort(5203);

test.describe("Examples demo-actions", () => {
  test.describe.configure({ mode: "serial" });
  let examplesServer: RunningServer;

  test.beforeAll(async () => {
    examplesServer = startExamplesServer(examplesPort);
    await waitForServerReady(examplesServer);
  });

  test.afterAll(async () => {
    await stopServer(examplesServer);
  });

  test("supports reset, dispatch, send, readonly, and load behavior", async ({ page }) => {
    const requests: string[] = [];
    page.on("request", (request) => {
      if (request.url().includes("/api/echo")) {
        requests.push(request.url());
      }
    });

    await page.goto(`${examplesServer.baseUrl}/demo-actions.html`);
    // Validate readonly MIP is applied to second input control
    await expect(page.locator("#xForm .xforms-input").first()).toBeVisible({ timeout: renderTimeoutMs });
    const inputs = page.locator("#xForm input");
    await expect(inputs.nth(1)).toHaveAttribute("data-readonly", "true");

    await inputs.nth(0).fill("Changed text");
    await page.getByRole("button", { name: "Reset form" }).click();
    // Verify reset action restores original instance value for editable field
    await expect(inputs.nth(0)).toHaveValue("Edit me");

    await page.getByRole("button", { name: "Dispatch custom event" }).click();
    // Verify custom dispatch updates bound status output
    await expect(page.locator("#xForm")).toContainText("Custom event fired.");

    await page.getByRole("button", { name: "Send to echo endpoint" }).click();
    await expect(page.locator("#xForm")).toContainText("Send succeeded.");
    // Confirm xf:send invoked endpoint request
    expect(requests.length).toBeGreaterThan(0);

    const popupPromise = page.waitForEvent("popup");
    await page.getByRole("button", { name: "Open external docs" }).click();
    const popup = await popupPromise;
    // Assert xf:load with show=new opens new browsing context
    await expect(popup).toHaveURL(/\/index\.html$/);
  });
});
