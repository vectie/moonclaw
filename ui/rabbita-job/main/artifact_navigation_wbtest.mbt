///|
fn artifact_test_update(model : Model, msg : Msg) -> Model {
  let (_, next) = update(@cmd.Emit(_ => @rabbita.none), msg, model)
  next
}

///|
fn artifact_test_result(id : String, content : String) -> LoadedArtifact {
  {
    artifact: {
      id,
      artifact_type: "analysis.report",
      logical_key: Some("Final report"),
      path: "/work/\{id}.md",
      content_type: "text/markdown",
    },
    content: Some(content),
  }
}

///|
fn artifact_test_complete(
  model : Model,
  id : String,
  content : String,
) -> Model {
  artifact_test_update(
    model,
    ArtifactLoaded(
      id,
      model.artifact_request_generation,
      Ok(artifact_test_result(id, content)),
    ),
  )
}

///|
test "artifact navigation close rejects late success and error" {
  let pending = artifact_test_update(init_model(), OpenArtifact("a"))
  let closed = artifact_test_update(pending, CloseArtifactModal)
  let late = artifact_test_complete(closed, "a", "late")
  inspect(late.artifact_modal is None, content="true")
  inspect(late.artifact_modal_loading, content="false")
  inspect(late.artifact_editor_draft, content="")
  let failed = artifact_test_update(
    late,
    ArtifactLoaded("a", pending.artifact_request_generation, Err("late")),
  )
  inspect(failed.artifact_modal_error is None, content="true")
}

///|
test "artifact navigation newer result wins reversed replies" {
  let a = artifact_test_update(init_model(), OpenArtifact("a"))
  let b = artifact_test_update(a, OpenArtifact("b"))
  let current = artifact_test_complete(b, "b", "chosen B")
  let late = artifact_test_update(
    current,
    ArtifactLoaded(
      "a",
      a.artifact_request_generation,
      Ok(artifact_test_result("a", "late A")),
    ),
  )
  inspect(late.artifact_modal.unwrap().artifact.id, content="b")
  inspect(late.artifact_editor_draft, content="chosen B")
  inspect(late.artifact_modal_error is None, content="true")
}

///|
test "artifact navigation stale responses preserve newer pending request" {
  let a = artifact_test_update(init_model(), OpenArtifact("a"))
  let b = artifact_test_update(a, OpenArtifact("b"))
  let late_success = artifact_test_update(
    b,
    ArtifactLoaded(
      "a",
      a.artifact_request_generation,
      Ok(artifact_test_result("a", "old")),
    ),
  )
  let late_error = artifact_test_update(
    late_success,
    ArtifactLoaded("a", a.artifact_request_generation, Err("old failure")),
  )
  inspect(late_error.artifact_modal_loading, content="true")
  inspect(late_error.artifact_pending_id == Some("b"), content="true")
  inspect(late_error.artifact_modal_error is None, content="true")
  let current = artifact_test_complete(late_error, "b", "B")
  inspect(current.artifact_editor_draft, content="B")
}

///|
test "artifact navigation reopening the same ID rejects its older generation" {
  let old = artifact_test_update(init_model(), OpenArtifact("a"))
  let closed = artifact_test_update(old, CloseArtifactModal)
  let reopened = artifact_test_update(closed, OpenArtifact("a"))
  inspect(
    reopened.artifact_request_generation > old.artifact_request_generation,
    content="true",
  )
  let late = artifact_test_update(
    reopened,
    ArtifactLoaded(
      "a",
      old.artifact_request_generation,
      Ok(artifact_test_result("a", "old")),
    ),
  )
  inspect(late.artifact_modal_loading, content="true")
  let current = artifact_test_complete(late, "a", "new")
  inspect(current.artifact_editor_draft, content="new")
}

///|
test "artifact navigation repeated open and retry keep current success" {
  let first = artifact_test_update(init_model(), OpenArtifact("a"))
  let repeated = artifact_test_update(first, OpenArtifact("a"))
  let failed = artifact_test_update(
    repeated,
    ArtifactLoaded(
      "a",
      repeated.artifact_request_generation,
      Err("unavailable"),
    ),
  )
  inspect(failed.artifact_modal_error == Some("unavailable"), content="true")
  let retry = artifact_test_update(failed, OpenArtifact("a"))
  inspect(retry.artifact_modal_error is None, content="true")
  let current = artifact_test_complete(retry, "a", "recovered")
  let stale_error = artifact_test_update(
    current,
    ArtifactLoaded("a", first.artifact_request_generation, Err("old error")),
  )
  inspect(stale_error.artifact_editor_draft, content="recovered")
  inspect(stale_error.artifact_modal_error is None, content="true")
}

///|
test "artifact navigation preserves selected artifact metadata and clears previous heading" {
  let loaded_a = artifact_test_complete(
    artifact_test_update(init_model(), OpenArtifact("a")),
    "a",
    "A",
  )
  let pending_b = artifact_test_update(loaded_a, OpenArtifact("b"))
  inspect(pending_b.artifact_modal is None, content="true")
  inspect(pending_b.artifact_editor_draft, content="")
  let current = artifact_test_complete(pending_b, "b", "B")
  let artifact = current.artifact_modal.unwrap().artifact
  inspect(artifact.id, content="b")
  inspect(artifact.artifact_type, content="analysis.report")
  inspect(artifact.logical_key == Some("Final report"), content="true")
  inspect(artifact.path, content="/work/b.md")
  inspect(artifact.content_type, content="text/markdown")
}

