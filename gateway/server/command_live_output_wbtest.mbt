///|
// Synthetic signed spool records, read only by the unchanged native Fort CLI.
// This fixture never invokes a command executor or a model provider.
fn live_fixture_hmac(value : String) -> String {
  @crypto.bytes_to_hex_string(
    @crypto.hmac(
      @crypto.SHA256::new(),
      @encoding/utf8.encode("r27-fixture-key-not-a-real-secret-0000"),
      @encoding/utf8.encode(value),
    ),
  )
}

///|
async fn write_live_fixture_record(
  root : String,
  plan : @execution_sandbox.SandboxApprovalPlan,
  bytes : Bytes,
  status : String,
  expires : Int64,
) -> String {
  let id = live_fixture_hmac(
    "moonfort.live-output.v1\napproval\n" + plan.grant.approval_id,
  )
  let size = if status == "running" { 0L } else { bytes.length().to_int64() }
  let digest = @crypto.bytes_to_hex_string(
    @crypto.sha256(if status == "running" { b"" } else { bytes }),
  )
  let signature = live_fixture_hmac(
    [
      "moonfort.live-output.v1",
      id,
      plan.grant.request_id,
      status,
      size.to_string(),
      digest,
      expires.to_string(),
      "fixture-key",
      plan.grant.approval_id,
      plan.expected_approval_digest,
    ].join("\n"),
  )
  let record : Json = {
    "reference": {
      "stream_id": id,
      "run_id": plan.grant.request_id,
      "status": status,
      "size_bytes": size,
      "sha256": digest,
      "expires_at_ms": expires,
      "key_id": "fixture-key",
      "signature": signature,
    },
    "approval_id": plan.grant.approval_id,
    "approval_digest": plan.expected_approval_digest,
  }
  @fs.write_file(
    root + "/" + id + ".json",
    record.stringify(),
    create_mode=CreateOrTruncate,
    permission=0o600,
  )
  id
}

