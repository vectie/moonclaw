// Daemon-private JSON carrier for canonical mooncode-goal-runtime.v1 records.

///|
priv suberror MoonCodeGoalRuntimeStoreError {
  CorruptStore(String)
  IdentityConflict(String, String, String)
}

///|
priv struct MoonCodeGoalRuntimeIndexedEntry {
  sequence : Int
  semantic_digest : String
  carrier : MoonCodeGoalRuntimeCarrier
}

///|
priv struct MoonCodeGoalRuntimeIdIndexEntry {
  semantic_digest : String
  sequence : Int
}

///|
priv struct MoonCodeGoalRuntimeScan {
  cursor : Int
  genesis : MoonCodeGoalRuntimeIndexedEntry?
  events : Array[MoonCodeGoalRuntimeIndexedEntry]
  id_index : Map[String, MoonCodeGoalRuntimeIdIndexEntry]
}

///|
fn[T] mooncode_goal_runtime_store_corrupt(
  message : String,
) -> T raise MoonCodeGoalRuntimeStoreError {
  raise MoonCodeGoalRuntimeStoreError::CorruptStore(message)
}

///|
fn mooncode_goal_runtime_scan_exact_int(
  value : Json,
  field : String,
) -> Int raise MoonCodeGoalRuntimeStoreError {
  match value {
    Number(_, repr=Some(raw)) => {
      let parsed = @string.parse_int(raw) catch {
        _ => mooncode_goal_runtime_store_corrupt(field + " is not an exact Int")
      }
      if parsed <= 0 || parsed.to_string() != raw {
        mooncode_goal_runtime_store_corrupt(field + " is not an exact Int")
      }
      parsed
    }
    Number(number, repr=None) => {
      if number.is_nan() ||
        number < 1.0 ||
        number > 2147483647.0 ||
        number.floor() != number {
        mooncode_goal_runtime_store_corrupt(field + " is not an exact Int")
      }
      let parsed = number.to_int()
      if parsed <= 0 {
        mooncode_goal_runtime_store_corrupt(field + " is not an exact Int")
      }
      parsed
    }
    _ => mooncode_goal_runtime_store_corrupt(field + " is not a number")
  }
}

///|
fn mooncode_goal_runtime_scan_exact_int64(
  value : Json,
  field : String,
) -> Int64 raise MoonCodeGoalRuntimeStoreError {
  match value {
    String(raw) => {
      let parsed = @string.parse_int64(raw) catch {
        _ =>
          mooncode_goal_runtime_store_corrupt(field + " is not an exact Int64")
      }
      if parsed < 0L || parsed.to_string() != raw {
        mooncode_goal_runtime_store_corrupt(
          field + " is not an exact canonical nonnegative Int64 String",
        )
      }
      parsed
    }
    _ => mooncode_goal_runtime_store_corrupt(field + " is not a string")
  }
}

