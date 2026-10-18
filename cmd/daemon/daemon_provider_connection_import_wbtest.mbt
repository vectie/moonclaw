///|
priv struct ProviderImportFixture {
  owner : IntegrationHttpFixture
  descriptor : Json
  calls : Array[String]
  validation : Ref[Json]
  validation_code : Ref[Int32]
  validation_raw : Ref[String?]
  validation_delay : Ref[Int32]
  exists : Ref[Bool]
  fail_path : Ref[String]
  provider_calls : Ref[Int32]
}

///|
async fn provider_import_status(workspace : String, url : String) -> Unit {
  integration_fixture_write(
    @pathx.join(@moonsuite.state_dir(workspace), "suite-status.json"),
    {
      "contract": "moon.suite.status.v2",
      "service": "moongate",
      "manifest": {
        "contract": "moon.suite.service.v1",
        "service": "moongate",
        "baseUrl": url,
      },
    },
  )
}

///|
async fn with_provider_import_fixture(
  run : async (ProviderImportFixture) -> Unit,
) -> Unit {
  with_integration_http_fixture(owner => {
    let token = "provider-import-synthetic-key"
    let control_token = "provider-import-gate-control-token"
    let provider = @httpx.Server::new("127.0.0.1", 0)
    defer provider.close()
    let provider_calls = Ref(0)
    let provider_router = @httpx.Router::new()
    provider_router.add_handler(Get, "/v1/models", (_, w) => {
      provider_calls.val += 1
      w.write_header(200)
      w.write("{\"data\":[{\"id\":\"fixture-import-model\"}]}")
    })
    let descriptor : Json = {
      "version": "openai.connection.v1",
      "api": "chat.completions",
      "base_url": "http://127.0.0.1:\{provider.port()}/v1",
      "api_key": token,
      "model": "fixture-import-model",
      "max_output_tokens": 4096,
    }
    let calls : Array[String] = []
    let validation : Ref[Json] = Ref({
      "contract": "moongate.provider-connection-validation.v1",
      "valid": true,
      "model": "fixture-import-model",
      "inferencePerformed": false,
      "persisted": false,
    })
    let validation_code = Ref(200)
    let validation_raw : Ref[String?] = Ref(None)
    let validation_delay = Ref(0)
    let exists = Ref(false)
    let fail_path = Ref("")
    let gate = @httpx.Server::new("127.0.0.1", 0)
    defer gate.close()
    let gate_router = @httpx.Router::new()
    gate_router.add_handler(Get, "/control/bootstrap", (r, w) => {
      calls.push("bootstrap")
      assert_eq(
        r.headers.get("origin"),
        Some("http://127.0.0.1:\{gate.port()}"),
      )
      assert_eq(r.headers.get("sec-fetch-site"), Some("same-origin"))
      w.write_header(200)
      w.write(({ "token": control_token } : Json).stringify())
    })
    gate_router.add_handler(Post, "/providers/validate-connection", (r, w) => {
      calls.push("validate")
      assert_eq(r.headers.get("x-moongate-control-token"), Some(control_token))
      let body : Json = @httpx.JsonRequestReader::new(r).read()
      assert_eq(body, {
        "appType": "openclaw",
        "api": "chat.completions",
        "baseUrl": mooncode_json_string(descriptor, "base_url", default=""),
        "apiKey": token,
        "model": "fixture-import-model",
      })
      if validation_delay.val > 0 {
        @async.sleep(validation_delay.val)
      }
      w.write_header(validation_code.val)
      w.write(validation_raw.val.unwrap_or(validation.val.stringify()))
    })
    gate_router.add_handler(Get, "/providers", (r, w) => {
      calls.push("list")
      assert_eq(r.headers.get("x-moongate-control-token"), Some(control_token))
      let id = provider_import_fixture_id(descriptor)
      w.write_header(200)
      w.write((if exists.val { [{ "id": id }] } else { [] } : Json).stringify())
    })
    for
      path in [
        "/providers", "/providers/update", "/providers/switch", "/bindings",
      ] {
      gate_router.add_handler(Post, path, (r, w) => {
        calls.push(path)
        assert_eq(
          r.headers.get("x-moongate-control-token"),
          Some(control_token),
        )
        let body : Json = @httpx.JsonRequestReader::new(r).read()
        let id = provider_import_fixture_id(descriptor)
        if path == "/providers" || path == "/providers/update" {
          assert_eq(mooncode_json_string(body, "apiKey", default=""), token)
          assert_eq(mooncode_json_string(body, "id", default=""), id)
        } else if path == "/bindings" {
          assert_eq(body, { "appType": "moondesk", "providerId": id })
        } else {
          assert_eq(body, { "appType": "openclaw", "id": id })
        }
        w.write_header(if fail_path.val == path { 502 } else { 200 })
        w.write(({ "secret": token } : Json).stringify())
      })
    }
    provider_import_status(owner.workspace, "http://127.0.0.1:\{gate.port()}")
    let old = @os.getenv("MOONGATE_CONTROL_TOKEN")
    defer (match old {
      Some(v) => @os.setenv("MOONGATE_CONTROL_TOKEN", v)
      None => @os.unsetenv("MOONGATE_CONTROL_TOKEN")
    })
    @os.setenv("MOONGATE_CONTROL_TOKEN", control_token)
    @async.with_task_group(group => {
      group.spawn_bg(
        () => provider.serve(provider_router.handler()),
        no_wait=true,
      )
      group.spawn_bg(() => gate.serve(gate_router.handler()), no_wait=true)
      run({
        owner,
        descriptor,
        calls,
        validation,
        validation_code,
        validation_raw,
        validation_delay,
        exists,
        fail_path,
        provider_calls,
      })
    })
  })
}

