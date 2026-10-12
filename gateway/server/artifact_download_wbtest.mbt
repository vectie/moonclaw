///|
test "artifact attachment filename rejects paths and header injection" {
  assert_eq(artifact_route_id("run%3Aone"), Some("run:one"))
  assert_eq(artifact_route_id("%E6%8A%A5%E5%91%8A"), Some("报告"))
  for value in ["%", "%GG", "%FF", "%00", "%2Fsecret", "..", "%2e%2e", "a%5Cb"] {
    assert_eq(artifact_route_id(value), None)
  }
  assert_eq(
    artifact_download_filename("../folder/报告📄.pdf"),
    "报告📄.pdf",
  )
  assert_eq(
    artifact_download_filename("C:\\folder\\evil\r\n\".bin"),
    "evil___.bin",
  )
  assert_eq(artifact_download_filename("../.."), "artifact.bin")
  let header = artifact_download_disposition("../报告📄.pdf")
  assert_true(
    header.contains("filename*=UTF-8''%E6%8A%A5%E5%91%8A%F0%9F%93%84.pdf"),
  )
  assert_false(header.contains("\r") || header.contains("\n"))
}

///|
async test "artifact download actual authenticated gateway preserves binary and exact owner after restart" {
  @fsx.with_temporary_directory("claw-download-http-XXXXXX", dir => {
    let gateway = Gateway::new(port=0, cwd=dir[:], home=dir[:], auth={
      token: Some("fixture-only-token"),
      _password: None,
    })
    defer gateway.httpx.close()
    let store = gateway.job_runtime().store()
    let artifacts = @job.ArtifactStore::new(store~)
    let artifact = artifacts.write(
      @job.ArtifactWriteRequest::new(
        run_id="run-owned",
        job_id="job-fixture",
        artifact_type="report",
        content_type="application/pdf",
        file_name=Some("报告📄.pdf"),
        content="seed",
      ),
      "artifact-exact",
      100,
    )
    let binary = b"%PDF-1.7\x00\xff\x80\xc0\xfe\nEOF"
    @fs.write_file(artifact.path, binary)
    ignore(
      artifacts.write(
        @job.ArtifactWriteRequest::new(
          run_id="run-owned",
          job_id="job-fixture",
          artifact_type="text-report",
          content_type="text/plain",
          content="retained text 世界",
        ),
        "text-exact",
        101,
      ),
    )
    ignore(
      artifacts.write(
        @job.ArtifactWriteRequest::new(
          run_id="encoded:run",
          job_id="job-fixture",
          artifact_type="encoded-text",
          content_type="text/plain",
          content="encoded identity",
        ),
        "encoded:artifact",
        102,
      ),
    )
    // Reload durable metadata rather than trusting the in-memory write result.
    store.load()
    let index_before = @fs.read_file(store.root_dir() + "/index/artifacts.json").binary()
    let before_records = store.list_artifacts().to_json()
    let base = "http://127.0.0.1:\{gateway.httpx.port()}"
    let endpoint = base +
      "/v1/jobs/runs/run-owned/artifacts/artifact-exact/download"
    let headers = { "authorization": "Bearer fixture-only-token" }
    @async.with_task_group(group => {
      group.spawn_bg(
        () => {
          gateway.httpx.serve(
            @httpx.Handler((r, w) => gateway.handle_request(r, w)),
          )
        },
        no_wait=true,
      )
      // Replay the actual shipped UI transport against this real gateway. The
      // test stubs only the browser's save-file boundary, never HTTP or auth.
      let (ui_code, ui_output) = @process.collect_output_merged(
        "moon",
        [
          "test", "--target", "js", "main/gateway_http_integration_wbtest.mbt", "--index",
          "0",
        ],
        extra_env={ "MOONCLAW_HTTP_FIXTURE_URL": base },
        cwd=@os.cwd() + "/ui/rabbita-job",
      )
      assert_eq(ui_code, 0, msg=ui_output.text())
      assert_true(
        ui_output.text().contains("ACTUAL_GATEWAY_UI_PASSED"),
        msg=ui_output.text(),
      )
      println("Actual gateway + shipped UI transport: ACTUAL_GATEWAY_UI_PASSED")
      let (denied, _) = @http.get(endpoint)
      assert_eq(denied.code, 401)
      let (wrong_token, _) = @http.get(endpoint, headers={
        "authorization": "Bearer wrong",
      })
      assert_eq(wrong_token.code, 401)
      let (encoded, encoded_body) = @http.get(
        base +
        "/v1/jobs/runs/encoded%3Arun/artifacts/encoded%3Aartifact/download",
        headers~,
      )
      assert_eq(encoded.code, 200)
      assert_eq(encoded_body.text(), "encoded identity")
      let (invalid, _) = @http.get(
        base + "/v1/jobs/runs/run-owned/artifacts/%2Fsecret/download",
        headers~,
      )
      assert_eq(invalid.code, 400)
      let (text_response, text_body) = @http.get(
        base + "/v1/jobs/runs/run-owned/artifacts/text-exact/download",
        headers~,
      )
      assert_eq(text_response.code, 200)
      assert_eq(
        text_body.binary(),
        @encoding/utf8.encode("retained text 世界"),
      )
      let (opened, opened_body) = @http.get(
        base + "/v1/artifacts/text-exact",
        headers~,
      )
      assert_eq(opened.code, 200)
      let opened_json = @json.parse(opened_body.text())
      assert_true(
        opened_json is { "content": [String(content)], .. } &&
        content == "retained text 世界",
        msg=opened_json.stringify(),
      )
      for
        path in [
          "/v1/jobs/runs/other-run/artifacts/artifact-exact/download", "/v1/jobs/runs/run-owned/artifacts/unknown/download",
          "/v1/jobs/runs/run-owned/artifacts/synthetic:run-owned:report/download",
        ] {
        let (response, _) = @http.get(base + path, headers~)
        assert_eq(response.code, 404)
      }
      for _ in 0..<2 {
        let (response, body) = @http.get(endpoint, headers~)
        assert_eq(response.code, 200)
        assert_eq(body.binary(), binary)
        assert_eq(
          response.headers.get("content-type"),
          Some("application/octet-stream"),
        )
        assert_eq(
          response.headers.get("content-disposition"),
          Some(artifact_download_disposition(artifact.path)),
        )
        assert_eq(response.headers.get("cache-control"), Some("no-store"))
        assert_eq(
          response.headers.get("x-content-type-options"),
          Some("nosniff"),
        )
      }
      // The consumer can disconnect after headers and retry the same identity.
      let client = @http.Client(base)
      client.request(
        Get,
        "/v1/jobs/runs/run-owned/artifacts/artifact-exact/download",
        extra_headers=headers,
      )
      let response = client.end_request()
      assert_eq(response.code, 200)
      client.close()
      let (response, body) = @http.get(endpoint, headers~)
      assert_eq(response.code, 200)
      assert_eq(body.binary(), binary)
      assert_eq(store.list_artifacts().to_json(), before_records)
      assert_eq(
        @fs.read_file(store.root_dir() + "/index/artifacts.json").binary(),
        index_before,
      )
      assert_eq(store.list_runs().length(), 0)
      @fsx.remove(artifact.path)
      let (missing, body) = @http.get(endpoint, headers~)
      assert_eq(missing.code, 410)
      assert_true(body.text().contains("artifact_content_missing"))
      assert_true(artifacts.get(artifact.id) is Some(_))
      @fs.write_file(artifact.path, binary, create_mode=CreateOrTruncate)
      let (restored, body) = @http.get(endpoint, headers~)
      assert_eq(restored.code, 200)
      assert_eq(body.binary(), binary)
    })
  })
}
