///|
test "decision decoder accepts all variants without aggregate operation limit" {
  let operations = Array::makei(42, fn(i) {
    "{\"operation_id\":\"op-" +
    i.to_string() +
    "\",\"kind\":\"shell\",\"input\":\"你好\\n\\\"ok\\\"\",\"policy\":{\"max_output_bytes\":2147483647,\"timeout_milliseconds\":2147483647}}"
  }).join(",")
  for
    fixture in [
      "{\"type\":\"continue\",\"operations\":[" +
      operations +
      "],\"expected_progress\":\"进展\\n\",\"rationale\":\"理由\"}",
      "{\"type\":\"achieved\",\"summary\":\"完成\\t✓\",\"evidence\":[{\"criterion\":\"criterion-1\",\"evidence_refs\":[\"proof\\\"1\"]}]}",
      "{\"type\":\"blocked\",\"reason\":{\"code\":\"external\",\"detail\":\"等待\"},\"attempted_alternatives\":[\"替代\"],\"required_event\":\"批准\\\"\\\\事件\"}",
      "{\"type\":\"blocked\",\"reason\":{\"code\":\"external\",\"detail\":\"waiting\"},\"attempted_alternatives\":[\"alternative\"],\"required_event\":null}",
    ] {
    ignore(mooncode_goal_runtime_decode_decision(@json.parse(fixture)))
  }
}

///|
test "decision decoder rejects malformed and semantically invalid variants" {
  let rejected = [
    "{\"type\":\"unknown\",\"summary\":\"done\",\"evidence\":[]}", "{\"type\":\"continue\",\"summary\":\"done\",\"evidence\":[]}",
    "{\"type\":\"continue\",\"operations\":[],\"expected_progress\":\"progress\",\"rationale\":\"reason\"}",
    "{\"type\":\"continue\",\"operations\":[{\"operation_id\":\"x\",\"kind\":\"shell\",\"input\":\"{}\",\"policy\":{\"max_output_bytes\":1,\"timeout_milliseconds\":1}},{\"operation_id\":\"x\",\"kind\":\"shell\",\"input\":\"{}\",\"policy\":{\"max_output_bytes\":1,\"timeout_milliseconds\":1}}],\"expected_progress\":\"progress\",\"rationale\":\"reason\"}",
    "{\"type\":\"achieved\",\"summary\":\"done\",\"evidence\":[]}", "{\"type\":\"achieved\",\"summary\":\"done\",\"evidence\":[{\"criterion\":\"c\",\"evidence_refs\":[\"r\",\"r\"]},{\"criterion\":\"c\",\"evidence_refs\":[\"s\"]}]}",
    "{\"type\":\"blocked\",\"reason\":{\"code\":\"external\",\"detail\":\"wait\"},\"attempted_alternatives\":[],\"required_event\":null}",
    "{\"type\":\"blocked\",\"reason\":{\"code\":\"external\",\"detail\":\"wait\"},\"attempted_alternatives\":[\"a\",\"a\"],\"required_event\":null}",
    "{\"type\":\"blocked\",\"reason\":{\"code\":\" invalid\",\"detail\":\"wait\"},\"attempted_alternatives\":[\"a\"],\"required_event\":null}",
    "{\"type\":\"blocked\",\"reason\":{\"code\":\"external\",\"detail\":\"wait\"},\"attempted_alternatives\":[\"a\"],\"required_event\":1}",
    "{\"type\":\"blocked\",\"reason\":{\"code\":\"external\",\"detail\":\"wait\"},\"attempted_alternatives\":[1],\"required_event\":null}",
    "{\"type\":\"achieved\",\"summary\":1,\"evidence\":[],\"extra\":true}", "{\"type\":\"blocked\",\"reason\":{\"code\":\"external\",\"detail\":\"wait\"},\"attempted_alternatives\":[\"a\"]}",
  ].map(fn(text) { @json.parse(text) })
  for value in rejected {
    let did_reject = try {
      ignore(mooncode_goal_runtime_decode_decision(value))
      false
    } catch {
      MoonCodeGoalRuntimeCodecError::Invalid(_) => true
    }
    assert_true(did_reject)
  }
}

///|
fn codec_test_operation() -> @mooncode_core.GoalRuntimeOperation {
  {
    operation_id: "op-1",
    kind: "shell",
    input: "{}",
    policy: { max_output_bytes: 1024, timeout_milliseconds: 1000 },
  }
}

///|
fn codec_test_event(
  event : @mooncode_core.GoalRuntimeEvent,
  at : Int64,
) -> MoonCodeGoalRuntimeStoredEvent raise MoonCodeGoalRuntimeCodecError {
  new_mooncode_goal_runtime_stored_event("session-1", "goal-1", event, at)
}

