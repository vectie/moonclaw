///|
fn mooncode_sequence_test_parse(text : String) -> MoonCodeJournalSequence raise {
  MoonCodeJournalSequence::parse(text) catch {
    _ => fail("unexpected sequence parse failure")
  }
}

///|
fn mooncode_sequence_expect_corrupt(
  action : () -> Unit raise MoonCodeGoalRuntimeStoreError,
) -> Unit raise {
  try action() catch {
    MoonCodeGoalRuntimeStoreError::CorruptStore(_) => ()
    MoonCodeGoalRuntimeStoreError::IdentityConflict(_, _, _) =>
      fail("unexpected identity conflict")
  } noraise {
    _ => fail("expected corrupt journal data")
  }
}

///|
fn assert_json_string(value : Json, expected : String) -> Unit raise {
  match value {
    String(actual) => assert_eq(actual, expected)
    _ => fail("expected JSON string")
  }
}

///|
fn mooncode_sequence_v1_envelope(sequence : String) -> Json raise {
  @json.parse(
    "{\"kind\":\"" +
    @moonlib_conversation.journal_record_kind() +
    "\",\"contract_id\":\"" +
    @moonlib_conversation.journal_contract_id() +
    "\",\"session_id\":\"session\",\"sequence\":" +
    sequence +
    ",\"record_id\":\"record\",\"record_kind\":\"event\",\"command_id\":\"\",\"client_turn_id\":\"\",\"recorded_at\":\"now\",\"payload\":{}}",
  )
}

///|
test "journal sequence next is arbitrary precision" {
  inspect(MoonCodeJournalSequence::zero().next().text(), content="1")
  inspect(mooncode_sequence_test_parse("9").next().text(), content="10")
  inspect(mooncode_sequence_test_parse("99").next().text(), content="100")
  inspect(
    mooncode_sequence_test_parse("2147483647").next().text(),
    content="2147483648",
  )
  inspect(
    mooncode_sequence_test_parse("9223372036854775807").next().text(),
    content="9223372036854775808",
  )
  let nines = StringBuilder()
  let expected = StringBuilder()
  expected.write_char('1')
  for i = 0; i < 1000; i = i + 1 {
    nines.write_char('9')
    expected.write_char('0')
  }
  assert_eq(
    mooncode_sequence_test_parse(nines.to_string()).next().text(),
    expected.to_string(),
  )
}

///|
test "journal sequence rejects noncanonical spellings" {
  let invalid = [
    "", "0", "00", "01", "+1", "-1", " 1", "1 ", "1.0", "1e2", "１",
  ]
  for text in invalid {
    mooncode_sequence_expect_corrupt(fn() -> Unit raise MoonCodeGoalRuntimeStoreError {
      ignore(MoonCodeJournalSequence::parse(text))
    })
  }
}

///|
test "journal sequence compares by magnitude" {
  assert_eq(
    mooncode_sequence_test_parse("9").compare(
      mooncode_sequence_test_parse("10"),
    ),
    -1,
  )
  assert_eq(
    mooncode_sequence_test_parse("100").compare(
      mooncode_sequence_test_parse("99"),
    ),
    1,
  )
  assert_eq(
    mooncode_sequence_test_parse("123").compare(
      mooncode_sequence_test_parse("124"),
    ),
    -1,
  )
  assert_eq(
    mooncode_sequence_test_parse("125").compare(
      mooncode_sequence_test_parse("124"),
    ),
    1,
  )
  assert_eq(
    mooncode_sequence_test_parse("124").compare(
      mooncode_sequence_test_parse("124"),
    ),
    0,
  )
}

///|
test "journal sequence parses v1 number and v2 string far beyond Int64" {
  let huge = "92233720368547758081234567890123456789012345678901234567890"
  let v1 = mooncode_sequence_v1_envelope(huge)
  let sequence = mooncode_sequence_test_parse(huge)
  let v2 = mooncode_journal_record_v2(
    session_id="session",
    sequence~,
    record_id="record",
    record_kind="event",
    command_id="",
    client_turn_id="",
    recorded_at="now",
    payload={},
  )
  assert_eq(mooncode_journal_sequence_from_record(v1).text(), huge)
  assert_eq(mooncode_journal_sequence_from_record(v2).text(), huge)
  let wrong_v1 = match v2 {
    Object(fields) => {
      let copied = fields.copy()
      copied["contract_id"] = @moonlib_conversation.journal_contract_id().to_json()
      Json::object(copied)
    }
    _ => abort("expected object")
  }
  let wrong_v2 = match v1 {
    Object(fields) => {
      let copied = fields.copy()
      copied["contract_id"] = mooncode_journal_contract_id_v2().to_json()
      Json::object(copied)
    }
    _ => abort("expected object")
  }
  let unknown = match v2 {
    Object(fields) => {
      let copied = fields.copy()
      copied["contract_id"] = "unknown".to_json()
      Json::object(copied)
    }
    _ => abort("expected object")
  }
  mooncode_sequence_expect_corrupt(fn() -> Unit raise MoonCodeGoalRuntimeStoreError {
    ignore(mooncode_journal_sequence_from_record(wrong_v1))
  })
  mooncode_sequence_expect_corrupt(fn() -> Unit raise MoonCodeGoalRuntimeStoreError {
    ignore(mooncode_journal_sequence_from_record(wrong_v2))
  })
  mooncode_sequence_expect_corrupt(fn() -> Unit raise MoonCodeGoalRuntimeStoreError {
    ignore(mooncode_journal_sequence_from_record(unknown))
  })
}

///|
test "v2 journal record has exact ten-key projection" {
  let sequence_text = "9999999999999999999999999999999999999999"
  let record = mooncode_journal_record_v2(
    session_id="session",
    sequence=mooncode_sequence_test_parse(sequence_text),
    record_id="record",
    record_kind="event",
    command_id="command",
    client_turn_id="client",
    recorded_at="now",
    payload={ "value": true, "operation": "opaque and allowed" },
  )
  let fields = match record {
    Object(fields) => fields
    _ => fail("record is not object")
  }
  assert_eq(fields.length(), 10)
  assert_json_string(
    fields["kind"],
    @moonlib_conversation.journal_record_kind(),
  )
  assert_json_string(fields["contract_id"], mooncode_journal_contract_id_v2())
  assert_json_string(fields["session_id"], "session")
  assert_json_string(fields["sequence"], sequence_text)
  assert_json_string(fields["record_id"], "record")
  assert_json_string(fields["record_kind"], "event")
  assert_json_string(fields["command_id"], "command")
  assert_json_string(fields["client_turn_id"], "client")
  assert_json_string(fields["recorded_at"], "now")
  match fields["payload"] {
    Object(payload) => {
      assert_eq(payload["value"], true.to_json())
      assert_json_string(payload["operation"], "opaque and allowed")
    }
    _ => fail("payload is not object")
  }
  let forbidden = [
    "token_budget", "max_tokens", "max_turns", "turn_limit", "max_steps", "step_limit",
    "max_retries", "retry_limit", "max_operations", "operation_limit", "deadline",
    "elapsed_limit", "max_output_total",
  ]
  for key in forbidden {
    assert_eq(fields.contains(key), false)
  }
}
