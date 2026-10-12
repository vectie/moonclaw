///|
test "text artifact decoder supports current Option wire shape and plain string compatibility" {
  for
    (wire, expected) in [
      (Json::string("text\u0000世界"), Some("text\u0000世界")),
      ((["text\u0000世界"] : Json), Some("text\u0000世界")),
      (Json::null(), None),
      (([] : Json), None),
    ] {
    let payload : Json = {
      "artifact": {
        "id": "text-exact",
        "artifact_type": "text-report",
        "path": "/retained/content.txt",
        "content_type": "text/plain",
      },
      "content": wire,
    }
    let result = parse_loaded_artifact_payload(payload)
    guard result is Ok(loaded) else {
      fail("Valid artifact payload must decode")
    }
    assert_eq(loaded.content, expected)
  }
}

///|
test "artifact cards expose download for binary and text and keep text open" {
  let dispatch = @cmd.Emit(_ => @rabbita.none)
  let text = artifact_test_result("text-artifact", "retained text").artifact
  let binary = {
    ..text,
    id: "binary-artifact",
    content_type: "application/pdf",
    path: "/work/报告.pdf",
  }
  let text_html = @rabbita.render_to_string(
    @rabbita.static_cell(render_artifact_card(dispatch, text)),
  )
  let binary_html = @rabbita.render_to_string(
    @rabbita.static_cell(render_artifact_card(dispatch, binary)),
  )
  assert_true(text_html.contains("Download"))
  assert_true(text_html.contains("artifact-card-button"))
  assert_true(binary_html.contains("Download"))
  assert_false(binary_html.contains("artifact-card-button"))
  let synthetic = { ..text, id: "synthetic:run-1:report", }
  let preview = @rabbita.render_to_string(
    @rabbita.static_cell(render_artifact_card(dispatch, synthetic)),
  )
  assert_true(preview.contains("download requires a retained artifact"))
  assert_false(preview.contains(">Download<"))
}

///|
test "download state deduplicates pending clicks and rejects old completion after cancel navigation and retry" {
  let artifact = artifact_test_result("artifact-one", "text").artifact
  let snapshot = { ..test_canvas_snapshot([]), artifacts: [artifact], }
  let model = {
    ..init_model(),
    route: Run("run-1"),
    selected_run_id: Some("run-1"),
    snapshot: Some(snapshot),
  }
  let pending = artifact_test_update(model, DownloadArtifact("artifact-one"))
  assert_eq(pending.artifact_download_pending, Some("artifact-one"))
  let stale_snapshot = artifact_test_update(
    { ..model, route: Run("run-2"), selected_run_id: Some("run-2"), },
    DownloadArtifact("artifact-one"),
  )
  assert_true(stale_snapshot.artifact_download_pending is None)
  let repeated = artifact_test_update(pending, DownloadArtifact("artifact-one"))
  assert_eq(
    repeated.artifact_download_generation,
    pending.artifact_download_generation,
  )
  let cancelled = artifact_test_update(pending, CancelArtifactDownload)
  let late = artifact_test_update(
    cancelled,
    ArtifactDownloadFinished(
      pending.artifact_download_generation,
      Ok("late success"),
    ),
  )
  assert_eq(late.artifact_download_notice, cancelled.artifact_download_notice)
  let retried = artifact_test_update(
    cancelled,
    DownloadArtifact("artifact-one"),
  )
  assert_true(
    retried.artifact_download_generation > pending.artifact_download_generation,
  )
  let stale = artifact_test_update(
    retried,
    ArtifactDownloadFinished(
      pending.artifact_download_generation,
      Err("old error"),
    ),
  )
  assert_eq(stale.artifact_download_pending, Some("artifact-one"))
  let navigated = artifact_test_update(retried, SelectRun("run-2"))
  assert_true(navigated.artifact_download_pending is None)
  let late = artifact_test_update(
    navigated,
    ArtifactDownloadFinished(
      retried.artifact_download_generation,
      Ok("old run"),
    ),
  )
  assert_true(late.artifact_download_notice is None)
}

///|
test "gateway owned dispatch drops old reads on token and gateway changes" {
  let _ = init_model()
  let delivered : Array[Msg] = []
  let dispatch = gateway_owned_dispatch(
    @cmd.Emit(msg => {
      delivered.push(msg)
      @rabbita.none
    }),
  )
  ignore(dispatch(RunsLoaded(Ok([]))))
  assert_eq(delivered.length(), 1)
  clear_gateway_token()
  ignore(dispatch(RunsLoaded(Err("stale error"))))
  assert_eq(delivered.length(), 1)
  let next = gateway_owned_dispatch(
    @cmd.Emit(msg => {
      delivered.push(msg)
      @rabbita.none
    }),
  )
  configure_gateway_transport("http://127.0.0.1:18124")
  ignore(next(RunsLoaded(Ok([]))))
  assert_eq(delivered.length(), 1)
}