///|
test "event decoder roundtrips every canonical v1 variant" {
  let operation : @mooncode_core.GoalRuntimeOperation = {
    operation_id: "操作-\"\\",
    kind: "shell-世界",
    input: "输入 \"quoted\" \\ path",
    policy: { max_output_bytes: 2147483647, timeout_milliseconds: 2147483647 },
  }
  let evidence : @mooncode_core.GoalCriterionEvidence = {
    criterion: "标准-\"\\",
    evidence_refs: ["证明-世界", "quote \" and slash \\"],
  }
  let reason : @mooncode_core.GoalBlockedReason = {
    code: "外部-\"\\",
    detail: "等待 \"批准\" \\ 路径",
  }
  let events : Array[@mooncode_core.GoalRuntimeEvent] = [
    @mooncode_core.PlannerDecision(
      "event-continue",
      @mooncode_core.Continue([operation], "继续-\"\\", "理由-世界"),
    ),
    @mooncode_core.PlannerDecision(
      "event-achieved",
      @mooncode_core.Achieved("完成-\"\\", [evidence]),
    ),
    @mooncode_core.PlannerDecision(
      "event-blocked-some",
      @mooncode_core.Blocked(reason, ["替代-\"\\"], Some("批准-\"\\")),
    ),
    @mooncode_core.PlannerDecision(
      "event-blocked-none",
      @mooncode_core.Blocked(reason, ["另一路径"], None),
    ),
    @mooncode_core.OperationAccepted("event-operation", "操作编号-\"\\"),
    @mooncode_core.CheckpointAccepted("event-checkpoint", "检查点-\"\\"),
    @mooncode_core.PhaseChanged("event-queued", @mooncode_core.Queued),
    @mooncode_core.PhaseChanged("event-running", @mooncode_core.Running),
    @mooncode_core.PhaseChanged(
      "event-waiting-approval",
      @mooncode_core.WaitingApproval,
    ),
    @mooncode_core.PhaseChanged(
      "event-retry-backoff",
      @mooncode_core.RetryBackoff,
    ),
    @mooncode_core.PhaseChanged(
      "event-paused-no-progress",
      @mooncode_core.PausedNoProgress,
    ),
    @mooncode_core.PhaseChanged(
      "event-paused-external",
      @mooncode_core.PausedExternal,
    ),
    @mooncode_core.Cancelled("event-cancelled", "取消-\"\\世界"),
  ]
  for i, event in events {
    let recorded_at = if i == events.length() - 1 {
      9223372036854775807L
    } else {
      i.to_int64()
    }
    let encoded = encode_mooncode_goal_runtime_stored_event(
      codec_test_event(event, recorded_at),
    )
    let decoded = decode_mooncode_goal_runtime_stored_event(encoded)
    assert_eq(encode_mooncode_goal_runtime_stored_event(decoded), encoded)
  }
}

///|
fn codec_assert_event_decode_rejects(text : String) -> Unit {
  ignore(decode_mooncode_goal_runtime_stored_event(text)) catch {
    MoonCodeGoalRuntimeCodecError::Invalid(_) => return
  }
  abort("expected event decoder rejection")
}

///|
test "event decoder requires exact canonical encoder bytes" {
  let operation = @mooncode_core.GoalRuntimeOperation::{
    operation_id: "op-1",
    kind: "shell",
    input: "path / value",
    policy: { max_output_bytes: 1, timeout_milliseconds: 1 },
  }
  let event = @mooncode_core.PlannerDecision(
    "event-canonical",
    @mooncode_core.Continue([operation], "progress", "reason"),
  )
  let encoded = encode_mooncode_goal_runtime_stored_event(
    codec_test_event(event, 1L),
  )
  let decoded = decode_mooncode_goal_runtime_stored_event(encoded)
  assert_eq(encode_mooncode_goal_runtime_stored_event(decoded), encoded)
  let assert_mutation_rejected = fn(mutated : String) raise {
    assert_true(mutated != encoded)
    codec_assert_event_decode_rejects(mutated)
  }
  assert_mutation_rejected(" " + encoded)
  assert_mutation_rejected(encoded + "\n")
  assert_mutation_rejected(
    encoded
    .replace(
      old="{\"id\":\"",
      new="{\"kind\":\"mooncode.goal.runtime.event.v1\",\"id\":\"",
    )
    .replace(old="\",\"kind\":\"mooncode.goal.runtime.event.v1\"", new="\""),
  )
  assert_mutation_rejected(
    encoded.replace(
      old="\"session_id\":\"session-1\"",
      new="\"session_id\":\"session-1\",\"session_id\":\"session-1\"",
    ),
  )
  assert_mutation_rejected(
    encoded.replace(
      old="\"payload\":",
      new="\"\\u0070ayload\":null,\"payload\":",
    ),
  )
  assert_mutation_rejected(
    encoded.replace(
      old="\"max_output_bytes\":1,",
      new="\"max_output_bytes\":1,\"max_output_bytes\":1,",
    ),
  )
  assert_mutation_rejected(
    encoded.replace(old="path / value", new="path \\/ value"),
  )
  for spelling in ["1.0", "1e0", "-0"] {
    assert_mutation_rejected(
      encoded.replace(
        old="\"recorded_at\":1",
        new="\"recorded_at\":" + spelling,
      ),
    )
  }
  for spelling in ["1.0", "1e0"] {
    assert_mutation_rejected(
      encoded.replace(
        old="\"max_output_bytes\":1,",
        new="\"max_output_bytes\":" + spelling + ",",
      ),
    )
  }
}

