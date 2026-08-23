// Daemon-private arbitrary-precision journal sequence and v2 envelope helpers.

///|
#warnings("-unused_value")
priv struct MoonCodeJournalSequence {
  text : String
} derive(Eq)

///|
priv struct MoonCodeJournalEnvelope {
  fields : Map[String, Json]
  contract_id : String
  sequence : MoonCodeJournalSequence
}

///|
fn MoonCodeJournalSequence::zero() -> MoonCodeJournalSequence {
  { text: "0" }
}

///|
fn MoonCodeJournalSequence::parse(
  text : String,
) -> MoonCodeJournalSequence raise MoonCodeGoalRuntimeStoreError {
  let digits = text.to_array()
  if digits.is_empty() || digits[0] < '1' || digits[0] > '9' {
    mooncode_goal_runtime_store_corrupt(
      "journal sequence is not a canonical positive decimal",
    )
  }
  for digit in digits {
    if digit < '0' || digit > '9' {
      mooncode_goal_runtime_store_corrupt(
        "journal sequence is not a canonical positive decimal",
      )
    }
  }
  { text, }
}

///|
/// Parse the scan cursor, for which zero is the initial derived value.
fn mooncode_journal_cursor_parse(
  text : String,
) -> MoonCodeJournalSequence raise MoonCodeGoalRuntimeStoreError {
  if text == "0" {
    MoonCodeJournalSequence::zero()
  } else {
    MoonCodeJournalSequence::parse(text)
  }
}

///|
/// Decode a derived cursor from either a JSON number or a JSON string. A
/// preserved numeric representation is validated exactly; a number without one
/// is canonicalized by JSON stringify for legacy numeric compatibility.
fn mooncode_journal_cursor_from_json(
  value : Json,
) -> MoonCodeJournalSequence raise MoonCodeGoalRuntimeStoreError {
  match value {
    Number(_, repr=Some(raw)) => mooncode_journal_cursor_parse(raw)
    Number(_, repr=None) as number =>
      mooncode_journal_cursor_parse(number.stringify())
    String(raw) => mooncode_journal_cursor_parse(raw)
    _ =>
      mooncode_goal_runtime_store_corrupt(
        "journal cursor is not a number or string",
      )
  }
}

///|
fn MoonCodeJournalSequence::next(
  self : MoonCodeJournalSequence,
) -> MoonCodeJournalSequence {
  if self.text == "0" {
    return { text: "1" }
  }
  let digits = self.text.to_array()
  let mut index = digits.length() - 1
  while index >= 0 && digits[index] == '9' {
    digits[index] = '0'
    index = index - 1
  }
  if index < 0 {
    let out = StringBuilder()
    out.write_char('1')
    for digit in digits {
      out.write_char(digit)
    }
    { text: out.to_string() }
  } else {
    digits[index] = (digits[index].to_int() + 1).unsafe_to_char()
    let out = StringBuilder()
    for digit in digits {
      out.write_char(digit)
    }
    { text: out.to_string() }
  }
}

///|
fn MoonCodeJournalSequence::compare(
  self : MoonCodeJournalSequence,
  other : MoonCodeJournalSequence,
) -> Int {
  if self.text.length() < other.text.length() {
    return -1
  }
  if self.text.length() > other.text.length() {
    return 1
  }
  if self.text < other.text {
    -1
  } else if self.text > other.text {
    1
  } else {
    0
  }
}

///|
fn MoonCodeJournalSequence::text(self : MoonCodeJournalSequence) -> String {
  self.text
}

///|
fn mooncode_journal_contract_id_v2() -> String {
  @mooncode_core.journal_contract_id()
}

