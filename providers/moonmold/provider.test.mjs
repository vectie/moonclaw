import assert from "node:assert/strict";
import { rm } from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import {
  MoonMoldProvider,
  MoonMoldProviderError,
} from "./provider.mjs";

const MOONMOLD = "/Users/kq/moonsuite/development/sources/moonmold";
const SERVER = path.join(MOONMOLD, "adapter/mcp-server.mjs");
const ROOT =
  "/Users/kq/moonsuite/development/worktrees/fourth-update/moonmold-integration/moonclaw";

async function provider() {
  const value = new MoonMoldProvider({
    command: [process.execPath, SERVER],
    defaultTimeoutMs: 120_000,
  });
  await value.connect();
  return value;
}

test("provider discovers exact semantic and live capabilities", async (context) => {
  const value = await provider();
  context.after(() => value.close());
  const capabilities = value.capabilities();
  assert.deepEqual(capabilities.tools.map((tool) => tool.name), [
    "moonmold_semantic_operation",
    "moonmold_live_building",
  ]);
  assert.equal(capabilities.arbitraryScripts, false);
  assert.equal(capabilities.physicalControl, false);
  assert.equal(capabilities.runtime.blender.available, true);
  const receipt = await value.callSemantic({
    projectId: "moonbook-provider-test",
    sessionId: "moonclaw-provider-test",
    modelId: "provider-test-model",
    requestId: "provider-capability-1",
    idempotencyKey: "provider-capability-1",
    expectedParentDigest: capabilities.initialSceneDigest,
    workspaceRoot: "/Users/kq/moonsuite",
    deadlineMs: 30000,
    authority: "observe",
    method: "capability.discover",
    params: {},
  });
  assert.equal(receipt.providerId, "moonmold");
  assert.equal(receipt.structuredContent.result.blender.available, true);
  assert.equal(receipt.physicalEffects, false);
});

test("provider invokes live Blender through MCP and preserves receipt identity", async (context) => {
  const value = await provider();
  context.after(() => value.close());
  const outputRoot = path.join(ROOT, ".tmp/moonmold-provider-live");
  await rm(outputRoot, { recursive: true, force: true });
  const receipt = await value.runLiveBuilding({
    requestId: "provider-live-1",
    idempotencyKey: "provider-live-city-hall-v1",
    inputPath: path.join(MOONMOLD, "fixtures/city-hall-image-referenced.json"),
    outputRoot,
    timeoutMs: 120000,
    authority: "workspace-mutation",
  });
  assert.equal(receipt.requestId, "provider-live-1");
  assert.equal(receipt.evidenceClass, "live-blender");
  assert.equal(receipt.structuredContent.evidence.accepted, true);
  assert.equal(receipt.physicalEffects, false);
});

test("provider rejects scripts, timeout, and cooperative cancellation", async (context) => {
  const value = await provider();
  context.after(() => value.close());
  await assert.rejects(
    value.callSemantic({ requestId: "bad", pythonScript: "print('no')" }),
    (error) => error instanceof MoonMoldProviderError &&
      error.code === "script-surface-rejected",
  );
  const timeoutOutput = path.join(ROOT, ".tmp/moonmold-provider-timeout");
  await rm(timeoutOutput, { recursive: true, force: true });
  await assert.rejects(
    value.runLiveBuilding({
      requestId: "provider-timeout-1",
      idempotencyKey: "provider-timeout-1",
      inputPath: path.join(MOONMOLD, "fixtures/tower-b.json"),
      outputRoot: timeoutOutput,
      timeoutMs: 120000,
      authority: "workspace-mutation",
    }, { timeoutMs: 1 }),
    (error) => error instanceof MoonMoldProviderError && error.code === "timeout",
  );
  const cancelledOutput = path.join(ROOT, ".tmp/moonmold-provider-cancel");
  await rm(cancelledOutput, { recursive: true, force: true });
  const controller = new AbortController();
  const promise = value.runLiveBuilding({
    requestId: "provider-cancel-1",
    idempotencyKey: "provider-cancel-1",
    inputPath: path.join(MOONMOLD, "fixtures/habitat-a.json"),
    outputRoot: cancelledOutput,
    timeoutMs: 120000,
    authority: "workspace-mutation",
  }, { signal: controller.signal });
  setTimeout(() => controller.abort(), 10);
  await assert.rejects(
    promise,
    (error) => error instanceof MoonMoldProviderError && error.code === "cancelled",
  );
});