///|
test "artifact navigation rejects mismatched returned identity and allows retry" {
  let a = artifact_test_update(init_model(), OpenArtifact("a"))
  let mismatch = artifact_test_update(
    a,
    ArtifactLoaded(
      "a",
      a.artifact_request_generation,
      Ok(artifact_test_result("b", "wrong")),
    ),
  )
  inspect(mismatch.artifact_modal is None, content="true")
  inspect(mismatch.artifact_modal_error is Some(_), content="true")
  inspect(mismatch.artifact_modal_loading, content="false")
  let retry = artifact_test_update(mismatch, OpenArtifact("a"))
  inspect(
    artifact_test_complete(retry, "a", "right").artifact_editor_draft,
    content="right",
  )
}

///|
test "artifact navigation run and route changes invalidate pending results" {
  let initial = {
    ..init_model(),
    route: Run("run-1"),
    selected_run_id: Some("run-1"),
  }
  let pending = artifact_test_update(initial, OpenArtifact("a"))
  let navigations = [
    SelectRun("run-2"),
    LoadRun("run-2"),
    UrlChanged(@url.parse("http://localhost/ui#/jobs")),
    UrlChanged(@url.parse("http://localhost/ui#/acp")),
    UrlChanged(@url.parse("http://localhost/ui#/cowork?session=s2")),
    UrlChanged(@url.parse("http://localhost/ui#/runs/run-2")),
  ]
  for navigation in navigations {
    let moved = artifact_test_update(pending, navigation)
    let late = artifact_test_complete(moved, "a", "old run")
    assert_true(late.artifact_modal is None)
    assert_false(late.artifact_modal_loading)
    assert_true(late.artifact_pending_id is None)
  }
}

///|
test "artifact navigation session and workspace changes invalidate pending results" {
  let workspace : UiWorkspaceSnapshot = {
    root: "/book/a",
    configured_from: "test",
    files: [],
    prompt_context: "",
  }
  let initial = {
    ..init_model(),
    route: Cowork,
    selected_cowork_session_key: Some("s1"),
    cowork_workspace_snapshot: Some(workspace),
  }
  let pending = artifact_test_update(initial, OpenArtifact("a"))
  for
    navigation in [
      SelectCoworkSession("s2"),
      LoadCoworkSession("s2"),
      CoworkWorkspaceLoaded(Ok({ ..workspace, root: "/book/b", })),
    ] {
    let moved = artifact_test_update(pending, navigation)
    let late = artifact_test_complete(moved, "a", "old workspace")
    assert_true(late.artifact_modal is None)
    assert_true(late.artifact_pending_id is None)
  }
  let refreshed = artifact_test_update(
    pending,
    CoworkWorkspaceLoaded(Ok(workspace)),
  )
  inspect(
    artifact_test_complete(refreshed, "a", "current").artifact_editor_draft,
    content="current",
  )
}

///|
test "artifact navigation report focus shares request generations and survives URL sync" {
  let result = artifact_test_result("report", "report content")
  let snapshot = {
    ..test_canvas_snapshot([]),
    artifacts: [result.artifact],
    nodes: [
      {
        id: "report-node",
        parent_id: None,
        kind: "Artifact",
        title: "Report",
        status: "Active",
        summary: None,
        detail: None,
        run_id: Some("run-1"),
        step_id: None,
        artifact_id: Some("report"),
        memory_id: None,
        metadata: Json::empty_object(),
        provisional: false,
      },
    ],
  }
  let initial = {
    ..init_model(),
    route: Run("run-1"),
    selected_run_id: Some("run-1"),
    snapshot: Some(snapshot),
  }
  let old = artifact_test_update(initial, OpenArtifact("old"))
  let focused = artifact_test_update(old, FocusNode("report-node"))
  inspect(focused.artifact_pending_id == Some("report"), content="true")
  inspect(
    focused.artifact_request_generation > old.artifact_request_generation,
    content="true",
  )
  let synced = artifact_test_update(
    focused,
    UrlChanged(
      @url.parse(
        "http://localhost/ui#/runs/run-1?focus=report-node&panel=artifacts",
      ),
    ),
  )
  let current = artifact_test_complete(synced, "report", "report content")
  inspect(current.artifact_editor_draft, content="report content")
}

///|
test "artifact navigation duplicate current response cannot overwrite local draft" {
  let pending = artifact_test_update(init_model(), OpenArtifact("a"))
  let current = artifact_test_complete(pending, "a", "original")
  let edited = artifact_test_update(current, SetArtifactEditorDraft("my edit"))
  inspect(
    artifact_test_complete(edited, "a", "duplicate").artifact_editor_draft,
    content="my edit",
  )
}

///|
test "artifact navigation route page parsing retains integer and invalid fallback semantics" {
  for
    (page, expected) in [
      ("12", 12),
      ("0", 0),
      ("-1", -1),
      ("2147483647", 2147483647),
      ("-2147483648", -2147483648),
      ("2147483648", 0),
      ("-2147483649", 0),
      ("bad", 0),
      ("", 0),
    ] {
    let next = artifact_test_update(
      init_model(),
      UrlChanged(@url.parse("http://localhost/ui#/jobs?page=\{page}")),
    )
    assert_eq(next.runs_page, expected)
  }
  let absent = artifact_test_update(
    init_model(),
    UrlChanged(@url.parse("http://localhost/ui#/jobs")),
  )
  inspect(absent.runs_page, content="0")
}
