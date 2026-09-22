///|
test "LunaNexa issuer validation rejects SSRF and credential-bearing URLs" {
  assert_eq(
    lunanexa_url_origin("https://management.example", true),
    Some("https://management.example"),
  )
  assert_eq(
    lunanexa_url_origin("http://127.0.0.1:18443", true),
    Some("http://127.0.0.1:18443"),
  )
  for
    malicious in [
      "http://management.example", "http://127.0.0.1.attacker.invalid", "http://localhost:not-a-port",
      "https://trusted@attacker.invalid", "https://management.example/path", "https://management.example#fragment",
      "https://management.example?issuer=other",
    ] {
    assert_true(lunanexa_url_origin(malicious, true) is None)
  }
}

///|
test "provider handoff validates code and returns no reusable secret" {
  let request : LunaProviderHandoffRequest = {
    contract: "moonclaw.provider-handoff.v1",
    client_id: "desktop-workspace",
    handoff_code: "lnxc_" + "b".repeat(64),
  }
  assert_true(valid_lunanexa_handoff_request(request))
  assert_false(
    valid_lunanexa_handoff_request({ ..request, client_id: "bad/client", }),
  )
  assert_false(
    valid_lunanexa_handoff_request({ ..request, handoff_code: "lnxc_short", }),
  )
  let redemption : LunaProviderHandoffRedemption = {
    client_id: request.client_id,
    api_secret: "lnx_" + "a".repeat(64),
    api_base_url: "https://management.example/v1",
    allowed_models: ["text.default"],
    expires_unix_ms: 20_000L,
    maximum_requests: 1_000L,
    one_time: true,
  }
  assert_true(
    valid_lunanexa_redemption(
      redemption, request, "https://management.example", 10_000L,
    ),
  )
  assert_false(
    valid_lunanexa_redemption(
      { ..redemption, api_base_url: "https://management.example/api", },
      request,
      "https://management.example",
      10_000L,
    ),
  )
  let public = lunanexa_provider_handoff_success(redemption).stringify()
  assert_false(public.contains("api_secret"))
  assert_false(public.contains("lnx_"))
  assert_false(public.contains("api_base_url"))
}

///|
async test "one handoff redeems from LunaNexa and installs the MoonGate binding" {
  let lunanexa = @httpx.Server::new("[::1]", 0, reuse_addr=true)
  defer lunanexa.close()
  let moongate = @httpx.Server::new("[::1]", 0, reuse_addr=true)
  defer moongate.close()
  let root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-lunanexa-handoff-XXXXXX"),
  )
  let suite_root = @moonsuite.suite_root_for_workspace_root(root)
  let state_dir = @moonsuite.state_dir(suite_root)
  @moonclaw_fsx.make_directory(state_dir, recursive=true, exists_ok=true)
  @fsx.write_to_file(
    @pathx.join(state_dir, "suite-status.json"),
    (
      {
        "contract": "moon.suite.status.v2",
        "service": "moongate",
        "manifest": {
          "contract": "moon.suite.service.v1",
          "service": "moongate",
          "baseUrl": "http://localhost:\{moongate.port()}",
        },
      } : Json).stringify(),
  )
  let calls : Array[String] = []
  let lunanexa_router = @httpx.Router::new()
  lunanexa_router.add_handler(Post, "/v1/client-handoffs:redeem", (r, w) => {
    let reader : @httpx.JsonRequestReader = @httpx.JsonRequestReader::new(r)
    let body : Json = reader.read()
    guard body is Object(fields) else { fail("expected redemption request") }
    assert_eq(fields["client_id"], Json::string("desktop-workspace"))
    assert_eq(fields["handoff_code"], Json::string("lnxc_" + "b".repeat(64)))
    assert_true(fields.get("issuer") is None)
    assert_true(fields.get("api_secret") is None)
    calls.push("redeem")
    w.header().set("Content-Type", "application/json")
    w.write_header(200)
    w.write(
      (
        {
          "client_id": "desktop-workspace",
          "api_secret": "lnx_" + "a".repeat(64),
          "api_base_url": "http://localhost:\{lunanexa.port()}/v1",
          "allowed_models": ["text.default"],
          "expires_unix_ms": (@async.now() + 60_000L).to_json(),
          "maximum_requests": 1_000L.to_json(),
          "one_time": true,
        } : Json).stringify(),
    )
  })
  let moongate_router = @httpx.Router::new()
  moongate_router.add_handler(Get, "/providers", (r, w) => {
    assert_true(r.path.contains("appType=openclaw"))
    assert_eq(r.headers.get("x-moongate-control-token"), Some("t".repeat(64)))
    calls.push("list")
    w.header().set("Content-Type", "application/json")
    w.write_header(200)
    w.write("[]")
  })
  moongate_router.add_handler(Post, "/providers", (r, w) => {
    let reader : @httpx.JsonRequestReader = @httpx.JsonRequestReader::new(r)
    let body : Json = reader.read()
    guard body is Object(fields) else { fail("expected provider request") }
    assert_eq(fields["id"], Json::string("lunanexa-lease"))
    assert_eq(fields["appType"], Json::string("openclaw"))
    assert_eq(fields["apiFormat"], Json::string("openai_chat"))
    assert_eq(
      fields["baseUrl"],
      Json::string("http://localhost:\{lunanexa.port()}/v1"),
    )
    assert_eq(fields["apiKey"], Json::string("lnx_" + "a".repeat(64)))
    calls.push("provider")
    w.header().set("Content-Type", "application/json")
    w.write_header(200)
    w.write("true")
  })
  moongate_router.add_handler(Post, "/bindings", (r, w) => {
    let reader : @httpx.JsonRequestReader = @httpx.JsonRequestReader::new(r)
    let body : Json = reader.read()
    guard body is Object(fields) else { fail("expected binding request") }
    assert_eq(fields["appType"], Json::string("moonclaw"))
    assert_eq(fields["providerId"], Json::string("lunanexa-lease"))
    calls.push("binding")
    w.header().set("Content-Type", "application/json")
    w.write_header(200)
    w.write("true")
  })
  @os.setenv("MOONGATE_CONTROL_TOKEN", "t".repeat(64))
  @async.with_task_group(group => {
    group.spawn_bg(
      () => lunanexa.serve(lunanexa_router.handler()),
      no_wait=true,
    )
    group.spawn_bg(
      () => moongate.serve(moongate_router.handler()),
      no_wait=true,
    )
    @async.pause()
    let request : LunaProviderHandoffRequest = {
      contract: "moonclaw.provider-handoff.v1",
      client_id: "desktop-workspace",
      handoff_code: "lnxc_" + "b".repeat(64),
    }
    guard install_lunanexa_provider_handoff(
        root,
        "http://localhost:\{lunanexa.port()}",
        request,
      )
      is Ok(redemption) else {
      fail("expected provider handoff installation")
    }
    assert_eq(redemption.allowed_models, ["text.default"])
    assert_eq(calls, ["redeem", "list", "provider", "binding"])
  })
  @os.unsetenv("MOONGATE_CONTROL_TOKEN")
  @fs.rmdir(root, recursive=true)
}
