///|
async test "Book source actual authenticated gateway uses shipped controls and never mutates execution" {
  @fsx.with_temporary_directory("claw-book-http-XXXXXX", dir => {
    let gateway = Gateway::new(port=0, cwd=dir[:], home=dir[:], auth={
      token: Some("fixture-only-token"),
      _password: None,
    })
    defer gateway.httpx.close()
    let store = gateway.job_runtime().store()
    store.save_run({
      id: "run-book-http",
      job_id: "job-book-http",
      trigger: Manual,
      parent_run_id: None,
      parent_step_id: None,
      depth: 0,
      workspace_dir: None,
      status: Succeeded,
      attempt: 1,
      retry_of: None,
      started_at: Some(100),
      finished_at: Some(200),
      summary: Some("Synthetic completed record for read-only HTTP integration"),
      error: None,
    })
    let artifacts = @job.ArtifactStore::new(store~)
    ignore(
      artifacts.write(
        @job.ArtifactWriteRequest::new(
          run_id="run-book-http",
          job_id="job-book-http",
          artifact_type="fixture.report",
          content="\uFEFFNative gateway text 报告\u0000<&>\n",
        ),
        "book-text",
        150,
      ),
    )
    store.load()
    let before_runs = store.list_runs().to_json()
    let before_artifacts = store.list_artifacts().to_json()
    let base = "http://127.0.0.1:\{gateway.httpx.port()}"
    @async.with_task_group(group => {
      group.spawn_bg(
        () => {
          gateway.httpx.serve(
            @httpx.Handler((r, w) => gateway.handle_request(r, w)),
          )
        },
        no_wait=true,
      )
      let (code, output) = @process.collect_output_merged(
        "moon",
        [
          "test", "--target", "js", "--frozen", "main/book_outcome_surface_wbtest.mbt",
          "--index", "1",
        ],
        extra_env={ "MOONCLAW_BOOK_HTTP_URL": base },
        cwd=@os.cwd() + "/ui/rabbita-job",
      )
      assert_eq(code, 0, msg=output.text())
      assert_true(
        output.text().contains("ACTUAL_BOOK_GATEWAY_UI_PASSED"),
        msg=output.text(),
      )
      assert_eq(store.list_runs().to_json(), before_runs)
      assert_eq(store.list_artifacts().to_json(), before_artifacts)
      println("ACTUAL_BOOK_GATEWAY_UI_PASSED")
      group.return_immediately(())
    })
  })
}

///|
test "Book source errors preserve useful refusals without leaking native paths" {
  assert_eq(
    book_outcome_public_error(
      "Failure(Selected source is not valid UTF-8; no lossy conversion is allowed)",
    ),
    "Selected source is not valid UTF-8; no lossy conversion is allowed",
  )
  assert_false(
    book_outcome_public_error("IO failure /private/operator/root/secret").contains(
      "/private",
    ),
  )
}
