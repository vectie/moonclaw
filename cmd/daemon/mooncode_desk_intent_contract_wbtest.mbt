///|
/// Native payloads produced by actual UI typed encoding then Desk adaptation.
test "Desk UI native payloads complete according to task purpose" {
  let commands = [
    @json.parse(
      "{\"protocol\":\"mooncode.v1\",\"command\":\"prompt\",\"text\":\"Review this code; do not edit or fix any files\",\"model\":\"\",\"session_id\":\"session-intent\",\"book_root\":\"/tmp/readonly-intent-book\",\"context_path\":\"\",\"payload\":{\"planner_guidance\":{\"no_match_policy\":\"Treat an empty optional search as a useful result, not a failed turn.\",\"finish_policy\":\"Always finish with a concise user-facing answer when no more tool work is needed.\",\"tool_failure_policy\":\"Report real execution failures and continue when a bounded fallback exists.\"},\"planner_reasoning_effort\":\"none\"},\"packet\":{\"action\":\"prompt\",\"client_turn_id\":\"ui-intent-auto\",\"context_path\":\"\",\"message\":\"Review this code; do not edit or fix any files\",\"model\":\"\",\"web_search\":false,\"planner_reasoning_effort\":\"none\",\"approval_id\":\"\",\"target_command_id\":\"\",\"tool_call_id\":\"\",\"force_preflight\":false,\"protocol\":\"mooncode.v1\",\"kind\":\"mooncode.command\",\"status\":\"accepted\",\"command_id\":\"mooncode-command-fe6d7ca9671cca3d\",\"created_at\":\"2026-10-02T00:00:00Z\",\"session_id\":\"session-intent\",\"workspace_id\":\"book\",\"workspace_name\":\"\",\"workspace_root\":\"/tmp/readonly-intent-book\",\"control\":\"prompt\",\"approval\":\"user\",\"runtime_tool_calls\":[]},\"web_search\":false,\"runtime_tool_calls\":[]}",
    ),
    @json.parse(
      "{\"protocol\":\"mooncode.v1\",\"command\":\"prompt\",\"text\":\"Review this code; do not edit or fix any files\",\"model\":\"\",\"session_id\":\"session-intent\",\"book_root\":\"/tmp/readonly-intent-book\",\"context_path\":\"\",\"payload\":{\"task_intent\":\"read_only\",\"planner_guidance\":{\"no_match_policy\":\"Treat an empty optional search as a useful result, not a failed turn.\",\"finish_policy\":\"Always finish with a concise user-facing answer when no more tool work is needed.\",\"tool_failure_policy\":\"Report real execution failures and continue when a bounded fallback exists.\"},\"planner_reasoning_effort\":\"none\"},\"packet\":{\"action\":\"prompt\",\"client_turn_id\":\"ui-intent-read_only\",\"context_path\":\"\",\"message\":\"Review this code; do not edit or fix any files\",\"model\":\"\",\"web_search\":false,\"planner_reasoning_effort\":\"none\",\"approval_id\":\"\",\"target_command_id\":\"\",\"tool_call_id\":\"\",\"force_preflight\":false,\"task_intent\":\"read_only\",\"protocol\":\"mooncode.v1\",\"kind\":\"mooncode.command\",\"status\":\"accepted\",\"command_id\":\"mooncode-command-f2cd2c683be48318\",\"created_at\":\"2026-10-02T00:00:00Z\",\"session_id\":\"session-intent\",\"workspace_id\":\"book\",\"workspace_name\":\"\",\"workspace_root\":\"/tmp/readonly-intent-book\",\"control\":\"prompt\",\"approval\":\"user\",\"runtime_tool_calls\":[]},\"web_search\":false,\"runtime_tool_calls\":[]}",
    ),
    @json.parse(
      "{\"protocol\":\"mooncode.v1\",\"command\":\"prompt\",\"text\":\"Review this code; do not edit or fix any files\",\"model\":\"\",\"session_id\":\"session-intent\",\"book_root\":\"/tmp/readonly-intent-book\",\"context_path\":\"\",\"payload\":{\"task_intent\":\"workspace_change\",\"planner_guidance\":{\"no_match_policy\":\"Treat an empty optional search as a useful result, not a failed turn.\",\"finish_policy\":\"Always finish with a concise user-facing answer when no more tool work is needed.\",\"tool_failure_policy\":\"Report real execution failures and continue when a bounded fallback exists.\"},\"planner_reasoning_effort\":\"none\"},\"packet\":{\"action\":\"prompt\",\"client_turn_id\":\"ui-intent-workspace_change\",\"context_path\":\"\",\"message\":\"Review this code; do not edit or fix any files\",\"model\":\"\",\"web_search\":false,\"planner_reasoning_effort\":\"none\",\"approval_id\":\"\",\"target_command_id\":\"\",\"tool_call_id\":\"\",\"force_preflight\":false,\"task_intent\":\"workspace_change\",\"protocol\":\"mooncode.v1\",\"kind\":\"mooncode.command\",\"status\":\"accepted\",\"command_id\":\"mooncode-command-5575a12edaa98066\",\"created_at\":\"2026-10-02T00:00:00Z\",\"session_id\":\"session-intent\",\"workspace_id\":\"book\",\"workspace_name\":\"\",\"workspace_root\":\"/tmp/readonly-intent-book\",\"control\":\"prompt\",\"approval\":\"user\",\"runtime_tool_calls\":[]},\"web_search\":false,\"runtime_tool_calls\":[]}",
    ),
  ]
  for command in commands {
    let explicit = mooncode_json_string(
      mooncode_json_object_field_or_empty(command, "payload"),
      "task_intent",
      default="",
    )
    let coding = explicit == "workspace_change"
    assert_eq(mooncode_runtime_turn_requires_verification(command), coding)
    let results = readonly_intent_results()
    assert_eq(
      mooncode_runtime_turn_completion_verdict(
        command,
        results,
        require_horizon=mooncode_runtime_turn_requires_verification(command),
      ).accepted,
      !coding,
    )
    assert_eq(
      mooncode_runtime_turn_discovery_saturated(
        command,
        { "tool": "read", "arguments": { "path": "src/next.mbt" } },
        results,
      ),
      coding,
    )
    assert_eq(
      mooncode_runtime_turn_recoverable_horizon_finish(
        command,
        { "planner_mode": "model-tool-calls" },
        [{ "tool": "finish" }],
        results,
      ),
      coding,
    )
  }
}