///|
fn provider_import_fixture_id(descriptor : Json) -> String {
  let key = mooncode_json_string(descriptor, "base_url", default="") +
    "\n" +
    mooncode_json_string(descriptor, "model", default="")
  "imported-openai-" +
  @crypto.bytes_to_hex_string(
    @crypto.sha256(@encoding/utf8.encode(key).to_fixedarray()),
  )[:16].to_owned()
}

///|
async test "provider import authenticates before bounded parsing and validates before every mutation" {
  with_provider_import_fixture(fixture => {
    let url = "http://127.0.0.1:\{fixture.owner.daemon.port}/v1/provider-connections/import"
    for
      headers in [
        Map([]),
        {
          "X-MoonClaw-Execution-Token": "b".repeat(64),
          "X-MoonClaw-Instance-ID": fixture.owner.config.instance_id,
        },
        {
          "X-MoonClaw-Execution-Token": fixture.owner.config.auth_token,
          "X-MoonClaw-Instance-ID": "f".repeat(32),
        },
      ] {
      let (r, _) = @http.post(url, "not-json", headers~)
      assert_eq(r.code, 401)
      assert_eq(r.headers.get("cache-control"), Some("no-store"))
    }
    assert_eq(fixture.calls, [])
    let headers = {
      "X-MoonClaw-Execution-Token": fixture.owner.config.auth_token,
      "X-MoonClaw-Instance-ID": fixture.owner.config.instance_id,
    }
    for (body, code) in [("not-json", 400), ("x".repeat(8193), 413)] {
      let (r, _) = @http.post(url, body, headers~)
      assert_eq(r.code, code)
    }
    assert_eq(
      integration_fixture_post(
        fixture.owner,
        "/v1/provider-connections/import",
        {},
      ).0,
      400,
    )
    let invalid = mooncode_json_object_with_field(
      fixture.descriptor,
      "model",
      Json("bad\nmodel"),
    )
    assert_eq(
      integration_fixture_post(
        fixture.owner,
        "/v1/provider-connections/import",
        invalid,
      ).0,
      400,
    )
    assert_eq(fixture.calls, [])
    for exists in [false, true] {
      fixture.exists.val = exists
      fixture.calls.clear()
      // Caller-provided workspace/control fields cannot replace the registered service.
      let body = mooncode_json_object_with_field(
        mooncode_json_object_with_field(
          fixture.descriptor,
          "workspace_root",
          Json("/outside"),
        ),
        "moongate_url",
        Json("https://unselected.invalid"),
      )
      let (code, result) = integration_fixture_post(
        fixture.owner,
        "/v1/provider-connections/import",
        body,
      )
      assert_eq(code, 200, msg=result.stringify())
      assert_eq(result, {
        "contract": "moonclaw.provider-connection-import.v1",
        "ok": true,
        "status": "connected",
        "model": "fixture-import-model",
        "provider_id": provider_import_fixture_id(fixture.descriptor),
      })
      assert_eq(fixture.calls, [
        "validate",
        "list",
        if exists {
          "/providers/update"
        } else {
          "/providers"
        },
        "/providers/switch",
        "/bindings",
      ])
      assert_false(result.stringify().contains("provider-import-synthetic-key"))
    }
    assert_eq(fixture.provider_calls.val, 0)
  })
}