///|
test "event decoder rejects schema constants digest and aggregate-bound injection" {
  let continue_operation : @mooncode_core.GoalRuntimeOperation = {
    operation_id: "op-1",
    kind: "shell",
    input: "opaque max_turns token_budget",
    policy: { max_output_bytes: 1, timeout_milliseconds: 1 },
  }
  let continue_encoded = encode_mooncode_goal_runtime_stored_event(
    codec_test_event(
      @mooncode_core.PlannerDecision(
        "event-schema",
        @mooncode_core.Continue([continue_operation], "progress", "reason"),
      ),
      1L,
    ),
  )
  let achieved_evidence : @mooncode_core.GoalCriterionEvidence = {
    criterion: "criterion-1",
    evidence_refs: ["proof-1"],
  }
  let achieved_encoded = encode_mooncode_goal_runtime_stored_event(
    codec_test_event(
      @mooncode_core.PlannerDecision(
        "event-schema-achieved",
        @mooncode_core.Achieved("done", [achieved_evidence]),
      ),
      1L,
    ),
  )
  let blocked_reason : @mooncode_core.GoalBlockedReason = {
    code: "external",
    detail: "waiting",
  }
  let blocked_encoded = encode_mooncode_goal_runtime_stored_event(
    codec_test_event(
      @mooncode_core.PlannerDecision(
        "event-schema-blocked",
        @mooncode_core.Blocked(blocked_reason, ["retry"], Some("approval")),
      ),
      1L,
    ),
  )
  let reject = fn(base : String, mutated : String) raise {
    assert_true(mutated != base)
    codec_assert_event_decode_rejects(mutated)
  }
  let mutate = fn(base : String, old : String, new : String) raise {
    reject(base, base.replace(old~, new~))
  }

  mutate(
    continue_encoded, "\"kind\":\"mooncode.goal.runtime.event.v1\"", "\"kind\":\"mooncode.goal.runtime.event.v2\"",
  )
  mutate(
    continue_encoded, "\"protocol\":\"mooncode.v1\"", "\"protocol\":\"mooncode.v2\"",
  )
  mutate(
    continue_encoded, "\"contract\":\"mooncode-goal-runtime.v1\"", "\"contract\":\"mooncode-goal-runtime.v2\"",
  )
  let digest = decode_mooncode_goal_runtime_stored_event(continue_encoded).semantic_digest
  for
    bad_digest in [
      "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", "gggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggg",
      "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
    ] {
    mutate(continue_encoded, digest, bad_digest)
  }
  mutate(continue_encoded, ",\"recorded_at\":1", "")
  mutate(
    continue_encoded, "{\"id\":\"event-schema\",", "{\"id\":\"event-schema\",\"extra\":true,",
  )
  mutate(
    continue_encoded, "\"payload\":{\"type\":\"planner_decision\",\"decision\":{\"type\":\"continue\"",
    "\"payload\":{\"type\":\"unknown\",\"decision\":{\"type\":\"continue\"",
  )
  mutate(
    continue_encoded, "\"payload\":{\"type\":\"planner_decision\",\"decision\":{\"type\":\"continue\"",
    "\"payload\":{\"type\":\"cancelled\",\"decision\":{\"type\":\"continue\"",
  )
  mutate(
    continue_encoded, "\"payload\":{\"type\":\"planner_decision\"", "\"payload\":{\"type\":\"planner_decision\",\"extra\":true",
  )
  mutate(
    continue_encoded, "\"decision\":{\"type\":\"continue\"", "\"decision\":{\"type\":\"continue\",\"extra\":true",
  )
  mutate(
    continue_encoded, "\"operations\":[{\"operation_id\":\"op-1\"", "\"operations\":[{\"operation_id\":\"op-1\",\"extra\":true",
  )
  mutate(
    continue_encoded, "\"policy\":{\"max_output_bytes\":1", "\"policy\":{\"max_output_bytes\":1,\"extra\":true",
  )
  mutate(
    achieved_encoded, "\"evidence\":[{\"criterion\":\"criterion-1\"", "\"evidence\":[{\"criterion\":\"criterion-1\",\"extra\":true",
  )
  mutate(
    blocked_encoded, "\"reason\":{\"code\":\"external\",\"detail\":\"waiting\"",
    "\"reason\":{\"code\":\"external\",\"detail\":\"waiting\",\"extra\":true",
  )
  mutate(
    continue_encoded, "{\"id\":\"event-schema\",", "{\"id\":\"event-schema\",\"max_turns\":1,",
  )
  mutate(
    continue_encoded, "\"payload\":{\"type\":\"planner_decision\"", "\"payload\":{\"type\":\"planner_decision\",\"max_steps\":1",
  )
  mutate(
    continue_encoded, "\"decision\":{\"type\":\"continue\"", "\"decision\":{\"type\":\"continue\",\"token_budget\":1",
  )
  mutate(
    continue_encoded, "\"operations\":[{\"operation_id\":\"op-1\"", "\"operations\":[{\"operation_id\":\"op-1\",\"max_iterations\":1",
  )
  mutate(
    continue_encoded, "\"policy\":{\"max_output_bytes\":1", "\"policy\":{\"max_output_bytes\":1,\"max_operations\":1",
  )
  mutate(
    achieved_encoded, "\"evidence\":[{\"criterion\":\"criterion-1\"", "\"evidence\":[{\"criterion\":\"criterion-1\",\"deadline\":1",
  )
  mutate(
    blocked_encoded, "\"reason\":{\"code\":\"external\",\"detail\":\"waiting\"",
    "\"reason\":{\"code\":\"external\",\"detail\":\"waiting\",\"max_loc\":1",
  )

  assert_eq(
    encode_mooncode_goal_runtime_stored_event(
      decode_mooncode_goal_runtime_stored_event(continue_encoded),
    ),
    continue_encoded,
  )
}

