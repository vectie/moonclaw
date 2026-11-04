///|
async test "image provider generation and editing persist returned PNG artifacts" {
  let server = @httpx.Server::new("[::1]", 0)
  defer server.close()
  let router = @httpx.Router::new()
  let requests : Array[Json] = []
  let png = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aD1sAAAAASUVORK5CYII="
  router.add_handler(Post, "/v1/responses", (r, w) => {
    assert_eq(
      r.headers.get("authorization"),
      Some("Bearer image-fixture-token"),
    )
    requests.push(@httpx.JsonRequestReader::new(r).read())
    w.header().set("Content-Type", "application/json")
    w.write_header(200)
    let result : Json = {
      "id": "response-fixture",
      "output": [{ "type": "image_generation_call", "result": png }],
    }
    w.write(result.stringify())
  })
  @fsx.with_temporary_directory("mooncode-image-fixture-XXXXXX", root => {
    @async.with_task_group(group => {
      group.spawn_bg(() => server.serve(router.handler()), no_wait=true)
      let model = @model.Model::new(
        api_key="image-fixture-token",
        base_url="http://localhost:\{server.port()}/v1",
        name="fixture",
        model_name="image-fixture",
        safe_zone_tokens=1000,
      )
      let generated = mooncode_generate_image_artifacts(
        model,
        root,
        "generated",
        "A calm workspace",
        [],
      )
      assert_eq(mooncode_json_string(generated, "status", default=""), "done")
      let source = @fs.read_file(
        @pathx.join(root, "artifacts/images/generated-0.png"),
      )
      assert_eq(@base64.encode(source.binary()), png)
      let daemon = mooncode_control_test_daemon(root)
      defer daemon.httpx.close()
      mooncode_management_test_create_session(daemon, root, "images")
      mooncode_append_session_journal(
        root,
        "images",
        mooncode_journal_event(),
        {
          "id": "image-result",
          "kind": "session.image.job",
          "session_id": "images",
          "created_at": @clock.epoch.now(),
          "paths": ["artifacts/images/generated-0.png"],
        },
      )
      let download = daemon.mooncode_task_controls_response("images", {
        "book_root": root,
        "action": "load_image",
        "path": "artifacts/images/generated-0.png",
      })
      assert_eq(mooncode_json_string(download, "data_base64", default=""), png)
      ignore(
        mooncode_generate_image_artifacts(
          model,
          root,
          "edited",
          "Make it blue",
          [{ "media_type": "image/png", "data_base64": png }],
        ),
      )
      assert_true(
        @fsx.exists(@pathx.join(root, "artifacts/images/edited-0.png")),
      )
      assert_eq(requests.length(), 2)
      assert_false(requests[0].stringify().contains("input_image"))
      assert_true(requests[1].stringify().contains("input_image"))
    })
  })
}

///|
test "image studio sends text and source pixels and extracts only generated images" {
  let request = mooncode_image_request(
    "fixture-image-model",
    "Make a quieter background",
    [{ "media_type": "image/png", "data_base64": "iVBORw0KGgo=" }],
  )
  let serialized = request.stringify()
  assert_true(serialized.contains("input_image"))
  assert_true(serialized.contains("data:image/png;base64,iVBORw0KGgo="))
  assert_true(serialized.contains("Make a quieter background"))
  assert_eq(
    mooncode_image_outputs({
      "output": [
        { "type": "message", "result": "not an image" },
        { "type": "image_generation_call", "result": "png-pixels" },
      ],
    }),
    ["png-pixels"],
  )
}

///|
test "image job projection shows interruptions after restart and final artifacts" {
  let jobs = mooncode_image_job_projection([
    { "kind": "session.image.job", "job_id": "job-a", "status": "running" },
    { "kind": "session.image.job", "job_id": "job-b", "status": "running" },
    {
      "kind": "session.image.job",
      "job_id": "job-b",
      "status": "done",
      "paths": ["artifacts/images/result.png"],
    },
  ])
  assert_eq(jobs.length(), 2)
  assert_eq(mooncode_json_string(jobs[0], "status", default=""), "interrupted")
  assert_eq(mooncode_json_string(jobs[1], "status", default=""), "done")
  assert_eq(mooncode_json_array_items(jobs[1], "paths"), [
    Json::string("artifacts/images/result.png"),
  ])
}
