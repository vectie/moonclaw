///|
fn fixture(
  run : String,
  timestamp : Int,
  message : String,
  step? : String,
) -> Json {
  let fields : Map[String, Json] = {
    "run_id": run.to_json(),
    "job_id": "job-1",
    "event_type": "step.progress",
    "timestamp": timestamp.to_json(),
    "status": "Running",
    "message": message.to_json(),
    "data": { "attempt": 2, "receipt": "local-receipt" },
    "future_field": ["retained", 42],
  }
  if step is Some(value) {
    fields["step_id"] = value.to_json()
  }
  fields.to_json()
}

///|
test "journal parses producer shape and preserves original fields and physical lines" {
  let original = fixture("run-a", 10, "Observed", step="prepare")
  let entries = @job_journal.parse_journal(
    "\n" + original.stringify() + "\r\n\n",
    source="saved/events.jsonl",
  )
  inspect(entries.length(), content="1")
  inspect(entries[0].line, content="2")
  inspect(entries[0].source, content="saved/events.jsonl")
  assert_eq(entries[0].record, original)
  let page = @job_journal.explore_journal(entries)
  inspect(page.total_events, content="1")
  inspect(page.matched_events, content="1")
  inspect(page.returned_events, content="1")
  assert_eq(page.entries[0].record, original)
}

///|
test "journal merges timestamps and retains deterministic source order for ties and duplicates" {
  let repeated = fixture("run-a", 20, "Repeated").stringify()
  let entries = @job_journal.parse_journal(
    repeated +
    "\n" +
    fixture("run-a", 5, "Earlier").stringify() +
    "\n" +
    repeated,
    source="first",
  )
  entries.append(
    @job_journal.parse_journal(
      fixture("run-b", 20, "Other run").stringify(),
      source="second",
    ),
  )
  let page = @job_journal.explore_journal(entries)
  inspect(
    page.entries.map(e => e.source + ":" + e.line.to_string()),
    content="[first:2, first:1, first:3, second:1]",
  )
  inspect(page.total_events, content="4")
  assert_eq(@job_journal.explore_journal(entries).to_json(), page.to_json())
}

///|
test "journal filters before paging with inclusive time bounds" {
  let entries = @job_journal.parse_journal(
    [
      fixture("run-a", 10, "PARSING input", step="prepare"),
      fixture("run-b", 20, "Parsing other", step="prepare"),
      fixture("run-a", 30, "Parsing result", step="prepare"),
      fixture("run-a", 40, "Finished", step="done"),
    ]
    .map(j => j.stringify())
    .join("\n"),
    source="journal",
  )
  let page = @job_journal.explore_journal(
    entries,
    run_id="run-a",
    step_id="prepare",
    event_type="step.progress",
    query="parsing",
    since=10,
    until=30,
    limit=1,
  )
  inspect(page.total_events, content="4")
  inspect(page.matched_events, content="2")
  inspect(page.returned_events, content="1")
  inspect(page.next_offset, content="Some(1)")
  inspect(page.entries[0].line, content="1")
  let second = @job_journal.explore_journal(
    entries,
    run_id="run-a",
    step_id="prepare",
    query="parsing",
    offset=1,
    limit=1,
  )
  inspect(second.entries[0].line, content="3")
  inspect(second.next_offset, content="None")
  inspect(
    @job_journal.explore_journal(entries, run_id="missing").matched_events,
    content="0",
  )
  inspect(
    @job_journal.explore_journal(entries, event_type="other").matched_events,
    content="0",
  )
  inspect(
    @job_journal.explore_journal(entries, offset=2147483647).returned_events,
    content="0",
  )
}