///|
test "construct and encode genesis" {
  let genesis = new_mooncode_goal_runtime_genesis(
    "session-1",
    "goal-1",
    "ship codec",
    [{ id: "criterion-1", criterion: "tests pass" }],
    10L,
  )
  let encoded = encode_mooncode_goal_runtime_genesis(genesis)
  assert_true(encoded.contains("mooncode.goal.runtime.genesis.v1"))
  assert_eq(genesis.semantic_digest.length(), 64)
}

///|
test "encode all phases" {
  let phases : Array[@mooncode_core.GoalRuntimePhase] = [
    @mooncode_core.Queued,
    @mooncode_core.Running,
    @mooncode_core.WaitingApproval,
    @mooncode_core.RetryBackoff,
    @mooncode_core.PausedNoProgress,
    @mooncode_core.PausedExternal,
  ]
  for i, phase in phases {
    let stored = codec_test_event(
      @mooncode_core.PhaseChanged("phase-" + i.to_string(), phase),
      i.to_int64(),
    )
    assert_true(
      encode_mooncode_goal_runtime_stored_event(stored).contains(
        "phase_changed",
      ),
    )
  }
}

///|
test "encode all decisions" {
  let decisions : Array[@mooncode_core.GoalPlannerDecision] = [
    @mooncode_core.Continue([codec_test_operation()], "progress", "reason"),
    @mooncode_core.Achieved("done", [
      { criterion: "criterion-1", evidence_refs: ["proof-1"] },
    ]),
    @mooncode_core.Blocked(
      { code: "external", detail: "waiting" },
      ["alternative"],
      Some("approval"),
    ),
  ]
  for i, decision in decisions {
    let stored = codec_test_event(
      @mooncode_core.PlannerDecision("decision-" + i.to_string(), decision),
      1L,
    )
    assert_true(
      encode_mooncode_goal_runtime_stored_event(stored).contains(
        "planner_decision",
      ),
    )
  }
}

///|
test "encode all five core events and preserve supplied id" {
  let events : Array[@mooncode_core.GoalRuntimeEvent] = [
    @mooncode_core.PlannerDecision(
      "stable-0",
      @mooncode_core.Continue([codec_test_operation()], "progress", "reason"),
    ),
    @mooncode_core.OperationAccepted("stable-1", "op-1"),
    @mooncode_core.CheckpointAccepted("stable-2", "checkpoint-1"),
    @mooncode_core.PhaseChanged("stable-3", @mooncode_core.Running),
    @mooncode_core.Cancelled("stable-4", "operator"),
  ]
  for event in events {
    let stored = codec_test_event(event, 1L)
    assert_eq(stored.id, mooncode_goal_runtime_event_id(event))
    assert_eq(stored.semantic_digest.length(), 64)
  }
}

///|
test "digest ignores recorded_at but changes with semantics" {
  let event = @mooncode_core.OperationAccepted("event-1", "op-1")
  let first = codec_test_event(event, 1L)
  let later = codec_test_event(event, 999L)
  let changed = codec_test_event(
    @mooncode_core.OperationAccepted("event-1", "op-2"),
    1L,
  )
  assert_eq(first.semantic_digest, later.semantic_digest)
  assert_true(first.semantic_digest != changed.semantic_digest)
}

///|
test "logical payload contains no aggregate completion names" {
  let text = encode_mooncode_goal_runtime_stored_event(
    codec_test_event(
      @mooncode_core.PlannerDecision(
        "event-1",
        @mooncode_core.Achieved("done", [
          { criterion: "criterion-1", evidence_refs: ["proof"] },
        ]),
      ),
      1L,
    ),
  )
  assert_true(!text.contains("AchievedOutcome"))
  assert_true(!text.contains("BlockedOutcome"))
  assert_true(!text.contains("CancelledOutcome"))
}

///|
test "invalid genesis constructors reject padded duplicate and blank identity" {
  try
    new_mooncode_goal_runtime_genesis(
      " padded ",
      "goal",
      "objective",
      [{ id: "c", criterion: "ok" }],
      1L,
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("expected padded identity to raise")
  }
  try
    new_mooncode_goal_runtime_genesis(
      "",
      "goal",
      "objective",
      [{ id: "c", criterion: "ok" }],
      1L,
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("expected blank identity to raise")
  }
  try
    new_mooncode_goal_runtime_genesis(
      "session",
      "goal",
      "objective",
      [{ id: "c", criterion: "one" }, { id: "c", criterion: "two" }],
      1L,
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("expected duplicate criterion to raise")
  }
  try
    new_mooncode_goal_runtime_genesis(
      "session",
      "goal",
      "objective",
      [{ id: "c1", criterion: "same" }, { id: "c2", criterion: "same" }],
      1L,
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("expected duplicate criterion text to raise")
  }
}