///|
#skip("Requires a freshly built unchanged native Fort live reader and shipped UI assets")
async test "actual Fort live reader crosses authenticated gateway into shipped UI before terminal receipt" {
  guard @os.getenv("MOONFORT_R27_LIVE_READER") is Some(reader) else {
    fail("Native Fort live reader is required")
  }
  @fsx.with_temporary_directory("claw-live-native-XXXXXX", dir => {
    for
      suffix in [
        "approval", "scratch", "retention", "receipts", "retention/output-artifacts",
        "retention/live-output",
      ] {
      @fs.mkdir(dir + "/" + suffix, permission=0o700)
    }
    let config_json : Json = {
      "approval_root": dir + "/approval",
      "scratch_root": dir + "/scratch",
      "retention_root": dir + "/retention",
      "artifact_key_id": "fixture-key",
      "artifact_signing_key": "r27-fixture-key-not-a-real-secret-0000",
      "workspaces": {},
      "local_tools": {},
      "aen_backends": {},
      "limits": {
        "max_protocol_bytes": 65536,
        "max_wall_clock_ms": 5000,
        "max_cpu_seconds": 2,
        "max_memory_mib": 256,
        "max_disk_mib": 32,
        "max_processes": 32,
        "max_output_bytes": 65536,
        "max_model_output_bytes": 32768,
        "max_command_args": 16,
        "max_argument_bytes": 4096,
        "max_changed_paths": 32,
        "retention_ms": 60000L.to_json(),
      },
    }
    @fs.write_file(
      dir + "/fort-config.json",
      config_json.stringify(),
      create_mode=CreateNew,
      permission=0o600,
    )
    let config = {
      ..@execution_sandbox.local_sandbox_executor_config(
        "/usr/bin/true",
        "/usr/bin/true",
        dir + "/fort-config.json",
        dir + "/receipts",
        "fixture-workspace",
      ),
      live_output_reader_path: Some(reader),
    }
    let plan = @execution_sandbox.make_sandbox_plan(
      config, dir, dir, "fixture-only-not-executed", 1000,
    )
    @execution_sandbox.validate_approved_plan(
      plan, config, dir, dir, "fixture-only-not-executed",
    )
    @execution_sandbox.persist_command_live_binding(
      config,
      { run_id: "run-1", step_id: "step-1", },
      plan,
    )
    let expires = @clock.epoch.now().ms() + 3600000L
    let spool = dir + "/retention/live-output"
    let first_bytes = b"prefix<safe>\n\xe2\x82"
    let all_bytes = b"prefix<safe>\n\xe2\x82\xac\x00\xfftail\n"
    let id = write_live_fixture_record(
      spool, plan, first_bytes, "running", expires,
    )
    let blob = spool + "/" + id + ".blob"
    @fs.write_file(blob, first_bytes, create_mode=CreateNew, permission=0o600)
    let first = @execution_sandbox.read_bound_command_live_output(
      config,
      "run-1",
      plan.grant.request_id,
      "start",
    )
    assert_false(first.terminal)
    assert_eq(first.next_offset, first_bytes.length())
    assert_eq(first.content_base64, @base64.encode(first_bytes))
    let gateway = Gateway::new(
      port=0,
      cwd=dir[:],
      home=dir[:],
      auth={ token: Some("fixture-only-token"), _password: None, },
      command_output_config=config,
    )
    defer gateway.httpx.close()
    let store = gateway.job_runtime().store()
    store.save_definition({
      id: "job-fixture",
      kind: "job.proposal.research",
      enabled: true,
      config: {},
      schedule: None,
      retry_policy: None,
      workflow_id: None,
      created_at: 10,
      updated_at: 10,
      tags: [],
    })
    let run : @job.JobRun = {
      id: "run-1",
      job_id: "job-fixture",
      trigger: Manual,
      parent_run_id: None,
      parent_step_id: None,
      depth: 0,
      workspace_dir: Some(dir),
      status: Running,
      attempt: 1,
      retry_of: None,
      started_at: Some(20),
      finished_at: None,
      summary: None,
      error: None,
    }
    store.save_run(run)
    store.save_run({ ..run, id: "other-run", })
    store.load()
    let base = "http://127.0.0.1:\{gateway.httpx.port()}"
    let endpoint = base +
      "/v1/jobs/runs/run-1/command-outputs/" +
      plan.grant.request_id +
      "/live/"
    let headers = { "authorization": "Bearer fixture-only-token" }
    @async.with_task_group(group => {
      group.spawn_bg(
        () => {
          gateway.httpx.serve(
            @httpx.Handler((r, w) => {
              // Fixture mutation endpoint exists only in this isolated test closure.
              if r.path == "/fixture/append" &&
                r.method_ == Post &&
                gateway_http_authorized(
                  "/v1/fixture",
                  r.headers,
                  Some("fixture-only-token"),
                ) {
                let file = @fs.open(blob, mode=ReadWrite)
                file.write_at(
                  all_bytes[first_bytes.length():],
                  position=first_bytes.length().to_int64(),
                )
                file.close()
                w.write_header(204)
              } else if r.path == "/fixture/terminal" &&
                r.method_ == Post &&
                gateway_http_authorized(
                  "/v1/fixture",
                  r.headers,
                  Some("fixture-only-token"),
                ) {
                ignore(
                  write_live_fixture_record(
                    spool, plan, all_bytes, "killed", expires,
                  ),
                )
                store.save_run({
                  ..run,
                  status: Cancelled,
                  finished_at: Some(30),
                })
                w.write_header(204)
              } else {
                gateway.handle_request(r, w)
              }
            }),
          )
        },
        no_wait=true,
      )
      let (denied, _) = @http.get(endpoint + "start")
      assert_eq(denied.code, 401)
      let (snapshot_response, snapshot_body) = @http.get(
        base + "/v1/jobs/runs/run-1/ui",
        headers~,
      )
      assert_eq(snapshot_response.code, 200)
      assert_true(snapshot_body.text().contains("fort-command-live-output"))
      assert_false(snapshot_body.text().contains(plan.grant.approval_id))
      assert_false(snapshot_body.text().contains("signature"))
      // Prove the normal gateway serves the fresh tracked production bundle.
      let dist = @os.cwd() + "/ui/rabbita-job/dist"
      let (index_response, index_body) = @http.get(base + "/ui")
      assert_eq(index_response.code, 200)
      assert_eq(index_body.text(), @fs.read_file(dist + "/index.html").text())
      let entries = index_body.text().split("src=\"/assets/").collect()
      assert_eq(entries.length(), 2)
      let entry = entries[1].split("\"").next().unwrap().to_owned()
      let (entry_response, entry_body) = @http.get(base + "/assets/" + entry)
      assert_eq(entry_response.code, 200)
      let current = operator_ui_current_compiled_entry(
        entry_body.text(),
        @fs.readdir(dist + "/assets"),
      )
      let served = StringBuilder()
      for asset in @fs.readdir(dist + "/assets", sort=true) {
        if !asset.has_suffix(".js") {
          continue
        }
        let (response, body) = @http.get(base + "/assets/" + asset)
        assert_eq(response.code, 200)
        assert_eq(
          body.binary(),
          @fs.read_file(dist + "/assets/" + asset).binary(),
        )
        if asset == current || asset == entry {
          served.write_string(body.text())
        }
      }
      assert_true(served.to_string().contains("Tail live output"))
      assert_true(served.to_string().contains("Reload from cursor"))
      let (code, output) = @process.collect_output_merged(
        "moon",
        [
          "test", "--target", "js", "--frozen", "--warn-list", "-a", "main/command_live_http_wbtest.mbt",
          "--index", "0",
        ],
        extra_env={
          "MOONCLAW_HTTP_FIXTURE_URL": base,
          "MOONCLAW_LIVE_FIXTURE_OUTPUT": plan.grant.request_id,
        },
        cwd=@os.cwd() + "/ui/rabbita-job",
      )
      assert_eq(code, 0, msg=output.text())
      assert_true(
        output.text().contains("ACTUAL_FORT_LIVE_CLAW_UI_PASSED"),
        msg=output.text(),
      )
      // Recreate the gateway object from disk: no in-memory owner/cursor is required.
      let restarted = Gateway::new(
        port=0,
        cwd=dir[:],
        home=dir[:],
        auth={ token: Some("fixture-only-token"), _password: None, },
        command_output_config=config,
      )
      defer restarted.httpx.close()
      assert_true(restarted.job_runtime().store().get_run("run-1") is Some(_))
      group.spawn_bg(
        () => {
          restarted.httpx.serve(
            @httpx.Handler((r, w) => restarted.handle_request(r, w)),
          )
        },
        no_wait=true,
      )
      let (restarted_response, restarted_body) = @http.get(
        "http://127.0.0.1:\{restarted.httpx.port()}/v1/jobs/runs/run-1/command-outputs/" +
        plan.grant.request_id +
        "/live/" +
        first.next_cursor,
        headers~,
      )
      assert_eq(restarted_response.code, 200)
      let restarted_chunk : @execution_sandbox.CommandLiveChunk = @json.from_json(
        @json.parse(restarted_body.text()),
      )
      assert_eq(restarted_chunk.offset, first.next_offset)
      assert_true(restarted_chunk.terminal)
      let unauthenticated = Gateway::new(
        port=0,
        cwd=dir[:],
        home=dir[:],
        auth={ token: None, _password: None, },
        command_output_config=config,
      )
      defer unauthenticated.httpx.close()
      group.spawn_bg(
        () => {
          unauthenticated.httpx.serve(
            @httpx.Handler((r, w) => unauthenticated.handle_request(r, w)),
          )
        },
        no_wait=true,
      )
      let (unconfigured_auth, _) = @http.get(
        "http://127.0.0.1:\{unauthenticated.httpx.port()}/v1/jobs/runs/run-1/command-outputs/" +
        plan.grant.request_id +
        "/live/start",
      )
      assert_eq(unconfigured_auth.code, 401)
      let replay = @execution_sandbox.read_bound_command_live_output(
        config,
        "run-1",
        plan.grant.request_id,
        first.next_cursor,
      )
      assert_eq(replay.offset, first.next_offset)
      assert_true(replay.terminal)
      assert_true(store.get_run("run-1").unwrap().status is Cancelled)
      let (cross, _) = @http.get(
        base +
        "/v1/jobs/runs/other-run/command-outputs/" +
        plan.grant.request_id +
        "/live/start",
        headers~,
      )
      assert_eq(cross.code, 409)
      let (outside, _) = @http.get(endpoint + id + ":999999", headers~)
      assert_eq(outside.code, 409)
      @fs.remove(blob)
      let (missing, _) = @http.get(endpoint + replay.next_cursor, headers~)
      assert_eq(missing.code, 409)
      @fs.write_file(blob, all_bytes, create_mode=CreateNew, permission=0o600)
      ignore(write_live_fixture_record(spool, plan, all_bytes, "killed", 1L))
      let (expired, body) = @http.get(endpoint + replay.next_cursor, headers~)
      assert_eq(expired.code, 409)
      assert_false(body.text().contains(dir))
      assert_false(body.text().contains("r27-fixture-key"))
      let owner_path = config.receipt_root +
        "/command-live/owners/request-" +
        plan.grant.request_id +
        ".json"
      let owner_record = @fs.read_file(owner_path).binary()
      @fs.write_file(owner_path, "{}", create_mode=CreateOrTruncate)
      let (corrupt_status, corrupt_snapshot) = @http.get(
        base + "/v1/jobs/runs/run-1/ui",
        headers~,
      )
      assert_eq(corrupt_status.code, 200)
      assert_true(
        corrupt_snapshot
        .text()
        .contains("Live run bindings failed verification"),
      )
      @fs.write_file(owner_path, owner_record, create_mode=CreateOrTruncate)
      println("ACTUAL_FORT_LIVE_CLAW_UI_PASSED")
      println("LIVE_RESTART_CANCEL_CROSSRUN_CURSOR_EXPIRY_MISSING_PASSED")
      group.return_immediately(())
    })
  })
}
