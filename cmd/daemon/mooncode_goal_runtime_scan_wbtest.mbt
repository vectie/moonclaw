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
) -> Json raise {
  let record = @moonlib_conversation.journal_record(
    session_id="session-你好",
    sequence~,
    record_id="event:" + carrier.id,
    record_kind="event",
    command_id="",
    client_turn_id="",
    recorded_at=carrier.recorded_at.to_string().to_json(),
    payload=encode_mooncode_goal_runtime_carrier(carrier),
  )
  @json.parse(record.stringify())
}

///|
fn scan_test_record_v2(
  carrier : MoonCodeGoalRuntimeCarrier,
  sequence : String,
) -> Json raise {
  let parsed = MoonCodeJournalSequence::parse(sequence)
  let record = mooncode_journal_record_v2(
    session_id="session-你好",
    sequence=parsed,
    record_id="event:" + carrier.id,
    record_kind="event",
    command_id="",
    client_turn_id="",
    recorded_at=carrier.recorded_at.to_string().to_json(),
    payload=encode_mooncode_goal_runtime_carrier(carrier),
  )
  @json.parse(record.stringify())
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
    CorruptStore(_) => true
    IdentityConflict(_, _, _) => false
  }
}

///|
test "valid canonical genesis envelope scans and retains canonical bytes" {
  let carrier = scan_test_carrier()
  let scan = mooncode_goal_runtime_scan_records(
    [scan_test_record(carrier, 1)],
    "session-你好",
  )
  assert_eq(scan.cursor.text(), "1")
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
  assert_eq(scan.cursor.text(), "1")
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

///|
test "v2 arbitrary-decimal sequence one scans" {
  let carrier = scan_test_carrier()
  let scan = mooncode_goal_runtime_scan_records(
    [scan_test_record_v2(carrier, "1")],
    "session-你好",
  )
  assert_eq(scan.cursor.text(), "1")
}

///|
test "mixed v1 and v2 contiguous stable identity is idempotent" {
  let carrier = scan_test_carrier()
  let scan = mooncode_goal_runtime_scan_records(
    [
      scan_test_record(carrier, 1),
      scan_test_record_v2(carrier, "2"),
      scan_test_record(carrier, 3),
    ],
    "session-你好",
  )
  assert_eq(scan.cursor.text(), "3")
}

///|
test "mixed v1 and v2 reject gaps and duplicates" {
  let carrier = scan_test_carrier()
  assert_true(
    scan_test_corrupt([
      scan_test_record(carrier, 1),
      scan_test_record_v2(carrier, "3"),
    ]),
  )
  assert_true(
    scan_test_corrupt([
      scan_test_record(carrier, 1),
      scan_test_record_v2(carrier, "1"),
    ]),
  )
}

///|
test "sequence JSON type must match journal contract" {
  let carrier = scan_test_carrier()
  let v1 = scan_test_copy_object(scan_test_record(carrier, 1))
  v1["sequence"] = "1".to_json()
  assert_true(scan_test_corrupt([Json::object(v1)]))
  let second_fields = scan_test_copy_object(scan_test_record_v2(carrier, "1"))
  second_fields["sequence"] = Json::number(1.0)
  assert_true(scan_test_corrupt([Json::object(second_fields)]))
}

///|
test "contract id is required string and known even for unrelated payload" {
  let carrier = scan_test_carrier()
  let base = scan_test_record_v2(carrier, "1")
  for replacement in [None, Some(true.to_json()), Some("unknown".to_json())] {
    let fields = scan_test_copy_object(base)
    fields["payload"] = Json::object({ "unrelated": true.to_json() })
    match replacement {
      None => fields.remove("contract_id") |> ignore
      Some(value) => fields["contract_id"] = value
    }
    assert_true(scan_test_corrupt([Json::object(fields)]))
  }
}

///|
test "at least 64 contiguous same identity records have no aggregate bound" {
  let carrier = scan_test_carrier()
  let records : Array[Json] = []
  records.push(scan_test_record(carrier, 1))
  for sequence = 2; sequence <= 64; sequence = sequence + 1 {
    records.push(scan_test_record_v2(carrier, sequence.to_string()))
  }
  let scan = mooncode_goal_runtime_scan_records(records, "session-你好")
  assert_eq(scan.cursor.text(), "64")
}

///|
test "foreign-session unrelated payload cannot advance cursor" {
  let carrier = scan_test_carrier()
  let fields = scan_test_copy_object(scan_test_record_v2(carrier, "1"))
  fields["session_id"] = "foreign-session".to_json()
  fields["payload"] = { "kind": "unrelated.event", "value": true }
  assert_true(scan_test_corrupt([Json::object(fields)]))
}