///|
test "invalid planner decision raises" {
  try
    new_mooncode_goal_runtime_stored_event(
      "session",
      "goal",
      @mooncode_core.PlannerDecision(
        "event",
        @mooncode_core.Continue([], "", "reason"),
      ),
      1L,
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("expected invalid planner decision to raise")
  }
}

///|
test "logical payload omits aggregate bounds but retains local policy" {
  let text = encode_mooncode_goal_runtime_stored_event(
    codec_test_event(
      @mooncode_core.PlannerDecision(
        "event-1",
        @mooncode_core.Continue([codec_test_operation()], "progress", "reason"),
      ),
      1L,
    ),
  )
  let denied = [
    "turn_limit", "max_turns", "token_limit", "token_budget", "max_tokens", "wall_time_limit",
    "wall_time_budget", "deadline", "max_steps", "step_limit", "iteration_limit",
    "max_iterations", "operation_limit", "max_operations", "loc_limit", "max_loc",
  ]
  for key in denied {
    assert_true(!text.contains("\"" + key + "\""))
  }
  assert_true(text.contains("\"timeout_milliseconds\""))
  assert_true(text.contains("\"max_output_bytes\""))
}

///|
test "session and goal identity may match" {
  let genesis = new_mooncode_goal_runtime_genesis(
    "same",
    "same",
    "objective",
    [{ id: "c", criterion: "done" }],
    1L,
  )
  assert_eq(genesis.session_id, genesis.goal_id)
  let event = new_mooncode_goal_runtime_stored_event(
    "same",
    "same",
    @mooncode_core.OperationAccepted("e", "op"),
    1L,
  )
  assert_eq(event.session_id, event.goal_id)
}

///|
test "event detail identifiers and cancel reason reject blanks and padding" {
  let bad_events : Array[@mooncode_core.GoalRuntimeEvent] = [
    @mooncode_core.OperationAccepted("e1", ""),
    @mooncode_core.OperationAccepted("e2", " op"),
    @mooncode_core.CheckpointAccepted("e3", ""),
    @mooncode_core.CheckpointAccepted("e4", "checkpoint "),
    @mooncode_core.Cancelled("e5", "   "),
  ]
  for event in bad_events {
    try codec_test_event(event, 1L) catch {
      _ => ()
    } noraise {
      _ => fail("expected invalid event to raise")
    }
  }
}

///|
test "constructor copies mutable semantic inputs" {
  let criteria = [{ id: "c", criterion: "before" }]
  let genesis = new_mooncode_goal_runtime_genesis(
    "s", "g", "objective", criteria, 1L,
  )
  let genesis_encoding = encode_mooncode_goal_runtime_genesis(genesis)
  let genesis_digest = genesis.semantic_digest
  criteria[0] = { id: "changed", criterion: "after" }
  assert_eq(encode_mooncode_goal_runtime_genesis(genesis), genesis_encoding)
  assert_eq(genesis.semantic_digest, genesis_digest)

  let operations = [codec_test_operation()]
  let continued = codec_test_event(
    @mooncode_core.PlannerDecision(
      "continue",
      @mooncode_core.Continue(operations, "p", "r"),
    ),
    1L,
  )
  let continued_encoding = encode_mooncode_goal_runtime_stored_event(continued)
  let continued_digest = continued.semantic_digest
  operations[0] = { ..codec_test_operation(), operation_id: "changed" }
  assert_eq(
    encode_mooncode_goal_runtime_stored_event(continued),
    continued_encoding,
  )
  assert_eq(continued.semantic_digest, continued_digest)

  let evidence_refs = ["proof"]
  let achieved = codec_test_event(
    @mooncode_core.PlannerDecision(
      "achieved",
      @mooncode_core.Achieved("done", [{ criterion: "c", evidence_refs }]),
    ),
    1L,
  )
  let achieved_encoding = encode_mooncode_goal_runtime_stored_event(achieved)
  let achieved_digest = achieved.semantic_digest
  evidence_refs[0] = "changed"
  assert_eq(
    encode_mooncode_goal_runtime_stored_event(achieved),
    achieved_encoding,
  )
  assert_eq(achieved.semantic_digest, achieved_digest)

  let alternatives = ["alternative"]
  let blocked = codec_test_event(
    @mooncode_core.PlannerDecision(
      "blocked",
      @mooncode_core.Blocked(
        { code: "external", detail: "waiting" },
        alternatives,
        None,
      ),
    ),
    1L,
  )
  let blocked_encoding = encode_mooncode_goal_runtime_stored_event(blocked)
  let blocked_digest = blocked.semantic_digest
  alternatives[0] = "changed"
  assert_eq(
    encode_mooncode_goal_runtime_stored_event(blocked),
    blocked_encoding,
  )
  assert_eq(blocked.semantic_digest, blocked_digest)
}

///|
test "event digest ignores stable id and recorded_at but tracks payload" {
  let first = codec_test_event(
    @mooncode_core.OperationAccepted("stable-a", "op-1"),
    1L,
  )
  let renamed = codec_test_event(
    @mooncode_core.OperationAccepted("stable-b", "op-1"),
    999L,
  )
  let changed = codec_test_event(
    @mooncode_core.OperationAccepted("stable-c", "op-2"),
    1L,
  )
  assert_eq(first.semantic_digest, renamed.semantic_digest)
  assert_true(first.semantic_digest != changed.semantic_digest)
}

