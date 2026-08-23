///|
test "Guardian qualification is default-off and approval-worthy only" {
  assert_false(mooncode_guardian_trial_enabled({ "payload": {} }))
  assert_true(
    mooncode_guardian_trial_enabled({
      "payload": { "planner_guardian_high_risk_trial": true },
    }),
  )
  assert_true(
    mooncode_guardian_trial_observation({
      "tool": "read",
      "arguments": { "path": "moon.mod" },
    })
    is None,
  )
  let observation = mooncode_guardian_trial_observation({
    "tool": "shell",
    "arguments": { "cmd": "git push origin main" },
  })
  guard observation is Some(value) else { fail("expected qualification") }
  assert_eq(
    mooncode_json_string(value, "outcome", default=""),
    "review_required",
  )
  assert_false(mooncode_json_bool(value, "behavior_changed", default=true))
  assert_false(
    mooncode_json_bool(value, "external_inference_performed", default=true),
  )
}

///|
test "Guardian qualification retains closed signals and no action content" {
  let observation = mooncode_guardian_trial_observation({
    "tool": "shell",
    "requires_approval": true,
    "arguments": {
      "cmd": "git commit -m secret-message",
      "path": "/private/tmp/do-not-retain",
    },
  })
  guard observation is Some(value) else { fail("expected qualification") }
  let encoded = value.stringify()
  assert_true(encoded.contains("durable_history"))
  assert_true(encoded.contains("explicit_operator_boundary"))
  assert_false(encoded.contains("secret-message"))
  assert_false(encoded.contains("/private/tmp"))
  assert_false(encoded.contains("arguments"))
}

///|
test "Guardian event remains shadow-only" {
  let event = mooncode_guardian_trial_event(
    {
      "session_id": "session-guardian",
      "packet": { "command_id": "command-guardian" },
      "payload": { "planner_guardian_high_risk_trial": true },
    },
    {
      "tool": "browser",
      "arguments": { "action": "open", "url": "https://example.com" },
    },
    @clock.Timestamp::from_ms(1_000L),
  )
  guard event is Some(value) else { fail("expected event") }
  assert_eq(
    mooncode_json_string(value, "kind", default=""),
    "runtime.guardian_trial",
  )
  let trial = mooncode_json_object_field_or_empty(value, "guardian_trial")
  assert_eq(mooncode_json_string(trial, "mode", default=""), "shadow")
  assert_false(mooncode_json_bool(trial, "behavior_changed", default=true))
}
