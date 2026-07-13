import { createHash } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";

const statePath = process.argv[2];
if (!statePath) throw new Error("state path is required");

let input = "";
for await (const chunk of process.stdin) input += chunk;
const command = JSON.parse(input);

if (String(command.semantic_target).includes("crash")) process.exit(17);
if (String(command.semantic_target).includes("delay")) {
  await new Promise((resolve) => setTimeout(resolve, 2000));
}

let state = { revision: 0, actions: [], results: {} };
try { state = JSON.parse(await readFile(statePath, "utf8")); } catch {}

if (state.results[command.action_id]) {
  process.stdout.write(JSON.stringify(state.results[command.action_id]) + "\n");
  process.exit(0);
}

const digest = (value) => createHash("sha256")
  .update(JSON.stringify(value))
  .digest("hex");
const before = digest({ revision: state.revision, actions: state.actions });
const missing = String(command.semantic_target).includes("missing");

if (!missing) {
  state.revision += 1;
  state.actions.push({
    action_id: command.action_id,
    operation: command.operation,
    semantic_target: command.semantic_target,
  });
}

const after = digest({ revision: state.revision, actions: state.actions });
const receipt = {
  host_receipt_id: `fixture-${digest(command).slice(0, 24)}`,
  request_id: command.request_id,
  session_id: command.session_id,
  action_id: command.action_id,
  code_revision: command.code_revision,
  authority_envelope_id: command.authority_envelope_id,
  capability_digest: command.capability_digest,
  status: missing ? ["RejectedByHost", "semantic-target-not-found"] : "Completed",
  before_state_digest: before,
  after_state_digest: after,
  screenshot_before_ref: "",
  screenshot_after_ref: "",
  observations: missing
    ? ["fixture semantic target unresolved"]
    : [`fixture executed ${command.operation} on ${command.semantic_target}`],
  target_resolved: !missing,
  completed_at: "fixture-time",
};

state.results[command.action_id] = receipt;
await writeFile(statePath, JSON.stringify(state, null, 2));
process.stdout.write(JSON.stringify(receipt) + "\n");