///|
test "negative genesis and event recorded_at raise" {
  let genesis_raised = try {
    ignore(
      new_mooncode_goal_runtime_genesis(
        "session-1",
        "goal-1",
        "ship codec",
        [{ id: "criterion-1", criterion: "tests pass" }],
        -1L,
      ),
    )
    false
  } catch {
    _ => true
  }
  let event_raised = try {
    ignore(
      codec_test_event(
        @mooncode_core.OperationAccepted("stable-a", "op-1"),
        -1L,
      ),
    )
    false
  } catch {
    _ => true
  }
  assert_true(genesis_raised)
  assert_true(event_raised)
}

///|
test "encoded event has exact kind protocol and contract" {
  let encoded = encode_mooncode_goal_runtime_stored_event(
    codec_test_event(@mooncode_core.OperationAccepted("stable-a", "op-1"), 1L),
  )
  assert_true(encoded.contains("\"kind\":\"mooncode.goal.runtime.event.v1\""))
  assert_true(encoded.contains("\"protocol\":\"mooncode.v1\""))
  assert_true(encoded.contains("\"contract\":\"mooncode-goal-runtime.v1\""))
}

///|
fn codec_assert_event_encode_rejects(
  value : MoonCodeGoalRuntimeStoredEvent,
) -> Unit raise {
  let rejected = try {
    ignore(encode_mooncode_goal_runtime_stored_event(value))
    false
  } catch {
    MoonCodeGoalRuntimeCodecError::Invalid(_) => true
  }
  assert_true(rejected)
}

///|
test "encoders reject forged identity and digest and preserve valid bytes" {
  let genesis = new_mooncode_goal_runtime_genesis(
    "session-1",
    "goal-1",
    "objective",
    [{ id: "criterion-1", criterion: "done" }],
    1L,
  )
  assert_eq(
    encode_mooncode_goal_runtime_genesis(genesis),
    genesis_envelope_json(genesis),
  )
  let bad_geneses = [
    { ..genesis, id: "wrong" },
    { ..genesis, semantic_digest: "short" },
    {
      ..genesis,
      semantic_digest: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
    },
    {
      ..genesis,
      semantic_digest: "gggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggg",
    },
    {
      ..genesis,
      semantic_digest: "0000000000000000000000000000000000000000000000000000000000000000",
    },
  ]
  for bad in bad_geneses {
    let rejected = try {
      ignore(encode_mooncode_goal_runtime_genesis(bad))
      false
    } catch {
      MoonCodeGoalRuntimeCodecError::Invalid(_) => true
    }
    assert_true(rejected)
  }
  let event = codec_test_event(
    @mooncode_core.OperationAccepted("event-1", "op-1"),
    1L,
  )
  assert_eq(
    encode_mooncode_goal_runtime_stored_event(event),
    event_envelope_json(event),
  )
  codec_assert_event_encode_rejects({ ..event, id: "other" })
  codec_assert_event_encode_rejects({ ..event, semantic_digest: "short" })
  codec_assert_event_encode_rejects({
    ..event,
    semantic_digest: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
  })
  codec_assert_event_encode_rejects({
    ..event,
    semantic_digest: "gggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggg",
  })
  codec_assert_event_encode_rejects({
    ..event,
    semantic_digest: "0000000000000000000000000000000000000000000000000000000000000000",
  })
  let operations = [codec_test_operation()]
  let nested = codec_test_event(
    @mooncode_core.PlannerDecision(
      "event-2",
      @mooncode_core.Continue(operations, "progress", "reason"),
    ),
    1L,
  )
  let unchanged = encode_mooncode_goal_runtime_stored_event(nested)
  operations[0] = { ..codec_test_operation(), operation_id: "mutated" }
  assert_eq(encode_mooncode_goal_runtime_stored_event(nested), unchanged)
  match nested.event {
    @mooncode_core.PlannerDecision(
      _,
      @mooncode_core.Continue(stored_operations, _, _)
    ) => {
      stored_operations[0] = {
        ..codec_test_operation(),
        operation_id: "mutated-stored",
      }
      codec_assert_event_encode_rejects(nested)
    }
    _ => assert_true(false)
  }
}

///|
fn codec_assert_genesis_decode_rejects(text : String) -> Unit raise {
  let rejected = try {
    let _ = decode_mooncode_goal_runtime_genesis(text)
    false
  } catch {
    MoonCodeGoalRuntimeCodecError::Invalid(_) => true
  }
  assert_true(rejected)
}

///|
fn codec_genesis_fixture() -> String raise {
  encode_mooncode_goal_runtime_genesis(
    new_mooncode_goal_runtime_genesis(
      "session-1",
      "goal-1",
      "Unicode 雪, quote \" slash / backslash \\",
      [{ id: "criterion-1", criterion: "accept café / \"quoted\" \\ path" }],
      4294967296L,
    ),
  )
}

