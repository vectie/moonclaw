// Daemon-private JSON carrier for canonical mooncode-goal-runtime.v1 records.

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
