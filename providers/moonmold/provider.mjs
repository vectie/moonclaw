import { spawn } from "node:child_process";
import readline from "node:readline";

const EXPECTED_TOOLS = new Set([
  "moonmold_semantic_operation",
  "moonmold_live_building",
]);

export class MoonMoldProviderError extends Error {
  constructor(code, message, details = {}) {
    super(message);
    this.name = "MoonMoldProviderError";
    this.code = code;
    this.details = details;
  }
}

export class MoonMoldProvider {
  constructor({ command, defaultTimeoutMs = 120_000 }) {
    if (
      !Array.isArray(command) ||
      command.length < 1 ||
      command.some((part) => typeof part !== "string" || !part)
    ) {
      throw new MoonMoldProviderError("invalid-command", "provider command must be a non-empty argv array");
    }
    if (!Number.isSafeInteger(defaultTimeoutMs) || defaultTimeoutMs < 1) {
      throw new MoonMoldProviderError("invalid-timeout", "default timeout must be positive");
    }
    this.command = [...command];
    this.defaultTimeoutMs = defaultTimeoutMs;
    this.child = null;
    this.pending = new Map();
    this.nextId = 1;
    this.handshake = null;
    this.tools = [];
  }

  async connect() {
    if (this.child) return this.handshake;
    const [executable, ...args] = this.command;
    this.child = spawn(executable, args, {
      stdio: ["pipe", "pipe", "pipe"],
      env: { ...process.env },
    });
    const lines = readline.createInterface({
      input: this.child.stdout,
      crlfDelay: Infinity,
    });
    lines.on("line", (line) => this.#receive(line));
    let stderr = "";
    this.child.stderr.on("data", (chunk) => {
      stderr = `${stderr}${chunk}`.slice(-8_000);
    });
    this.child.on("error", (error) => {
      this.#rejectAll("process-error", error.message);
    });
    this.child.on("exit", (code, signal) => {
      this.#rejectAll("process-exited", "MoonMold MCP process exited", {
        code,
        signal,
        stderr,
      });
      this.child = null;
    });
    this.handshake = await this.#request("initialize", {
      protocolVersion: "2025-06-18",
      clientInfo: { name: "moonclaw", version: "0.1.0" },
      capabilities: {},
    });
    const listed = await this.#request("tools/list", {});
    this.tools = listed.tools;
    const names = new Set(this.tools.map((tool) => tool.name));
    if (
      names.size !== EXPECTED_TOOLS.size ||
      [...EXPECTED_TOOLS].some((name) => !names.has(name))
    ) {
      await this.close();
      throw new MoonMoldProviderError(
        "capability-mismatch",
        "MoonMold MCP tool catalog does not match the bounded provider contract",
      );
    }
    for (const tool of this.tools) {
      const schema = tool.inputSchema;
      if (
        schema?.additionalProperties !== false ||
        !schema.required?.every((field) => schema.properties?.[field])
      ) {
        await this.close();
        throw new MoonMoldProviderError("unsafe-tool-schema", `tool ${tool.name} has an open schema`);
      }
    }
    return this.handshake;
  }

  capabilities() {
    if (!this.handshake) {
      throw new MoonMoldProviderError("not-connected", "provider is not connected");
    }
    return {
      providerId: "moonmold",
      protocol: this.handshake.moonmoldProtocol,
      initialSceneDigest: this.handshake.initialSceneDigest,
      runtime: this.handshake.runtimeCapabilities,
      tools: this.tools.map((tool) => ({
        name: tool.name,
        inputSchema: tool.inputSchema,
      })),
      arbitraryScripts: false,
      physicalControl: false,
    };
  }

  async callSemantic(arguments_, options = {}) {
    return this.#callTool("moonmold_semantic_operation", arguments_, options);
  }

  async runLiveBuilding(arguments_, options = {}) {
    return this.#callTool("moonmold_live_building", arguments_, options);
  }

  async #callTool(name, arguments_, { timeoutMs, signal } = {}) {
    if (!EXPECTED_TOOLS.has(name)) {
      throw new MoonMoldProviderError("unsupported-tool", "tool is not in MoonClaw's MoonMold allowlist");
    }
    if (containsScriptKey(arguments_)) {
      throw new MoonMoldProviderError("script-surface-rejected", "script/eval/shell/code parameters are forbidden");
    }
    const started = Date.now();
    const result = await this.#request(
      "tools/call",
      { name, arguments: arguments_ },
      { timeoutMs, signal },
    );
    if (result.isError) {
      throw new MoonMoldProviderError("tool-error", "MoonMold returned a tool error");
    }
    return {
      providerId: "moonmold",
      tool: name,
      requestId: arguments_.requestId,
      idempotencyKey: arguments_.idempotencyKey,
      outcome: result.structuredContent.outcome,
      durationMs: Date.now() - started,
      structuredContent: result.structuredContent,
      evidenceClass:
        result.structuredContent.evidence?.evidenceClass ?? "semantic-receipt",
      physicalEffects: false,
    };
  }

  #request(method, params, { timeoutMs = this.defaultTimeoutMs, signal } = {}) {
    if (!this.child || !this.child.stdin.writable) {
      return Promise.reject(new MoonMoldProviderError("not-connected", "MCP process is not writable"));
    }
    const id = this.nextId++;
    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        this.pending.delete(id);
        this.#notifyCancelled(id);
        reject(new MoonMoldProviderError("timeout", `MCP request ${id} exceeded ${timeoutMs}ms`));
      }, timeoutMs);
      const abort = () => {
        clearTimeout(timeout);
        this.pending.delete(id);
        this.#notifyCancelled(id);
        reject(new MoonMoldProviderError("cancelled", `MCP request ${id} was cancelled`));
      };
      signal?.addEventListener("abort", abort, { once: true });
      this.pending.set(id, {
        resolve: (value) => {
          clearTimeout(timeout);
          signal?.removeEventListener("abort", abort);
          resolve(value);
        },
        reject: (error) => {
          clearTimeout(timeout);
          signal?.removeEventListener("abort", abort);
          reject(error);
        },
      });
      this.child.stdin.write(`${JSON.stringify({
        jsonrpc: "2.0",
        id,
        method,
        params,
      })}\n`);
    });
  }

  #notifyCancelled(id) {
    if (!this.child?.stdin.writable) return;
    this.child.stdin.write(`${JSON.stringify({
      jsonrpc: "2.0",
      method: "notifications/cancelled",
      params: { requestId: id },
    })}\n`);
  }

  #receive(line) {
    let message;
    try {
      message = JSON.parse(line);
    } catch {
      this.#rejectAll("invalid-json", "MoonMold MCP emitted malformed JSON");
      return;
    }
    const pending = this.pending.get(message.id);
    if (!pending) return;
    this.pending.delete(message.id);
    if (message.error) {
      pending.reject(new MoonMoldProviderError(
        message.error.data?.moonmoldCode ?? "mcp-error",
        message.error.message,
        message.error.data?.details ?? {},
      ));
    } else {
      pending.resolve(message.result);
    }
  }

  #rejectAll(code, message, details = {}) {
    for (const request of this.pending.values()) {
      request.reject(new MoonMoldProviderError(code, message, details));
    }
    this.pending.clear();
  }

  async close() {
    if (!this.child) return;
    const child = this.child;
    this.child = null;
    this.#rejectAll("provider-closed", "MoonMold provider was closed");
    child.stdin.end();
    child.kill("SIGTERM");
    await new Promise((resolve) => {
      if (child.exitCode !== null) resolve();
      else child.once("exit", resolve);
      setTimeout(() => {
        child.kill("SIGKILL");
        resolve();
      }, 2_000).unref();
    });
  }
}

function containsScriptKey(value) {
  if (!value || typeof value !== "object") return false;
  if (Array.isArray(value)) return value.some(containsScriptKey);
  return Object.entries(value).some(([key, child]) =>
    /(script|python|shell|eval|expression|command|code)/i.test(key) ||
    containsScriptKey(child)
  );
}

