///|
fn mooncode_capability_endpoints() -> Array[String] {
  mooncode_native_capability_endpoints()
}

///|
fn mooncode_capability_tools() -> Array[String] {
  mooncode_native_capability_tools()
}

///|
fn mooncode_capabilities_payload() -> Json {
  {
    "component": "mooncode",
    "provider": "moonclaw",
    "protocol": mooncode_protocol_version(),
    "capability_contract_id": mooncode_native_capability_contract_id(),
    "capability_surface_fingerprint": mooncode_native_capability_surface_fingerprint(),
    "capability_surface": mooncode_native_capability_surface_json(),
    "native_runtime_ready": true,
    "bridge_mode": "moonclaw-daemon-native-mooncode",
    "runtime_owner": "moonclaw",
    "session_owner": "moondesk",
    "endpoints": mooncode_capability_endpoints(),
    "control_commands": ["prompt", "steer", "cancel"],
    "tools": mooncode_capability_tools(),
    "event_lifecycle": [
      "PreConversation", "AssistantMessage", "PreToolCall", "PostToolCall", "PostConversation",
    ],
    "first_class_events": ["Cancelled", "Failed", "ContextPruned", "Pruned"],
    "command_scoped_web_search": "MoonCode commands persist web_search intent in commands.jsonl and runtime receipts so research work does not depend on global defaults.",
    "execution_boundary": "MoonClaw accepts Moondesk MoonCode command packets and executes them through the existing MoonClaw task/agent runtime for the target book root.",
    "package_result_endpoint": "POST /v1/mooncode/sessions/<id>/package-result?book_root=<path> accepts package_built/package_verified proof packets for MoonBook-owned executable artifacts; native package manifests also promote generated source files under portable/app-tool/mooncode/<session>/sources/<command>/ with hash metadata.",
    "durable_session_store": ".moonclaw/mooncode/sessions/<session-id>/session.json plus commands.jsonl, runtime-dispatches.jsonl, events.jsonl, and package-results.jsonl under the selected book root.",
    "serve_scheduler_endpoint": "GET /v1/mooncode/sessions/<id>/serve-scheduler?book_root=<path> projects the OpenSeek-style ordered prompt/steer/cancel scheduler from native commands.jsonl and runtime-dispatches.jsonl without spawning a task.",
    "runtime_claim_endpoint": "GET/POST /v1/mooncode/sessions/<id>/runtime-claim?book_root=<path> projects and appends native runtime-claimed receipts over the durable command queue without spawning a task.",
    "runtime_dispatch_endpoint": "POST /v1/mooncode/sessions/<id>/runtime-dispatch?book_root=<path> claims the next durable command if needed, forwards it to the MoonClaw task runtime, and appends a runtime-delivered receipt.",
    "runtime_turn_endpoint": "POST /v1/mooncode/sessions/<id>/runtime-turn?book_root=<path> claims the next durable command if needed, includes serve_scheduler_state and serve_scheduler_decision, executes explicit, deterministic, or bounded model-planned native MoonCode tool calls only when the scheduler permits work, appends planner reasoning/tool-call/tool-result events plus steer_applied/steer_deferred/steer_dropped/cancel_dropped settlement events for control commands, test_result evidence for run_tests/run_build commands, eval_report.manifest evidence for run_eval commands, receipt.accept/receipt.reject review evidence for review commands, and runtime.commit_created proof for commit commands, then closes the command with a terminal runtime-completed or runtime-failed receipt.",
    "runtime_loop_endpoint": "POST /v1/mooncode/sessions/<id>/runtime-loop?book_root=<path> repeatedly runs bounded native runtime-turns over the durable queue until idle, failure, cancel, or max_turns; callers may pass live_wait_ms and poll_ms to opt into bounded live polling for newly appended prompt/steer/cancel commands before returning idle.",
    "runtime_loop_options": mooncode_native_capability_runtime_loop_options(),
    "runtime_service_endpoint": "POST /v1/mooncode/sessions/<id>/runtime-service?book_root=<path> starts a daemon task-group supervisor that records runtime.service_started/runtime.service_finished events and runs the bounded native runtime-loop outside the request lifecycle.",
    "runtime_service_options": {
      "max_turns": { "default": 8, "min": 1, "max": 32 },
      "live_wait_ms": { "default": 5000, "min": 0, "max": 30000 },
      "poll_ms": { "default": 250, "min": 25, "max": 2000 },
    },
    "runtime_events_endpoint": "GET/POST /v1/mooncode/sessions/<id>/runtime-events?book_root=<path> reads or appends normalized MoonCode runtime evidence into events.jsonl.",
    "stream_endpoint": "GET /v1/mooncode/sessions/<id>/stream?book_root=<path>&format=jsonl|sse&since=<n>&wait_ms=<ms>&poll_ms=<ms> replays durable book-local MoonCode events from events.jsonl with resumable sequence records; wait_ms enables bounded long-poll live tailing for new stream records.",
    "eval_report_endpoint": "GET /v1/mooncode/sessions/<id>/eval-report?book_root=<path> reports native eval/readiness evidence from the live binding or the selected book's durable sidecar.",
    "tool_execution_endpoint": "POST /v1/mooncode/sessions/<id>/tool-exec?book_root=<path> executes the native MoonCode read/edit/write/apply_patch/revert_patch/shell/moon_ide/moon_cmd/moon_check/finish tool contract against the selected MoonBook root and appends command-scoped proof events, including runtime.patch_applied and runtime.patch_reverted for reviewed text replacements plus single-file or multi-file unified-diff patchsets; selected hunk targets can be addressed with hunk_index/hunk_id or path#hunk-N and report hunk_dispatch_scope plus file_path metadata; patch tools can attach post-change verification from verification_command/test_command, verify_after, or moon_check_target.",
    "queue_only_command_mode": "POST /v1/mooncode/sessions/<id>/commands with native_dispatch_mode=queue-only appends the durable command and command.queued_for_runtime_turn event without spawning or messaging a legacy MoonClaw task; callers can then invoke runtime-turn for non-duplicating native execution.",
    "prompt_planner": "runtime-turn expands bounded prompt and delivered steer requests through explicit, deterministic, or model-planned native tool batches under MoonBook-owned tools/ or apps/ paths; idle steer is deferred as durable steering context and injected into the next turn before planning, while review commands settle as deterministic context unless explicit tool calls are provided.",
    "review_receipts": "runtime-turn writes accept/reject review receipts under wiki/reviews/mooncode/<session-id>/ and emits review-lane receipt.accept/receipt.reject events so Moondesk can clear pending diffs from MoonClaw-owned evidence.",
    "eval_proof": "runtime-turn handles run_eval commands by running MoonClaw's native OpenSeek-style tool/file-edit harnesses, writing wiki/reviews/mooncode/<session-id>/eval-report.json in the selected MoonBook, and emitting eval_report.manifest evidence with tool_harness and file_edit results.",
    "commit_proof": "runtime-turn handles commit commands by running git inside the selected MoonBook root, excluding MoonClaw/Moontown runtime sidecars from status and staging, and emitting runtime.commit_created with the resulting commit SHA only after git commit and rev-parse HEAD succeed.",
    "ordering_rule": "Prompt and command packets are accepted per session and forwarded to the bound MoonClaw task in request order. Steer packets are delivered as steering context to the same task. Cancel packets target an existing bound task and never spawn a new task. Package-result proof packets append command-scoped runtime evidence for already accepted package commands.",
  }
}

///|
async fn Daemon::mooncode_capabilities(
  self : Daemon,
  w : @httpx.ResponseWriter,
) -> Unit {
  ignore(self)
  w.header().set("Content-Type", "application/json")
  w.write_header(200)
  w.write(mooncode_capabilities_payload().stringify())
}
