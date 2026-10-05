import { spawn, type ChildProcess } from "node:child_process";
import { once } from "node:events";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, "..", "..");

export type RunningServer = {
  baseUrl: string;
  child: ChildProcess;
  name: string;
};

const DEFAULT_EXAMPLES_BASE_PORT = 5174;

// Derive example ports from the wrapper-selected PLAYWRIGHT_TEST_PORT base so Windows reserved port blocks (winnat/Hyper-V excluded ranges; netsh interface ipv4 show excludedportrange protocol=tcp) cannot collide with fixed 519x/520x ports
export function resolveExamplesPort(preferredPort: number): number {
  const basePort = Number(process.env.PLAYWRIGHT_TEST_PORT || DEFAULT_EXAMPLES_BASE_PORT);
  return basePort + (preferredPort - DEFAULT_EXAMPLES_BASE_PORT);
}

export function startExamplesServer(port: number, host = "127.0.0.1"): RunningServer {
  const child = spawn("node", ["examples/server.mjs"], {
    cwd: repoRoot,
    env: {
      ...process.env,
      EXAMPLES_HOST: host,
      EXAMPLES_PORT: String(port)
    },
    stdio: "pipe"
  });

  return {
    baseUrl: `http://${host}:${port}`,
    child,
    name: "examples-server"
  };
}

export async function waitForServerReady(server: RunningServer, timeoutMs = 15_000): Promise<void> {
  const startedAt = Date.now();
  while ((Date.now() - startedAt) < timeoutMs) {
    if (server.child.exitCode !== null) {
      const errorOutput = server.child.stderr?.read?.()?.toString() ?? "";
      throw new Error(`${server.name} exited before ready (code ${server.child.exitCode}). ${errorOutput}`);
    }
    try {
      const response = await fetch(`${server.baseUrl}/index.html`);
      if (response.ok || response.status === 404) {
        return;
      }
    } catch {
      // wait and retry
    }
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  throw new Error(`Timed out waiting for ${server.name} at ${server.baseUrl}.`);
}

export async function stopServer(server: RunningServer): Promise<void> {
  if (!server || server.child.exitCode !== null) {
    return;
  }
  server.child.kill("SIGTERM");
  await Promise.race([
    once(server.child, "exit"),
    new Promise((resolve) => setTimeout(resolve, 2_000))
  ]);
  if (server.child.exitCode === null) {
    server.child.kill("SIGKILL");
  }
}
