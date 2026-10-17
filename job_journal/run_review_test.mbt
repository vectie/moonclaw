///|
fn review_event(
  run : String,
  job : String,
  time : Int32,
  message : String,
) -> Json {
  {
    "run_id": run.to_json(),
    "job_id": job.to_json(),
    "timestamp": time.to_json(),
    "event_type": "step.observed",
    "message": message.to_json(),
    "data": { "future": true },
    "status": { "unknown": true },
    "producer_extra": [1, 2],
  }
}

///|
fn review_export_entry(
  id : String,
  run : String,
  job : String,
  index : Int32,
  version : Int32,
) -> Json {
  let digest = "sha256:" + "a".repeat(64)
  {
    "record": {
      "id": id.to_json(),
      "run_id": run.to_json(),
      "job_id": job.to_json(),
      "artifact_type": "report",
      "logical_key": "result",
      "version": version.to_json(),
      "status": "Archived",
      "path": "/old/source.txt",
      "content_type": "text/plain",
      "metadata": { "future": true },
      "created_at": 5,
      "archived_at": 9,
      "scope": [],
      "record_extra": { "kept": true },
    },
    "record_path": "records/\{index}.json".to_json(),
    "content_path": "files/\{index}-source.txt".to_json(),
    "record_sha256": digest.to_json(),
    "content_sha256": digest.to_json(),
    "content_bytes": 3,
    "entry_extra": 42,
  }
}

///|
fn review_manifest(entries : Array[Json]) -> String {
  let json : Json = {
    "schema": "moonclaw.artifact-export.v1",
    "artifacts": entries.to_json(),
    "total_content_bytes": (entries.length() * 3).to_json(),
  }
  json.stringify()
}

///|
test "run review joins exact output revisions and chronological journal with original provenance" {
  let events = [
    review_event("run", "job", 20, "later"),
    review_event("other", "other-job", 1, "other"),
    review_event("run", "job", 10, "first"),
    review_event("run", "job", 10, "tie"),
  ]
  let entries = @job_journal.parse_journal(
    "\n" + events.map(j => j.stringify()).join("\n"),
    source="saved/events.jsonl",
  )
  let artifacts = [
    review_export_entry("v1", "run", "job", 1, 1),
    review_export_entry("other", "other", "other-job", 2, 1),
    review_export_entry("v2", "run", "job", 3, 2),
  ]
  let review = @job_journal.review_run(
    entries,
    review_manifest(artifacts),
    manifest_source="packet/manifest.json",
    run_id="run",
  )
  inspect(review.events.map(e => e.line), content="[4, 5, 2]")
  inspect(review.artifacts.map(a => a.index), content="[1, 3]")
  inspect(
    (
      review.excluded_events,
      review.excluded_artifacts,
      review.selected_content_bytes,
    ),
    content="(1, 1, 6)",
  )
  assert_eq(review.events[0].record, events[2])
  assert_eq(review.artifacts[1].entry, artifacts[2])
  assert_eq(review.content_verification, "not_checked")
  let md = review.to_markdown()
  assert_true(md.contains("[Open exported content](files/3-source.txt)"))
  assert_true(md.contains("revision 2"))
  assert_true(md.contains("recorded") || md.contains("Recorded"))
}

///|
test "run review supports partial supplied evidence without pretending missing data never existed" {
  let manifest = review_manifest([
    review_export_entry("a", "artifact-only", "job", 1, 1),
  ])
  let only_artifact = @job_journal.review_run(
    [],
    manifest,
    manifest_source="manifest.json",
    run_id="artifact-only",
  )
  assert_eq(only_artifact.events.length(), 0)
  assert_true(
    only_artifact.notes.contains(
      "No journal events for this run were supplied.",
    ),
  )
  let entries = @job_journal.parse_journal(
    review_event("journal-only", "job", 1, "note").stringify(),
    source="events.jsonl",
  )
  let only_journal = @job_journal.review_run(
    entries,
    manifest,
    manifest_source="manifest.json",
    run_id="journal-only",
  )
  assert_eq(only_journal.artifacts.length(), 0)
  assert_true(
    only_journal.notes.contains(
      "No artifacts for this run occur in the supplied export selection.",
    ),
  )
  assert_true(
    (try? @job_journal.review_run(
      entries,
      manifest,
      manifest_source="manifest.json",
      run_id="absent",
    ))
    is Err(_),
  )
}

