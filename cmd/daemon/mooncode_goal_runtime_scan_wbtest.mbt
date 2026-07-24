///|
fn scan_test_genesis(
  recorded_at : Int64,
) -> MoonCodeGoalRuntimeStoredGenesis raise MoonCodeGoalRuntimeCodecError {
  new_mooncode_goal_runtime_genesis(
    "session-你好",
    "goal-1",
    "objective",
    [{ id: "criterion-1", criterion: "done ✓" }],
    recorded_at,
  )
}

///|
fn scan_test_carrier() -> MoonCodeGoalRuntimeCarrier raise MoonCodeGoalRuntimeCodecError {
  let genesis = scan_test_genesis(1735787045000L)
  let canonical = encode_mooncode_goal_runtime_genesis(genesis)
  mooncode_goal_runtime_carrier_from_genesis(canonical)
}

///|
fn scan_test_record(
  carrier : MoonCodeGoalRuntimeCarrier,
  sequence : Int,
) -> Json raise MoonCodeGoalRuntimeCodecError {
  @moonlib_conversation.journal_record(
    session_id="session-你好",
    sequence~,
    record_id="event:" + carrier.id,
    record_kind="event",
    command_id="",
    client_turn_id="",
    recorded_at=carrier.recorded_at.to_string().to_json(),
    payload=encode_mooncode_goal_runtime_carrier(carrier),
  )
}

///|
fn scan_test_copy_object(json : Json) -> Map[String, Json] {
  match json {
    Object(fields) => fields.copy()
    _ => abort("expected object")
  }
}

///|
fn scan_test_corrupt(records : Array[Json]) -> Bool {
  try {
    let _ = mooncode_goal_runtime_scan_records(records, "session-你好")
    false
  } catch {
    MoonCodeGoalRuntimeStoreError::CorruptStore(_) => true
    MoonCodeGoalRuntimeStoreError::IdentityConflict(_, _, _) => false
  }
}

///|
test "valid canonical genesis envelope scans and retains canonical bytes" {
  let carrier = scan_test_carrier()
  let scan = mooncode_goal_runtime_scan_records(
    [scan_test_record(carrier, 1)],
    "session-你好",
  )
  assert_eq(scan.cursor, 1)
  match scan.genesis {
    Some(entry) =>
      assert_eq(entry.carrier.canonical_record, carrier.canonical_record)
    None => abort("expected genesis")
  }
  assert_eq(scan.events.length(), 0)
}

///|
test "reserved carrier rejects wrong missing or non-string record_kind" {
  let carrier = scan_test_carrier()
  let base = scan_test_record(carrier, 1)
  for replacement in [Some("command".to_json()), None, Some(true.to_json())] {
    let fields = scan_test_copy_object(base)
    match replacement {
      Some(value) => fields["record_kind"] = value
      None => fields.remove("record_kind") |> ignore
    }
    assert_true(scan_test_corrupt([Json::object(fields)]))
  }
}

///|
test "reserved envelope rejects extra key wrong kind contract and non-string ids" {
  let carrier = scan_test_carrier()
  let base = scan_test_record(carrier, 1)
  let variants : Array[(String, Json)] = [
    ("extra", true.to_json()),
    ("kind", "wrong".to_json()),
    ("contract_id", "wrong".to_json()),
    ("command_id", true.to_json()),
    ("client_turn_id", true.to_json()),
  ]
  for variant in variants {
    let key = variant.0
    let value = variant.1
    let fields = scan_test_copy_object(base)
    fields[key] = value
    assert_true(scan_test_corrupt([Json::object(fields)]))
  }
}

///|
test "reserved envelope rejects each required outer key except payload" {
  let carrier = scan_test_carrier()
  let base = scan_test_record(carrier, 1)
  for
    key in [
      "kind", "contract_id", "session_id", "sequence", "record_id", "record_kind",
      "command_id", "client_turn_id", "recorded_at",
    ] {
    let fields = scan_test_copy_object(base)
    fields.remove(key) |> ignore
    assert_true(scan_test_corrupt([Json::object(fields)]))
  }
}

///|
test "unrelated non-prefixed payload with budget-like extras is ignored" {
  let carrier = scan_test_carrier()
  let fields = scan_test_copy_object(scan_test_record(carrier, 1))
  fields["payload"] = {
    "kind": "unrelated.event",
    "arbitrary": true,
    "max_turns": 999999,
    "token_budget": 999999,
    "max_operations": 999999,
  }
  let scan = mooncode_goal_runtime_scan_records(
    [Json::object(fields)],
    "session-你好",
  )
  assert_eq(scan.cursor, 1)
  match scan.genesis {
    Some(_) => abort("unexpected genesis")
    None => ()
  }
  assert_eq(scan.events.length(), 0)
}

///|
test "carrier-shaped payloads reject damaged inner kind" {
  let carrier = scan_test_carrier()
  let base = scan_test_record(carrier, 1)
  for
    replacement in [
      None,
      Some(true.to_json()),
      Some("unrelated.event".to_json()),
    ] {
    let outer = scan_test_copy_object(base)
    let payload = scan_test_copy_object(outer["payload"])
    match replacement {
      None => payload.remove("kind") |> ignore
      Some(value) => payload["kind"] = value
    }
    outer["payload"] = Json::object(payload)
    assert_true(scan_test_corrupt([Json::object(outer)]))
  }
}