///|
fn mooncode_journal_validate_envelope(
  record : Json,
) -> MoonCodeJournalEnvelope raise MoonCodeGoalRuntimeStoreError {
  let fields = match record {
    Object(fields) => fields
    _ => mooncode_goal_runtime_store_corrupt("journal record is not an object")
  }
  let keys = [
    "kind", "contract_id", "session_id", "sequence", "record_id", "record_kind",
    "command_id", "client_turn_id", "recorded_at", "payload",
  ]
  if fields.length() != keys.length() {
    mooncode_goal_runtime_store_corrupt(
      "journal record does not have exactly ten keys",
    )
  }
  for key in keys {
    if !fields.contains(key) {
      mooncode_goal_runtime_store_corrupt("journal record is missing " + key)
    }
  }
  match fields["kind"] {
    String(value) if value == @moonlib_conversation.journal_record_kind() => ()
    _ => mooncode_goal_runtime_store_corrupt("journal kind is invalid")
  }
  let contract_id = match fields["contract_id"] {
    String(value) => value
    _ =>
      mooncode_goal_runtime_store_corrupt("journal contract_id is not a string")
  }
  if contract_id != @moonlib_conversation.journal_contract_id() &&
    contract_id != mooncode_journal_contract_id_v2() {
    mooncode_goal_runtime_store_corrupt("unknown journal contract")
  }
  for key in ["session_id", "record_id"] {
    match fields[key] {
      String(value) if !value.is_empty() && value.trim() == value => ()
      _ =>
        mooncode_goal_runtime_store_corrupt(
          "journal " + key + " is not canonical",
        )
    }
  }
  let record_kind = match fields["record_kind"] {
    String(value) => value
    _ =>
      mooncode_goal_runtime_store_corrupt("journal record_kind is not a string")
  }
  if !@moonlib_conversation.journal_record_kinds().contains(record_kind) {
    mooncode_goal_runtime_store_corrupt("unsupported journal record_kind")
  }
  for key in ["command_id", "client_turn_id"] {
    match fields[key] {
      String(_) => ()
      _ =>
        mooncode_goal_runtime_store_corrupt(
          "journal " + key + " is not a string",
        )
    }
  }
  match fields["recorded_at"] {
    Null => mooncode_goal_runtime_store_corrupt("journal recorded_at is null")
    _ => ()
  }
  match fields["payload"] {
    Object(_) => ()
    _ => mooncode_goal_runtime_store_corrupt("journal payload is not an object")
  }
  let sequence = if contract_id == @moonlib_conversation.journal_contract_id() {
    match fields["sequence"] {
      Number(_, repr=Some(raw)) => MoonCodeJournalSequence::parse(raw)
      Number(_, repr=None) as value =>
        MoonCodeJournalSequence::parse(value.stringify())
      _ =>
        mooncode_goal_runtime_store_corrupt(
          "v1 journal sequence is not an exact durable number",
        )
    }
  } else {
    match fields["sequence"] {
      String(raw) => MoonCodeJournalSequence::parse(raw)
      _ =>
        mooncode_goal_runtime_store_corrupt(
          "v2 journal sequence is not a string",
        )
    }
  }
  { fields, contract_id, sequence }
}

///|
fn mooncode_journal_sequence_from_record(
  record : Json,
) -> MoonCodeJournalSequence raise MoonCodeGoalRuntimeStoreError {
  mooncode_journal_validate_envelope(record).sequence
}

///|
fn mooncode_journal_record_v2(
  session_id~ : String,
  sequence~ : MoonCodeJournalSequence,
  record_id~ : String,
  record_kind~ : String,
  command_id~ : String,
  client_turn_id~ : String,
  recorded_at~ : Json,
  payload~ : Json,
) -> Json raise MoonCodeGoalRuntimeStoreError {
  let sequence = MoonCodeJournalSequence::parse(sequence.text)
  let record : Json = {
    "kind": @moonlib_conversation.journal_record_kind(),
    "contract_id": mooncode_journal_contract_id_v2(),
    "session_id": session_id,
    "sequence": sequence.text,
    "record_id": record_id,
    "record_kind": record_kind,
    "command_id": command_id,
    "client_turn_id": client_turn_id,
    "recorded_at": recorded_at,
    "payload": payload,
  }
  ignore(mooncode_journal_validate_envelope(record))
  record
}
