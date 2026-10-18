///|
async test "saved job journals explore actual producer events across runs without changing files" {
  @fsx.with_temporary_directory("journal-explorer-XXXXXX", root => {
    let store = SystemStore::new(root~)
    let parent_event : JobRunEvent = {
      run_id: "parent",
      job_id: "job",
      event_type: "step.completed",
      timestamp: 20,
      step_id: Some("prepare"),
      status: Some(Succeeded),
      message: "Prepared the local input",
      data: { "artifact_id": "artifact-1" },
    }
    let child_event : JobRunEvent = {
      run_id: "child",
      job_id: "child-job",
      event_type: "adapter.unknown",
      timestamp: 20,
      step_id: Some("dispatch"),
      status: None,
      message: "Receipt not observed",
      data: { "outcome": "unknown", "correlation_id": "attempt-1" },
    }
    store.append_run_event(parent_event)
    store.append_run_event({
      ..parent_event,
      timestamp: 10,
      event_type: "step.started",
      status: Some(Running),
    })
    store.append_run_event(child_event)
    let parent_path = store.run_events_file("parent")
    let child_path = store.run_events_file("child")
    let parent_bytes = @fsx.read_file(parent_path)
    let child_bytes = @fsx.read_file(child_path)
    let entries = @journal.parse_journal(parent_bytes, source=parent_path)
    entries.append(@journal.parse_journal(child_bytes, source=child_path))
    let page = @journal.explore_journal(entries, limit=2)
    inspect(page.total_events, content="3")
    inspect(page.matched_events, content="3")
    inspect(page.returned_events, content="2")
    debug_inspect(page.next_offset, content="Some(2)")
    debug_inspect(page.entries.map(e => e.line), content="[2, 1]")
    assert_eq(page.entries[1].record, parent_event.to_json())
    let unknown = @journal.explore_journal(entries, run_id="child")
    assert_eq(unknown.entries[0].record, child_event.to_json())
    assert_true(unknown.to_markdown().contains("Receipt not observed"))
    assert_eq(@fsx.read_file(parent_path), parent_bytes)
    assert_eq(@fsx.read_file(child_path), child_bytes)
    inspect(store.list_runs().length(), content="0")
  })
}