///|
fn mooncode_goal_runtime_scan_records(
  records : Array[Json],
  expected_session_id : String,
) -> MoonCodeGoalRuntimeScan raise MoonCodeGoalRuntimeStoreError {
  if !mooncode_goal_runtime_canonical(expected_session_id) {
    mooncode_goal_runtime_store_corrupt("expected session_id is not canonical")
  }
  let mut cursor = 0
  let mut genesis : MoonCodeGoalRuntimeIndexedEntry? = None
  let events : Array[MoonCodeGoalRuntimeIndexedEntry] = []
  let id_index : Map[String, MoonCodeGoalRuntimeIdIndexEntry] = {}
  for record_json in records {
    let record = match record_json {
      Object(fields) => fields
      _ =>
        mooncode_goal_runtime_store_corrupt("journal record is not an object")
    }
    let sequence = match record.get("sequence") {
      Some(value) => mooncode_goal_runtime_scan_exact_int(value, "sequence")
      None => mooncode_goal_runtime_store_corrupt("journal sequence is missing")
    }
    if sequence <= 0 || sequence != cursor + 1 {
      mooncode_goal_runtime_store_corrupt("journal sequence is not contiguous")
    }
    cursor = sequence
    let payload = match record.get("payload") {
      Some(Object(value)) => value
      _ => continue
    }
    let kind_is_reserved = match payload.get("kind") {
      Some(String(value)) => value.has_prefix("mooncode-goal-runtime-carrier.")
      _ => false
    }
    let carrier_shaped = kind_is_reserved ||
      payload.contains("logical_kind") ||
      payload.contains("semantic_digest") ||
      payload.contains("canonical_record")
    if !carrier_shaped {
      continue
    }
    let payload_kind = match payload.get("kind") {
      Some(String(value)) => value
      _ => mooncode_goal_runtime_store_corrupt("payload kind is not a string")
    }
    if !payload_kind.has_prefix("mooncode-goal-runtime-carrier.") {
      mooncode_goal_runtime_store_corrupt(
        "carrier-shaped payload kind is not reserved",
      )
    }
    let expected_outer_keys = [
      "kind", "contract_id", "session_id", "sequence", "record_id", "record_kind",
      "command_id", "client_turn_id", "recorded_at", "payload",
    ]
    if record.length() != expected_outer_keys.length() {
      mooncode_goal_runtime_store_corrupt(
        "reserved journal record has invalid schema",
      )
    }
    for key in expected_outer_keys {
      if !record.contains(key) {
        mooncode_goal_runtime_store_corrupt(
          "reserved journal record has invalid schema",
        )
      }
    }
    match record.get("kind") {
      Some(String(value)) if value ==
        @moonlib_conversation.journal_record_kind() => ()
      _ =>
        mooncode_goal_runtime_store_corrupt("reserved journal kind is invalid")
    }
    match record.get("contract_id") {
      Some(String(value)) if value ==
        @moonlib_conversation.journal_contract_id() => ()
      _ =>
        mooncode_goal_runtime_store_corrupt(
          "reserved journal contract_id is invalid",
        )
    }
    match record.get("record_kind") {
      Some(String("event")) => ()
      _ =>
        mooncode_goal_runtime_store_corrupt(
          "reserved journal record_kind is invalid",
        )
    }
    match record.get("command_id") {
      Some(String(_)) => ()
      _ =>
        mooncode_goal_runtime_store_corrupt(
          "reserved journal command_id is invalid",
        )
    }
    match record.get("client_turn_id") {
      Some(String(_)) => ()
      _ =>
        mooncode_goal_runtime_store_corrupt(
          "reserved journal client_turn_id is invalid",
        )
    }
    if payload_kind != mooncode_goal_runtime_carrier_kind_v1 {
      mooncode_goal_runtime_store_corrupt("unsupported reserved carrier kind")
    }
    let carrier_json = Json::object(payload.copy())
    let carrier = decode_mooncode_goal_runtime_carrier(carrier_json) catch {
      MoonCodeGoalRuntimeCodecError::Invalid(message) =>
        mooncode_goal_runtime_store_corrupt(
          "invalid runtime carrier: " + message,
        )
    }
    let outer_session = match record.get("session_id") {
      Some(String(value)) => value
      _ => mooncode_goal_runtime_store_corrupt("journal session_id is invalid")
    }
    if outer_session != expected_session_id {
      mooncode_goal_runtime_store_corrupt("journal session_id mismatch")
    }
    let outer_id = match record.get("record_id") {
      Some(String(value)) => value
      _ => mooncode_goal_runtime_store_corrupt("journal record_id is invalid")
    }
    if outer_id != "event:" + carrier.id {
      mooncode_goal_runtime_store_corrupt("journal record_id mismatch")
    }
    let outer_time = match record.get("recorded_at") {
      Some(value) =>
        mooncode_goal_runtime_scan_exact_int64(value, "recorded_at")
      None =>
        mooncode_goal_runtime_store_corrupt("journal recorded_at is missing")
    }
    if outer_time != carrier.recorded_at {
      mooncode_goal_runtime_store_corrupt("journal recorded_at mismatch")
    }
    let goal_id = match carrier.record {
      Genesis(value) => {
        if value.session_id != expected_session_id {
          mooncode_goal_runtime_store_corrupt(
            "decoded genesis session mismatch",
          )
        }
        value.goal_id
      }
      Event(value) => {
        if value.session_id != expected_session_id {
          mooncode_goal_runtime_store_corrupt("decoded event session mismatch")
        }
        value.goal_id
      }
    }
    match id_index.get(carrier.id) {
      Some(previous) => {
        if previous.semantic_digest != carrier.semantic_digest {
          raise MoonCodeGoalRuntimeStoreError::IdentityConflict(
            carrier.id,
            previous.semantic_digest,
            carrier.semantic_digest,
          )
        }
        continue
      }
      None =>
        id_index[carrier.id] = {
          semantic_digest: carrier.semantic_digest,
          sequence,
        }
    }
    let entry = MoonCodeGoalRuntimeIndexedEntry::{
      sequence,
      semantic_digest: carrier.semantic_digest,
      carrier,
    }
    match carrier.record {
      Genesis(_) =>
        match genesis {
          None => genesis = Some(entry)
          Some(previous) => {
            if previous.carrier.semantic_digest != carrier.semantic_digest {
              raise MoonCodeGoalRuntimeStoreError::IdentityConflict(
                carrier.id,
                previous.carrier.semantic_digest,
                carrier.semantic_digest,
              )
            }
            mooncode_goal_runtime_store_corrupt("second genesis")
          }
        }
      Event(_) =>
        match genesis {
          None => mooncode_goal_runtime_store_corrupt("event before genesis")
          Some(first) => {
            let genesis_goal = match first.carrier.record {
              Genesis(value) => value.goal_id
              Event(_) =>
                mooncode_goal_runtime_store_corrupt(
                  "indexed genesis entry is not genesis",
                )
            }
            if goal_id != genesis_goal {
              mooncode_goal_runtime_store_corrupt("event goal mismatch")
            }
            events.push(entry)
          }
        }
    }
  }
  MoonCodeGoalRuntimeScan::{ cursor, genesis, events, id_index }
}

///|
let mooncode_goal_runtime_carrier_kind_v1 = "mooncode-goal-runtime-carrier.v1"

