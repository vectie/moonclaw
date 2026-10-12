///|
test "CSV quotes multiline fields and keeps original records" {
  let original = fixture("00017", -10, "Hello, \"Moon\"\r\n雪", step="a,b")
  let csv = @job_journal.journal_csv(
    @job_journal.parse_journal(original.stringify(), source="saved,one"),
  )
  assert_true(
    csv.has_prefix("source,source_line,timestamp,run_id,job_id,step_id,"),
  )
  assert_true(csv.contains("\"saved,one\",\"1\",\"-10\",\"00017\""))
  assert_true(csv.contains("\"Hello, \"\"Moon\"\"\r\n雪\""))
  assert_true(csv.contains("\"\"future_field\"\""))
  assert_true(csv.has_suffix("\r\n"))
  assert_eq(
    @job_journal.journal_csv(
      @job_journal.parse_journal(original.stringify(), source="saved,one"),
    ),
    csv,
  )
}

///|
test "CSV selection shares explorer filters and never stops at the first page" {
  let entries = @job_journal.parse_journal(
    [
      fixture("run-a", 20, "Receipt later", step="inspect"),
      fixture("run-b", 10, "Receipt other", step="inspect"),
      fixture("run-a", 10, "RECEIPT first", step="inspect"),
      fixture("run-a", 20, "Receipt tied", step="inspect"),
    ]
    .map(j => j.stringify())
    .join("\n"),
    source="one",
  )
  let csv = @job_journal.journal_csv(
    entries,
    run_id="run-a",
    step_id="inspect",
    event_type="step.progress",
    query="receipt",
    since=10,
    until=20,
  )
  let rows = csv.split("\r\n").to_array()
  inspect(rows.length(), content="5")
  assert_true(rows[1].has_prefix("\"one\",\"3\",\"10\""))
  assert_true(rows[2].has_prefix("\"one\",\"1\",\"20\""))
  assert_true(rows[3].has_prefix("\"one\",\"4\",\"20\""))
  let repeated = @job_journal.parse_journal(
    Array::make(1001, fixture("run", 1, "x").stringify()).join("\n"),
    source="many",
  )
  inspect(
    @job_journal.journal_csv(repeated).split("\r\n").count(),
    content="1003",
  )
}

///|
test "CSV prefixes dangerous text with an explicit reversible column list" {
  let original = fixture("=run", -2, "  +SUM(1,2)", step="@step")
  let csv = @job_journal.journal_csv(
    @job_journal.parse_journal(original.stringify(), source="'saved"),
  )
  assert_true(csv.contains("\"''saved\",\"1\",\"-2\",\"'=run\""))
  assert_true(csv.contains("\"'@step\""))
  assert_true(csv.contains("\"'  +SUM(1,2)\""))
  assert_true(csv.contains("\"source;run_id;step_id;message\"\r\n"))
  for message in ["\t=1", "\r-1", "\n@x", "-1", "'original", "\u{FEFF}=1"] {
    let result = @job_journal.journal_csv(
      @job_journal.parse_journal(
        fixture("run", 1, message).stringify(),
        source="one",
      ),
    )
    assert_true(result.contains("\"message\"\r\n"))
  }
}

///|
test "CSV header-only empty selection and bounded output errors" {
  let empty = @job_journal.journal_csv([])
  inspect(empty.split("\r\n").count(), content="2")
  let optional_record : Json = {
    "run_id": "run",
    "job_id": "job",
    "timestamp": 1,
    "event_type": "recorded",
    "message": "x",
    "data": null,
    "step_id": "",
    "status": null,
  }
  let optionals = @job_journal.journal_csv(
    @job_journal.parse_journal(optional_record.stringify(), source="one"),
  )
  assert_true(optionals.contains("\"recorded\",\"null\",\"x\",\"null\""))
  let entries = @job_journal.parse_journal(
    fixture("run", 1, "x").stringify(),
    source="one",
  )
  assert_eq(@job_journal.journal_csv(entries, run_id="missing"), empty)
  try @job_journal.journal_csv(entries, since=2, until=1) catch {
    error =>
      assert_true(error.to_string().contains("Since must not exceed until"))
  } noraise {
    _ => fail("Expected invalid time range to fail")
  }
  let large = @job_journal.parse_journal(
    fixture("run", 1, "x".repeat(1000000)).stringify(),
    source="large",
  )
  let many : Array[@job_journal.JournalEntry] = []
  for _ in 0..<9 {
    many.append(large)
  }
  try @job_journal.journal_csv(many) catch {
    error =>
      assert_true(
        error.to_string().contains("CSV export exceeds 16 Mi code units"),
      )
  } noraise {
    _ => fail("Expected output budget failure")
  }
}
