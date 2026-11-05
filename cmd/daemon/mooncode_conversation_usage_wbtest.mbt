///|
test "usage survives compacted plans and duplicate receipts without an exporter" {
  let command = mooncode_claim_projection_command("/book", "usage-session")
  let event : Json = {
    "command_id": "claim-projection-command",
    "kind": "runtime.planner_replan_requested",
    "created_at": "2026-11-05T00:00:00Z",
  }
  let observed = mooncode_planner_observed(
    { "events": [event] },
    {
      "usage_observed": true,
      "prompt_tokens": 100,
      "completion_tokens": 20,
      "cache_read_tokens": 40,
    },
    "response-a",
  )
  let events = mooncode_json_array_items(observed, "events")
  events.push(
    mooncode_json_array_items(
      mooncode_planner_observed(
        { "events": [event] },
        {
          "usage_observed": true,
          "prompt_tokens": 80,
          "completion_tokens": 15,
          "cache_read_tokens": 25,
        },
        "response-b",
      ),
      "events",
    )[0],
  )
  assert_true(
    mooncode_json_string(events[0], "id", default="") !=
    mooncode_json_string(events[1], "id", default=""),
  )
  events.push(event)
  let receipt : Json = {
    "command_id": "claim-projection-command",
    "status": "runtime-delivered",
    "planner_steps": [{ "planner_metrics": { "prompt_tokens": 9999 } }],
  }
  let turns = mooncode_conversation_turns([command], [receipt, receipt], events)
  assert_eq(turns.length(), 1)
  let usage = turns[0].usage
  assert_true(mooncode_json_bool(usage, "measured", default=false))
  assert_eq(mooncode_json_int(usage, "response_count", default=0), 2)
  assert_eq(mooncode_json_int(usage, "input_tokens", default=0), 180)
  assert_eq(mooncode_json_int(usage, "output_tokens", default=0), 35)
  assert_eq(mooncode_json_int(usage, "cached_input_tokens", default=0), 65)
  assert_eq(
    mooncode_conversation_turns([command], [], [event])[0].usage,
    Json::object({}),
  )
}