///|
test "journal empty inputs and exhausted pages are explicit" {
  let empty = @job_journal.explore_journal(
    @job_journal.parse_journal("\n\r\n", source="empty"),
  )
  inspect(empty.total_events, content="0")
  inspect(empty.next_offset, content="None")
  assert_true(empty.to_markdown().contains("No events on this page."))
  let entries = @job_journal.parse_journal(
    fixture("run", 1, "x").stringify(),
    source="one",
  )
  let page = @job_journal.explore_journal(entries, offset=1)
  inspect(page.matched_events, content="1")
  inspect(page.returned_events, content="0")
  inspect(page.next_offset, content="None")
}

///|
test "journal malformed records fail with source line and never echo raw data" {
  let secret = "private-fixture-marker"
  let bad = fixture("run", 1, "good").stringify() + "\n\n" + secret
  match (try? @job_journal.parse_journal(bad, source="saved")) {
    Err(error) => {
      let text = error.to_string()
      assert_true(text.contains("line 3"))
      assert_false(text.contains(secret))
    }
    Ok(_) => fail("Expected malformed JSON to fail")
  }
  assert_true((try? @job_journal.parse_journal("{}", source="saved")) is Err(_))
  assert_true((try? @job_journal.parse_journal("[]", source="saved")) is Err(_))
  let fractional = fixture("run", 1, "x")
    .stringify()
    .replace(old="\"timestamp\":1", new="\"timestamp\":1.5")
  assert_true(
    (try? @job_journal.parse_journal(fractional, source="saved")) is Err(_),
  )
}

///|
test "journal retains unrecognized status data without inferring completion" {
  let record : Json = {
    "run_id": "run",
    "job_id": "job",
    "event_type": "adapter.unknown",
    "timestamp": 1,
    "message": "Outcome unknown",
    "data": { "effect": "unknown" },
    "status": { "future": "unconfirmed" },
  }
  let page = @job_journal.explore_journal(
    @job_journal.parse_journal(record.stringify(), source="future"),
  )
  assert_eq(page.entries[0].record, record)
  assert_true(page.to_markdown().contains("Outcome unknown"))
  assert_true(
    page.to_markdown().contains("does not establish current runtime status"),
  )
}

///|
test "journal bounds and invalid pagination are rejected" {
  let entry = fixture("run", 1, "x").stringify()
  let entries = @job_journal.parse_journal(
    Array::make(10000, entry).join("\n"),
    source="max",
  )
  inspect(
    @job_journal.explore_journal(entries, offset=9999).returned_events,
    content="1",
  )
  assert_true(
    (try? @job_journal.parse_journal(
      Array::make(10001, entry).join("\n"),
      source="large",
    ))
    is Err(_),
  )
  entries.append(@job_journal.parse_journal(entry, source="extra"))
  assert_true((try? @job_journal.explore_journal(entries)) is Err(_))
  assert_true((try? @job_journal.explore_journal([], limit=0)) is Err(_))
  assert_true((try? @job_journal.explore_journal([], limit=1001)) is Err(_))
  assert_true((try? @job_journal.explore_journal([], offset=-1)) is Err(_))
  assert_true(
    (try? @job_journal.explore_journal([], since=2, until=1)) is Err(_),
  )
  assert_true((try? @job_journal.parse_journal("", source=" ")) is Err(_))
  assert_true(
    (try? @job_journal.parse_journal(" ".repeat(4194305), source="large"))
    is Err(_),
  )
}

///|
test "journal Markdown renders untrusted text and source paths inertly" {
  let entry = fixture(
    "[run](https://example.test)",
    1,
    "<script>alert(1)</script>\n# heading ![image](file:///tmp/x) & **bold**",
    step="`x`",
  )
  let page = @job_journal.explore_journal(
    @job_journal.parse_journal(entry.stringify(), source="# /tmp/[file].jsonl"),
  )
  let markdown = page.to_markdown()
  assert_false(markdown.contains("<script>"))
  assert_false(markdown.contains("\n# heading"))
  assert_false(markdown.contains("![image]("))
  assert_true(markdown.contains("&lt;script&gt;"))
  assert_true(markdown.contains("\\[run\\]\\(https://example\\.test\\)"))
  assert_true(markdown.contains("&amp;"))
}