///|
test "run review rejects ambiguous run jobs both within journals and across exported outputs" {
  let manifest = review_manifest([
    review_export_entry("a", "run", "artifact-job", 1, 1),
  ])
  let entries = @job_journal.parse_journal(
    review_event("run", "journal-job", 1, "note").stringify(),
    source="events",
  )
  assert_true(
    (try? @job_journal.review_run(
      entries,
      manifest,
      manifest_source="manifest",
      run_id="run",
    ))
    is Err(_),
  )
  let conflicts = @job_journal.parse_journal(
    [review_event("run", "job1", 1, "a"), review_event("run", "job2", 2, "b")]
    .map(j => j.stringify())
    .join("\n"),
    source="events",
  )
  assert_true(
    (try? @job_journal.review_run(
      conflicts,
      manifest,
      manifest_source="manifest",
      run_id="run",
    ))
    is Err(_),
  )
}

///|
test "run review checks all export entries including unselected entries and refuses unsafe links" {
  let good = review_export_entry("a", "run", "job", 1, 1)
  let other = review_export_entry("b", "other", "job", 2, 1)
  guard other.as_object() is Some(fields) else { fail("fixture") }
  for
    (key, value) in [
      ("content_path", "files/2-../<bad>".to_json()),
      ("content_bytes", 0.5.to_json()),
      ("content_sha256", "sha256:invalid".to_json()),
      ("record_path", "https://bad.invalid/record".to_json()),
    ] {
    let changed = fields.copy()
    changed[key] = value
    assert_true(
      (try? @job_journal.review_run(
        [],
        review_manifest([good, changed.to_json()]),
        manifest_source="manifest",
        run_id="run",
      ))
      is Err(_),
    )
  }
  assert_true(
    (try? @job_journal.review_run(
      [],
      review_manifest([good, good]),
      manifest_source="manifest",
      run_id="run",
    ))
    is Err(_),
  )
  assert_true(
    (try? @job_journal.review_run(
      [],
      review_manifest([]),
      manifest_source="manifest",
      run_id="run",
    ))
    is Err(_),
  )
}

///|
test "run review markdown leaves only validated member links active" {
  let event = review_event(
    "run", "job", 1, "<script>alert(1)</script> [bad](https://bad.invalid)\nnext",
  )
  let entries = @job_journal.parse_journal(event.stringify(), source="<source>")
  let review = @job_journal.review_run(
    entries,
    review_manifest([review_export_entry("<output>", "run", "job", 1, 1)]),
    manifest_source="<manifest>",
    run_id="run",
  )
  let md = review.to_markdown()
  assert_true(!md.contains("<script>"))
  assert_true(!md.contains("[bad](https://bad.invalid)"))
  assert_true(md.contains("&lt;output&gt;"))
  assert_true(md.contains("[Original record](records/1.json)"))
}

///|
test "run review retains repeated evidence beyond explorer page size and validates manifest totals" {
  let repeated = Array::make(
    1001,
    review_event("run", "job", -1, "same").stringify(),
  ).join("\n")
  let entries = @job_journal.parse_journal(repeated, source="many-events")
  let entry = review_export_entry("a", "run", "job", 1, 1)
  let manifest = review_manifest([entry])
  let review = @job_journal.review_run(
    entries,
    manifest,
    manifest_source="manifest",
    run_id="run",
  )
  assert_eq(review.events.length(), 1001)
  assert_eq(review.events[1000].line, 1001)
  let invalid_total = manifest.replace(
    old="\"total_content_bytes\":3",
    new="\"total_content_bytes\":3.5",
  )
  assert_true(invalid_total != manifest)
  assert_true(
    (try? @job_journal.review_run(
      [],
      invalid_total,
      manifest_source="manifest",
      run_id="run",
    ))
    is Err(_),
  )
  let conflict = review_manifest([
    entry,
    review_export_entry("b", "run", "other-job", 2, 2),
  ])
  assert_true(
    (try? @job_journal.review_run(
      [],
      conflict,
      manifest_source="manifest",
      run_id="run",
    ))
    is Err(_),
  )
}