///|
async test "provider import rejects failed malformed wrong-model and credential-echo validation without saving" {
  with_provider_import_fixture(fixture => {
    let original = fixture.validation.val
    for
      invalid in [
        Json::null(),
        {},
        mooncode_json_object_with_field(original, "contract", Json("wrong")),
        mooncode_json_object_with_field(original, "valid", Json(false)),
        mooncode_json_object_with_field(original, "model", Json("wrong-model")),
        mooncode_json_object_with_field(original, "persisted", Json(true)),
        mooncode_json_object_with_field(
          original,
          "inferencePerformed",
          Json(true),
        ),
        mooncode_json_object_with_field(
          original,
          "secret",
          Json("provider-import-synthetic-key"),
        ),
      ] {
      fixture.validation.val = invalid
      fixture.calls.clear()
      let (code, result) = integration_fixture_post(
        fixture.owner,
        "/v1/provider-connections/import",
        fixture.descriptor,
      )
      assert_eq(code, 502)
      assert_eq(fixture.calls, ["validate"])
      assert_false(result.stringify().contains("provider-import-synthetic-key"))
    }
    fixture.validation.val = { "error": "provider-import-synthetic-key" }
    for status in [302, 400, 401, 500] {
      fixture.validation_code.val = status
      fixture.calls.clear()
      let (code, result) = integration_fixture_post(
        fixture.owner,
        "/v1/provider-connections/import",
        fixture.descriptor,
      )
      assert_eq(code, 502)
      assert_eq(fixture.calls, ["validate"])
      assert_false(result.stringify().contains("provider-import-synthetic-key"))
    }
    fixture.validation_code.val = 200
    for raw in ["{", "x".repeat(65537)] {
      fixture.validation_raw.val = Some(raw)
      fixture.calls.clear()
      let (code, _) = integration_fixture_post(
        fixture.owner,
        "/v1/provider-connections/import",
        fixture.descriptor,
      )
      assert_eq(code, 502)
      assert_eq(fixture.calls, ["validate"])
    }
    assert_eq(fixture.provider_calls.val, 0)
  })
}

///|
async test "provider import total timeout performs no configuration" {
  with_provider_import_fixture(fixture => {
    fixture.validation_delay.val = 31000
    let (code, result) = integration_fixture_post(
      fixture.owner,
      "/v1/provider-connections/import",
      fixture.descriptor,
    )
    assert_eq(code, 502)
    assert_true(result.stringify().contains("connection validation"))
    assert_eq(fixture.calls, ["validate"])
    assert_eq(fixture.provider_calls.val, 0)
  })
}

///|
async test "provider import preserves token-file bootstrap and truthful later-stage failures" {
  with_provider_import_fixture(fixture => {
    @os.unsetenv("MOONGATE_CONTROL_TOKEN")
    let token_path = @moonsuite.product_artifact_for_workspace_root(
      fixture.owner.workspace,
      "moongate",
      "control-token",
    )
    @fsx.make_directory(
      @pathx.dirname(token_path),
      recursive=true,
      exists_ok=true,
    )
    @fsx.write_to_file(token_path, "provider-import-gate-control-token\n")
    assert_eq(
      integration_fixture_post(
        fixture.owner,
        "/v1/provider-connections/import",
        fixture.descriptor,
      ).0,
      200,
    )
    assert_false(fixture.calls.contains("bootstrap"))
    @fs.rename(token_path, token_path + ".retained")
    fixture.calls.clear()
    assert_eq(
      integration_fixture_post(
        fixture.owner,
        "/v1/provider-connections/import",
        fixture.descriptor,
      ).0,
      200,
    )
    assert_eq(fixture.calls[0], "bootstrap")
    for path in ["/providers", "/providers/switch", "/bindings"] {
      fixture.calls.clear()
      fixture.fail_path.val = path
      let (code, result) = integration_fixture_post(
        fixture.owner,
        "/v1/provider-connections/import",
        fixture.descriptor,
      )
      assert_eq(code, 502)
      assert_true(fixture.calls.contains("validate"))
      assert_eq(fixture.calls.last(), Some(path))
      assert_false(result.stringify().contains("provider-import-synthetic-key"))
    }
  })
}