///|
test "genesis decode roundtrip preserves canonical bytes and large timestamp" {
  let encoded = codec_genesis_fixture()
  let decoded = decode_mooncode_goal_runtime_genesis(encoded)
  assert_eq(decoded.recorded_at, 4294967296L)
  assert_eq(encode_mooncode_goal_runtime_genesis(decoded), encoded)
}

///|
test "genesis decoder rejects missing and aggregate keys" {
  let valid = codec_genesis_fixture()
  let fields = [
    "id", "kind", "protocol", "contract", "session_id", "goal_id", "objective", "criteria",
    "semantic_digest", "recorded_at",
  ]
  for field in fields {
    let parsed : Json = @json.parse(valid)
    guard parsed is Object(object) else { abort("fixture object") }
    object.remove(field)
    codec_assert_genesis_decode_rejects(parsed.stringify())
  }
  for
    field in [
      "max_turns", "token_budget", "deadline", "max_steps", "max_iterations", "max_operations",
      "max_loc",
    ] {
    let parsed : Json = @json.parse(valid)
    guard parsed is Object(object) else { abort("fixture object") }
    object[field] = Json::number(1.0)
    codec_assert_genesis_decode_rejects(parsed.stringify())
  }
}

///|
test "genesis decoder rejects criterion extra key and duplicate id" {
  let valid = codec_genesis_fixture()
  codec_assert_genesis_decode_rejects(
    valid.replace(
      old="\"criterion\":\"accept café / \\\"quoted\\\" \\\\ path\"",
      new="\"criterion\":\"accept café / \\\"quoted\\\" \\\\ path\",\"extra\":true",
    ),
  )
  codec_assert_genesis_decode_rejects(
    valid.replace(
      old="}]",
      new="},{\"id\":\"criterion-1\",\"criterion\":\"duplicate\"}]",
    ),
  )
}

///|
test "genesis decoder rejects malformed and mismatched digest" {
  let valid = codec_genesis_fixture()
  let digest = decode_mooncode_goal_runtime_genesis(valid).semantic_digest
  codec_assert_genesis_decode_rejects(valid.replace(old=digest, new="xyz"))
  codec_assert_genesis_decode_rejects(
    valid.replace(
      old=digest,
      new="0000000000000000000000000000000000000000000000000000000000000000",
    ),
  )
}

///|
test "genesis decoder rejects invalid recorded_at numbers" {
  let valid = codec_genesis_fixture()
  for replacement in ["-1", "1.5", "\"1\"", "9223372036854775808"] {
    codec_assert_genesis_decode_rejects(
      valid.replace(old="4294967296", new=replacement),
    )
  }
}

///|
test "genesis decoder requires exact canonical encoder bytes" {
  let genesis = new_mooncode_goal_runtime_genesis(
    "session-1",
    "goal-1",
    "ship / codec",
    [{ id: "criterion-1", criterion: "tests pass" }],
    1L,
  )
  let encoded = encode_mooncode_goal_runtime_genesis(genesis)
  let decoded = decode_mooncode_goal_runtime_genesis(encoded)
  assert_eq(encode_mooncode_goal_runtime_genesis(decoded), encoded)
  codec_assert_genesis_decode_rejects(" " + encoded)
  codec_assert_genesis_decode_rejects(encoded + "\n")
  let assert_mutation_rejected = fn(mutated : String) raise {
    assert_true(mutated != encoded)
    codec_assert_genesis_decode_rejects(mutated)
  }
  assert_mutation_rejected(
    encoded
    .replace(
      old="{\"id\":\"goal-runtime-genesis-v1\",\"kind\":",
      new="{\"kind\":\"mooncode.goal.runtime.genesis.v1\",\"id\":\"goal-runtime-genesis-v1\",\"kind\":",
    )
    .replace(
      old="\"kind\":\"mooncode.goal.runtime.genesis.v1\",\"protocol\"",
      new="\"protocol\"",
    ),
  )
  assert_mutation_rejected(
    encoded.replace(
      old="\"session_id\":\"session-1\"",
      new="\"session_id\":\"session-1\",\"session_id\":\"session-1\"",
    ),
  )
  assert_mutation_rejected(
    encoded.replace(
      old="\"criterion\":\"tests pass\"",
      new="\"criterion\":\"tests pass\",\"criterion\":\"tests pass\"",
    ),
  )
  assert_mutation_rejected(
    encoded.replace(
      old="\"session_id\":\"session-1\"",
      new="\"session_id\":\"session-1\",\"\\u0073ession_id\":\"session-1\"",
    ),
  )
  for lexical in ["1.0", "1e0", "-0"] {
    assert_mutation_rejected(
      encoded.replace(old="\"recorded_at\":1", new="\"recorded_at\":" + lexical),
    )
  }
  assert_mutation_rejected(
    encoded.replace(old="ship / codec", new="ship \\/ codec"),
  )
}

///|
test "genesis decoder accepts encoder-produced Int64 max recorded_at" {
  let genesis = new_mooncode_goal_runtime_genesis(
    "session-1",
    "goal-1",
    "ship codec",
    [{ id: "criterion-1", criterion: "tests pass" }],
    9223372036854775807L,
  )
  let encoded = encode_mooncode_goal_runtime_genesis(genesis)
  let decoded = decode_mooncode_goal_runtime_genesis(encoded)
  assert_eq(decoded.recorded_at, 9223372036854775807L)
  assert_eq(encode_mooncode_goal_runtime_genesis(decoded), encoded)
}

