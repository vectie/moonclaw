///|
#skip("Requires prepared round55 private Fort fixtures and compiler-JS packaging")
async test "real gateway owner route serves fresh compiler UI and inspects all five exact Fort attempts" {
  guard @os.getenv("ROUND55_ROOT") is Some(root) &&
    @os.getenv("ROUND55_FIXTURE_ROOT") is Some(fixture) else {
    fail("round55 fixture required")
  }
  @fsx.with_temporary_directory("round55-gateway-XXXXXX", dir => {
    let gateway = Gateway::new(port=0, cwd=dir[:], home=dir[:], auth={
      token: Some("fixture-only-token"),
      _password: None,
    })
    defer gateway.httpx.close()
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
      assert_eq(index_response.headers.get("cache-control"), Some("no-cache"))
      assert_eq(
        index_body.binary(),
        @fs.read_file(dist + "/index.html").binary(),
      )
      let packaging = @json.parse(
        @fs.read_file(root + "/evidence/UI_PACKAGING.json").text(),
      )
      guard packaging
        is {
          "bootstrap": String(bootstrap),
          "entry": String(entry),
          "compiled_sha256": String(expected),
          ..
        } else {
        fail("packaging receipt")
      }
      assert_true(index_body.text().contains(bootstrap))
      assert_false(index_body.text().contains("index-Dr1FNJNT.js"))
      let (loader_response, loader_body) = @http.get(
        base + "/assets/" + bootstrap,
      )
      assert_eq(loader_response.code, 200)
      assert_true(loader_body.text().contains("./" + entry))
      assert_false(
        loader_body.text().contains("./_rabbita_main-entry-6xtbnIpU.js"),
      )
      let (entry_response, entry_body) = @http.get(base + "/assets/" + entry)
      assert_eq(entry_response.code, 200)
      assert_eq(
        entry_body.binary(),
        @fs.read_file(root + "/evidence/build-ui/js/debug/build/main/main.js").binary(),
      )
      assert_eq(
        @crypto.bytes_to_hex_string(@crypto.sha256(entry_body.binary())),
        expected,
      )
      assert_true(entry_body.text().contains("Inspect destination read-only"))
      assert_true(entry_body.text().contains("promotion-recovery"))
      let (code, output) = @process.collect_output_merged(
        "moon",
        [
          "test",
          "--frozen",
          "--target",
          "js",
          "--strip",
          "-j",
          "1",
          "--target-dir",
          root + "/evidence/build-ui",
          "main/promotion_recovery_wbtest.mbt",
          "--index",
          "1",
        ],
        extra_env={
          "MOONCLAW_HTTP_FIXTURE_URL": base,
          "ROUND55_FIXTURE_ROOT": fixture,
        },
        cwd=@os.cwd() + "/ui/rabbita-job",
      )
      @fs.write_file(
        root + "/evidence/gateway-compiled-ui.log",
        output.binary(),
        create_mode=CreateOrTruncate,
      )
      assert_eq(code, 0, msg=output.text())
      assert_true(
        output.text().contains("ROUND55_ACTUAL_FORT_GATEWAY_COMPILED_UI_PASSED"),
      )
      let headers = {
        "authorization": "Bearer fixture-only-token",
        "x-moonclaw-execution-token": "b".repeat(64),
      }
      let (extra_response, _) = @http.post(
        base + "/v1/execution-sandbox/promotion-recovery",
        "{\"protocol_version\":1,\"instance_id\":\"a\",\"workspace_id\":\"book\",\"retention_id\":\"r\",\"pending_attempt_id\":\"p\",\"request_id\":\"i\",\"workspace_root\":\"/CANARY-private\"}",
        headers~,
      )
      assert_eq(extra_response.code, 422)
      let (large_response, _) = @http.post(
        base + "/v1/execution-sandbox/promotion-recovery",
        "x".repeat(4097),
        headers~,
      )
      assert_eq(large_response.code, 422)
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
        "http://127.0.0.1:\{anonymous.httpx.port()}/v1/execution-sandbox/promotion-recovery",
        "{}",
      )
      assert_eq(response.code, 401)
      group.return_immediately(())
    })
  })
  println("ROUND55_NORMAL_OWNER_URL_AND_GATEWAY_PASSED")
}