///|
priv enum MoonCodeGoalRuntimeCarrierRecord {
  Genesis(MoonCodeGoalRuntimeStoredGenesis)
  Event(MoonCodeGoalRuntimeStoredEvent)
}

///|
priv struct MoonCodeGoalRuntimeCarrier {
  logical_kind : String
  id : String
  semantic_digest : String
  recorded_at : Int64
  canonical_record : String
  record : MoonCodeGoalRuntimeCarrierRecord
}

///|
fn mooncode_goal_runtime_carrier_from_genesis(
  canonical_record : String,
) -> MoonCodeGoalRuntimeCarrier raise MoonCodeGoalRuntimeCodecError {
  let record = decode_mooncode_goal_runtime_genesis(canonical_record)
  MoonCodeGoalRuntimeCarrier::{
    logical_kind: "genesis",
    id: record.id,
    semantic_digest: record.semantic_digest,
    recorded_at: record.recorded_at,
    canonical_record,
    record: Genesis(record),
  }
}

///|
fn mooncode_goal_runtime_carrier_from_event(
  canonical_record : String,
) -> MoonCodeGoalRuntimeCarrier raise MoonCodeGoalRuntimeCodecError {
  let record = decode_mooncode_goal_runtime_stored_event(canonical_record)
  MoonCodeGoalRuntimeCarrier::{
    logical_kind: "event",
    id: record.id,
    semantic_digest: record.semantic_digest,
    recorded_at: record.recorded_at,
    canonical_record,
    record: Event(record),
  }
}

///|
fn mooncode_goal_runtime_carrier_validate(
  carrier : MoonCodeGoalRuntimeCarrier,
) -> MoonCodeGoalRuntimeCarrier raise MoonCodeGoalRuntimeCodecError {
  let reconstructed = match carrier.record {
    Genesis(_) =>
      mooncode_goal_runtime_carrier_from_genesis(carrier.canonical_record)
    Event(_) =>
      mooncode_goal_runtime_carrier_from_event(carrier.canonical_record)
  }
  if carrier.logical_kind != reconstructed.logical_kind ||
    carrier.id != reconstructed.id ||
    carrier.semantic_digest != reconstructed.semantic_digest ||
    carrier.recorded_at != reconstructed.recorded_at {
    mooncode_goal_runtime_fail("carrier fields do not match canonical record")
  }
  reconstructed
}

///|
fn encode_mooncode_goal_runtime_carrier(
  carrier : MoonCodeGoalRuntimeCarrier,
) -> Json raise MoonCodeGoalRuntimeCodecError {
  let carrier = mooncode_goal_runtime_carrier_validate(carrier)
  {
    "kind": mooncode_goal_runtime_carrier_kind_v1,
    "logical_kind": carrier.logical_kind,
    "id": carrier.id,
    "semantic_digest": carrier.semantic_digest,
    "recorded_at": carrier.recorded_at.to_string(),
    "canonical_record": carrier.canonical_record,
  }
}

///|
fn mooncode_goal_runtime_carrier_recorded_at(
  text : String,
) -> Int64 raise MoonCodeGoalRuntimeCodecError {
  let value = @string.parse_int64(text) catch {
    _ => mooncode_goal_runtime_fail("carrier recorded_at is invalid")
  }
  if value < 0L || value.to_string() != text {
    mooncode_goal_runtime_fail("carrier recorded_at is not canonical")
  }
  value
}

///|
fn decode_mooncode_goal_runtime_carrier(
  json : Json,
) -> MoonCodeGoalRuntimeCarrier raise MoonCodeGoalRuntimeCodecError {
  let object = mooncode_goal_runtime_exact_object(
    json,
    [
      "kind", "logical_kind", "id", "semantic_digest", "recorded_at", "canonical_record",
    ],
    "goal runtime carrier",
  )
  let kind = mooncode_goal_runtime_checked_string(object, "kind")
  if kind != mooncode_goal_runtime_carrier_kind_v1 {
    mooncode_goal_runtime_fail("wrong carrier kind")
  }
  let logical_kind = mooncode_goal_runtime_checked_string(
    object, "logical_kind",
  )
  let id = mooncode_goal_runtime_checked_string(object, "id")
  let semantic_digest = mooncode_goal_runtime_checked_string(
    object, "semantic_digest",
  )
  let recorded_at = mooncode_goal_runtime_carrier_recorded_at(
    mooncode_goal_runtime_checked_string(object, "recorded_at"),
  )
  let canonical_record = mooncode_goal_runtime_checked_string(
    object, "canonical_record",
  )
  let decoded = match logical_kind {
    "genesis" => mooncode_goal_runtime_carrier_from_genesis(canonical_record)
    "event" => mooncode_goal_runtime_carrier_from_event(canonical_record)
    _ => mooncode_goal_runtime_fail("unknown carrier logical_kind")
  }
  if decoded.id != id ||
    decoded.semantic_digest != semantic_digest ||
    decoded.recorded_at != recorded_at {
    mooncode_goal_runtime_fail("carrier fields do not match canonical record")
  }
  decoded
}
