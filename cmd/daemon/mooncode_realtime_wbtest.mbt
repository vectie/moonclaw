///|
async test "realtime credentials use configured provider and return only ephemeral connection details" {
  let server = @httpx.Server::new("[::1]", 0)
  defer server.close()
  let router = @httpx.Router::new()
  router.add_handler(Post, "/v1/realtime/client_secrets", (r, w) => {
    assert_eq(r.headers.get("authorization"), Some("Bearer fixture-long-lived"))
    let request : Json = @httpx.JsonRequestReader::new(r).read()
    let session = mooncode_json_object_field_or_empty(request, "session")
    assert_eq(
      mooncode_json_string(session, "model", default=""),
      "gpt-realtime",
    )
    assert_true(
      mooncode_json_string(session, "instructions", default="").contains(
        "Review the editor layout",
      ),
    )
    assert_true(session.stringify().contains("marin"))
    w.header().set("Content-Type", "application/json")
    w.write_header(200)
    w.write("{\"value\":\"fixture-ephemeral\",\"expires_at\":12345}")
  })
  @async.with_task_group(group => {
    group.spawn_bg(() => server.serve(router.handler()), no_wait=true)
    let model = @model.Model::new(
      api_key="fixture-long-lived",
      base_url="http://localhost:\{server.port()}/v1",
      name="fixture",
      model_name="coding-model",
      safe_zone_tokens=1000,
    )
    let result = mooncode_realtime_credentials(model, {
      "context": "Review the editor layout",
    })
    assert_eq(
      mooncode_json_string(result, "value", default=""),
      "fixture-ephemeral",
    )
    assert_eq(
      mooncode_json_string(result, "endpoint", default=""),
      "http://localhost:\{server.port()}/v1/realtime/calls",
    )
    assert_false(result.stringify().contains("fixture-long-lived"))
  })
}

///|
async test "realtime rejects long-lived credential echoes and redacts provider errors" {
  let server = @httpx.Server::new("[::1]", 0)
  defer server.close()
  let router = @httpx.Router::new()
  let token = "fixture-realtime-long-lived-secret"
  let mode = ["error"]
  router.add_handler(Post, "/v1/realtime/client_secrets", (r, w) => {
    let _ : Json = @httpx.JsonRequestReader::new(r).read()
    let response : Json = match mode[0] {
      "error" =>
        {
          "error": {
            "message": "Provider rejected " + token + " twice " + token,
          },
        }
      "credential" => { "value": token, "expires_at": 12345 }
      _ => { "value": "fixture-ephemeral", "expires_at": token }
    }
    w.header().set("Content-Type", "application/json")
    w.write_header(if mode[0] == "error" { 400 } else { 200 })
    w.write(response.stringify())
  })
  @async.with_task_group(group => {
    group.spawn_bg(() => server.serve(router.handler()), no_wait=true)
    let model = @model.Model::new(
      api_key=token,
      base_url="http://localhost:\{server.port()}/v1",
      name="fixture",
      model_name="coding-model",
      safe_zone_tokens=1000,
    )
    for outcome in ["error", "credential", "expiration"] {
      mode[0] = outcome
      let result = Ok(mooncode_realtime_credentials(model, {})) catch {
        InvalidJournal(message) => Err(message)
        error => raise error
      }
      match result {
        Ok(_) => fail("provider credential echo must be rejected")
        Err(message) => assert_false(message.contains(token))
      }
    }
  })
}
