///|
async test "human revisions actual authenticated editor durable store fresh process exact download" {
  @fsx.with_temporary_directory("human-revision-http-XXXXXX", dir => {
    let gateway = Gateway::new(port=0, cwd=dir[:], home=dir[:], auth={
      token: Some("fixture-only-token"),
      _password: None,
    })
    defer gateway.httpx.close()
    let store = gateway.job_runtime().store()
    store.save_run({
      id: "run-human",
      job_id: "job-human",
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
      summary: Some("Human revision fixture"),
      error: None,
    })
    let artifacts = @job.ArtifactStore::new(store~)
    let original = artifacts.write(
      @job.ArtifactWriteRequest::new(
        run_id="run-human",
        job_id="job-human",
        artifact_type="report",
        content="Original source 报告\u0000\n",
      ),
      "source-human",
      150,
    )
    ignore(
      artifacts.write(
        @job.ArtifactWriteRequest::new(
          run_id="run-human",
          job_id="job-human",
          artifact_type="binary",
          content_type="application/pdf",
          content="pdf",
        ),
        "binary-human",
        151,
      ),
    )
    let runs = store.list_runs().to_json()
    let events = store.list_run_events("run-human").to_json()
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
      let dist = @os.cwd() + "/ui/rabbita-job/dist"
      let (index_response, index_body) = @http.get(base + "/ui")
      assert_eq(index_response.code, 200)
      let index = @fs.read_file(dist + "/index.html").text()
      assert_eq(index_body.text(), index)
      let entries = index.split("src=\"/assets/").collect()
      guard entries.length() == 2 else { fail("Production entry is required") }
      let entry = entries[1].split("\"").next().unwrap().to_owned()
      let (entry_response, entry_body) = @http.get(base + "/assets/" + entry)
      assert_eq(entry_response.code, 200)
      let served = StringBuilder()
      for asset in @fs.readdir(dist + "/assets", sort=true) {
        if !asset.has_suffix(".js") {
          continue
        }
        if asset.has_prefix("_rabbita_main-entry-") {
          assert_true(entry_body.text().contains(asset))
        }
        let (response, body) = @http.get(base + "/assets/" + asset)
        assert_eq(response.code, 200)
        assert_eq(
          body.binary(),
          @fs.read_file(dist + "/assets/" + asset).binary(),
        )
        served.write_string(body.text())
      }
      assert_true(served.to_string().contains("Save human-revised copy"))
      assert_true(served.to_string().contains("/human-revisions"))
      assert_true(served.to_string().contains("expected_parent_digest"))
      println("DEFAULT_GATEWAY_HUMAN_DIST_PASSED")
      let (code, output) = @process.collect_output_merged(
        "moon",
        [
          "test", "--target", "js", "--frozen", "main/human_revision_wbtest.mbt",
          "--index", "1",
        ],
        extra_env={ "MOONCLAW_HUMAN_HTTP_URL": base },
        cwd=@os.cwd() + "/ui/rabbita-job",
      )
      assert_eq(code, 0, msg=output.text())
      assert_true(
        output.text().contains("ACTUAL_HUMAN_GATEWAY_UI_PASSED"),
        msg=output.text(),
      )
      assert_eq(store.list_runs().to_json(), runs)
      assert_eq(store.list_run_events("run-human").to_json(), events)
      assert_eq(
        artifacts.get("source-human").unwrap().to_json(),
        original.to_json(),
      )
      assert_eq(artifacts.list().length(), 3)
      let saved = artifacts
        .list()
        .filter(a => a.artifact_type == "human_revision")[0]
      let (fresh_code, fresh_output) = @process.collect_output_merged(
        @os.executable(),
        ["human_revision_wbtest.mbt:1-2"],
        extra_env={
          "MOONCLAW_HUMAN_REOPEN_ROOT": dir,
          "MOONCLAW_HUMAN_REOPEN_ID": saved.id,
        },
        cwd=@os.cwd(),
      )
      assert_eq(fresh_code, 0, msg=fresh_output.text())
      assert_true(
        fresh_output.text().contains("FRESH_PROCESS_HUMAN_DOWNLOAD_PASSED"),
        msg=fresh_output.text(),
      )
      println(
        "ACTUAL_HUMAN_GATEWAY_UI_PASSED + FRESH_PROCESS_HUMAN_DOWNLOAD_PASSED",
      )
      group.return_immediately(())
    })
    let anonymous = Gateway::new(port=0, cwd=dir[:], home=dir[:], auth={
      token: None,
      _password: None,
    })
    defer anonymous.httpx.close()
    @async.with_task_group(group => {
      group.spawn_bg(
        () => {
          anonymous.httpx.serve(
            @httpx.Handler((r, w) => anonymous.handle_request(r, w)),
          )
        },
        no_wait=true,
      )
      let (response, _) = @http.post(
        "http://127.0.0.1:\{anonymous.httpx.port()}/v1/jobs/runs/run-human/artifacts/source-human/human-revisions",
        "{}",
      )
      assert_eq(response.code, 401)
      group.return_immediately(())
    })
  })
}

///|
#skip("Invoked in a fresh process by the human revision HTTP fixture")
async test "fresh process reopens retained human revision and downloads exact bytes" {
  guard @os.getenv("MOONCLAW_HUMAN_REOPEN_ROOT") is Some(dir) &&
    @os.getenv("MOONCLAW_HUMAN_REOPEN_ID") is Some(id) else {
    fail("fixture required")
  }
  let gateway = Gateway::new(port=0, cwd=dir[:], home=dir[:], auth={
    token: Some("fixture-only-token"),
    _password: None,
  })
  defer gateway.httpx.close()
  let store = gateway.job_runtime().store()
  let runs = store.list_runs().to_json()
  let events = store.list_run_events("run-human").to_json()
  assert_eq(store.get_artifact(id).unwrap().artifact_type, "human_revision")
  @async.with_task_group(group => {
    group.spawn_bg(
      () => {
        gateway.httpx.serve(
          @httpx.Handler((r, w) => gateway.handle_request(r, w)),
        )
      },
      no_wait=true,
    )
    let (response, body) = @http.get(
      "http://127.0.0.1:\{gateway.httpx.port()}/v1/jobs/runs/run-human/artifacts/\{id}/download",
      headers={ "authorization": "Bearer fixture-only-token" },
    )
    assert_eq(response.code, 200)
    assert_eq(
      body.binary(),
      @encoding/utf8.encode("Human revised 世界\u0000\n"),
    )
    assert_eq(store.list_runs().to_json(), runs)
    assert_eq(store.list_run_events("run-human").to_json(), events)
    println("FRESH_PROCESS_HUMAN_DOWNLOAD_PASSED")
    group.return_immediately(())
  })
}