///|
test "checked positive int enforces exact Int carrier range" {
  let accepted : Map[String, Json] = {
    "one": @json.parse("1"),
    "maximum": @json.parse("2147483647"),
  }
  assert_eq(mooncode_goal_runtime_checked_positive_int(accepted, "one"), 1)
  assert_eq(
    mooncode_goal_runtime_checked_positive_int(accepted, "maximum"),
    2147483647,
  )
  let rejected : Array[Json] = [
    @json.parse("0"),
    @json.parse("-1"),
    @json.parse("1.5"),
    @json.parse("2147483648"),
    @json.parse("\"1\""),
    @json.parse("true"),
    @json.parse("null"),
  ]
  for value in rejected {
    let object : Map[String, Json] = { "value": value }
    let did_reject = try {
      let _ = mooncode_goal_runtime_checked_positive_int(object, "value")
      false
    } catch {
      MoonCodeGoalRuntimeCodecError::Invalid(_) => true
    }
    assert_true(did_reject)
  }
}

///|
fn codec_parse_fixture(text : String) -> Json {
  @json.parse(text) catch {
    _ => abort("invalid test fixture")
  }
}

///|
fn codec_assert_leaf_rejects(
  thunk : () -> Unit raise MoonCodeGoalRuntimeCodecError,
) -> Unit {
  thunk() catch {
    MoonCodeGoalRuntimeCodecError::Invalid(_) => return
  }
  abort("expected leaf decode rejection")
}

///|
test "accepted leaf forms" {
  for
    phase in [
      "queued", "running", "waiting_approval", "retry_backoff", "paused_no_progress",
      "paused_external",
    ] {
    ignore(
      mooncode_goal_runtime_decode_phase(
        codec_parse_fixture(phase.to_json().stringify()),
      ),
    )
  }
  let operation = mooncode_goal_runtime_decode_operation(
    codec_parse_fixture(
      "{\"operation_id\":\"op-\u2603\",\"kind\":\"sh\\\"ell\",\"input\":\"max_turns token_budget deadline max_steps max_iterations max_operations max_loc\",\"policy\":{\"max_output_bytes\":2147483647,\"timeout_milliseconds\":2}}",
    ),
  )
  assert_eq(operation.policy.max_output_bytes, 2147483647)
  assert_eq(
    operation.input,
    "max_turns token_budget deadline max_steps max_iterations max_operations max_loc",
  )
  let evidence = mooncode_goal_runtime_decode_criterion_evidence(
    codec_parse_fixture(
      "{\"criterion\":\"café\",\"evidence_refs\":[\"a\\\"b\",\"\\\\path\"]}",
    ),
  )
  assert_eq(evidence.evidence_refs.length(), 2)
  let reason = mooncode_goal_runtime_decode_blocked_reason(
    codec_parse_fixture("{\"code\":\"external\",\"detail\":\"待機\"}"),
  )
  assert_eq(reason.detail, "待機")
  assert_eq(
    mooncode_goal_runtime_decode_optional_string(codec_parse_fixture("null")),
    None,
  )
}

///|
test "rejected leaf forms" {
  let rejected = [
    "{\"max_output_bytes\":1,\"timeout_milliseconds\":2,\"extra\":0}", "{\"max_output_bytes\":1}",
    "[]", "{\"max_output_bytes\":0,\"timeout_milliseconds\":1}", "{\"max_output_bytes\":-1,\"timeout_milliseconds\":1}",
    "{\"max_output_bytes\":1.5,\"timeout_milliseconds\":1}", "{\"max_output_bytes\":\"1\",\"timeout_milliseconds\":1}",
    "{\"max_output_bytes\":2147483648,\"timeout_milliseconds\":1}",
  ]
  for text in rejected {
    codec_assert_leaf_rejects(fn() raise MoonCodeGoalRuntimeCodecError {
      ignore(mooncode_goal_runtime_decode_policy(codec_parse_fixture(text)))
    })
  }
  codec_assert_leaf_rejects(fn() raise MoonCodeGoalRuntimeCodecError {
    ignore(
      mooncode_goal_runtime_decode_phase(codec_parse_fixture("\"invalid\"")),
    )
  })
  codec_assert_leaf_rejects(fn() raise MoonCodeGoalRuntimeCodecError {
    ignore(
      mooncode_goal_runtime_decode_string_array(
        codec_parse_fixture("[\"ok\",1]"),
      ),
    )
  })
  codec_assert_leaf_rejects(fn() raise MoonCodeGoalRuntimeCodecError {
    ignore(
      mooncode_goal_runtime_decode_optional_string(codec_parse_fixture("1")),
    )
  })
  codec_assert_leaf_rejects(fn() raise MoonCodeGoalRuntimeCodecError {
    ignore(
      mooncode_goal_runtime_decode_operation(
        codec_parse_fixture(
          "{\"operation_id\":1,\"kind\":\"k\",\"input\":\"{}\",\"policy\":{\"max_output_bytes\":1,\"timeout_milliseconds\":1}}",
        ),
      ),
    )
  })
}
