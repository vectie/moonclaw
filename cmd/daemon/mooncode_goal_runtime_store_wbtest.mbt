///|
fn carrier_test_genesis(
  recorded_at : Int64,
) -> MoonCodeGoalRuntimeStoredGenesis raise MoonCodeGoalRuntimeCodecError {
  new_mooncode_goal_runtime_genesis(
    "session-你好",
    "goal-1",
    "objective \"quoted\"\nline",
    [{ id: "criterion-1", criterion: "done ✓" }],
    recorded_at,
  )
}

///|
fn carrier_test_event(
  event : @mooncode_core.GoalRuntimeEvent,
  recorded_at : Int64,
) -> MoonCodeGoalRuntimeStoredEvent raise MoonCodeGoalRuntimeCodecError {
  new_mooncode_goal_runtime_stored_event(
    "session-你好", "goal-1", event, recorded_at,
  )
}

///|
fn carrier_assert_rejected(json : Json) -> Unit raise {
  let rejected = try {
    ignore(decode_mooncode_goal_runtime_carrier(json))
    false
  } catch {
    Invalid(_) => true
  }
  assert_true(rejected)
}

///|
fn carrier_object_copy(json : Json) -> Map[String, Json] {
  match json {
    Object(fields) => fields.copy()
    _ => abort("expected carrier object")
  }
}

///|
fn carrier_assert_mutation_rejected(
  base : Json,
  fields : Map[String, Json],
) -> Unit raise {
  let changed = Json::object(fields)
  assert_true(changed.stringify() != base.stringify())
  carrier_assert_rejected(changed)
}

///|
fn carrier_genesis_json(
  recorded_at : Int64,
) -> Json raise MoonCodeGoalRuntimeCodecError {
  let canonical = encode_mooncode_goal_runtime_genesis(
    carrier_test_genesis(recorded_at),
  )
  encode_mooncode_goal_runtime_carrier(
    mooncode_goal_runtime_carrier_from_genesis(canonical),
  )
}

///|
test "carrier genesis roundtrip preserves exact canonical record" {
  let canonical = encode_mooncode_goal_runtime_genesis(carrier_test_genesis(7L))
  let json = encode_mooncode_goal_runtime_carrier(
    mooncode_goal_runtime_carrier_from_genesis(canonical),
  )
  let decoded = decode_mooncode_goal_runtime_carrier(json)
  assert_eq(decoded.logical_kind, "genesis")
  assert_eq(decoded.canonical_record, canonical)
}

///|
test "carrier event variants roundtrip exact canonical record" {
  let operation : @mooncode_core.GoalRuntimeOperation = {
    operation_id: "op-1",
    kind: "shell",
    input: "你好 max_turns token_budget deadline",
    policy: { max_output_bytes: 100, timeout_milliseconds: 200 },
  }
  let evidence : @mooncode_core.GoalCriterionEvidence = {
    criterion: "criterion-1",
    evidence_refs: ["proof-1"],
  }
  let reason : @mooncode_core.GoalBlockedReason = {
    code: "external",
    detail: "等待",
  }
  let events : Array[@mooncode_core.GoalRuntimeEvent] = [
    PlannerDecision(
      "event-continue",
      Continue([operation], "progress ✓", "理由"),
    ),
    PlannerDecision("event-achieved", Achieved("完成", [evidence])),
    PlannerDecision(
      "event-blocked-some",
      Blocked(reason, ["alternative"], Some("批准")),
    ),
    PlannerDecision(
      "event-blocked-none",
      Blocked(reason, ["alternative"], None),
    ),
    OperationAccepted("event-operation", "op-1"),
    CheckpointAccepted("event-checkpoint", "checkpoint-1"),
    PhaseChanged("event-queued", Queued),
    PhaseChanged("event-running", Running),
    PhaseChanged("event-waiting", WaitingApproval),
    PhaseChanged("event-retry", RetryBackoff),
    PhaseChanged("event-paused-progress", PausedNoProgress),
    PhaseChanged("event-paused-external", PausedExternal),
    Cancelled("event-cancelled", "停止"),
  ]
  for event in events {
    let canonical = encode_mooncode_goal_runtime_stored_event(
      carrier_test_event(event, 9L),
    )
    let decoded = decode_mooncode_goal_runtime_carrier(
      encode_mooncode_goal_runtime_carrier(
        mooncode_goal_runtime_carrier_from_event(canonical),
      ),
    )
    assert_eq(decoded.logical_kind, "event")
    assert_eq(decoded.canonical_record, canonical)
  }
}

///|
test "carrier genesis accepts Int64 max recorded_at" {
  let canonical = encode_mooncode_goal_runtime_genesis(
    carrier_test_genesis(9223372036854775807L),
  )
  let decoded = decode_mooncode_goal_runtime_carrier(
    encode_mooncode_goal_runtime_carrier(
      mooncode_goal_runtime_carrier_from_genesis(canonical),
    ),
  )
  assert_eq(decoded.recorded_at, 9223372036854775807L)
  assert_eq(decoded.canonical_record, canonical)
}

///|
test "carrier schema requires exactly six fields" {
  let base = carrier_genesis_json(7L)
  let required = [
    "kind", "logical_kind", "id", "semantic_digest", "recorded_at", "canonical_record",
  ]
  for key in required {
    let fields = carrier_object_copy(base)
    fields.remove(key)
    carrier_assert_mutation_rejected(base, fields)
  }
  let extras = [
    "extra", "max_turns", "token_budget", "deadline", "max_steps", "max_iterations",
    "max_operations", "max_loc",
  ]
  for key in extras {
    let fields = carrier_object_copy(base)
    fields[key] = true
    carrier_assert_mutation_rejected(base, fields)
  }
}

///|
test "carrier rejects wrong constants types and redundant fields" {
  let base = carrier_genesis_json(7L)
  let replacements : Array[(String, Json)] = [
    ("kind", "wrong-kind"),
    ("logical_kind", "unknown"),
    ("logical_kind", "event"),
    ("kind", 1),
    ("logical_kind", 1),
    ("id", 1),
    ("semantic_digest", 1),
    ("recorded_at", 1),
    ("canonical_record", 1),
    ("id", "wrong-id"),
    ("semantic_digest", "wrong-digest"),
    ("recorded_at", "8"),
  ]
  for replacement in replacements {
    let fields = carrier_object_copy(base)
    fields[replacement.0] = replacement.1
    carrier_assert_mutation_rejected(base, fields)
  }
}

///|
test "carrier recorded_at is canonical nonnegative Int64 string" {
  let base = carrier_genesis_json(1L)
  for value in ["+1", "01", "-0", "-1", " 1", "1 ", "9223372036854775808"] {
    let fields = carrier_object_copy(base)
    fields["recorded_at"] = value.to_json()
    carrier_assert_mutation_rejected(base, fields)
  }
  let fields = carrier_object_copy(base)
  fields["recorded_at"] = 1
  carrier_assert_mutation_rejected(base, fields)
}

///|
test "carrier rejects malformed and noncanonical embedded records" {
  let base = carrier_genesis_json(7L)
  let malformed = carrier_object_copy(base)
  malformed["canonical_record"] = "{"
  carrier_assert_mutation_rejected(base, malformed)
  let noncanonical = carrier_object_copy(base)
  match noncanonical["canonical_record"] {
    String(record) =>
      noncanonical["canonical_record"] = (" " + record).to_json()
    _ => abort("expected canonical record string")
  }
  carrier_assert_mutation_rejected(base, noncanonical)
}
