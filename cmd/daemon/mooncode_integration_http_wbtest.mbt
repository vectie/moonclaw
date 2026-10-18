///|
priv struct IntegrationHttpFixture {
  daemon : Daemon
  workspace : String
  book : String
  other : String
  untrusted : String
  config_path : String
  config : @moondesk_sandbox_config.Config
  descriptor : Json
  provider_calls : Ref[Int32]
}

///|
let integration_http_fixture_lock : @semaphore.Semaphore = Semaphore(1)

///|
async fn integration_fixture_daemon(root : String) -> Daemon {
  let server = @httpx.Server::new("127.0.0.1", 0)
  {
    clock: @clock.epoch,
    models: @model.Loader::new(home=root, cwd=root),
    uuid: @uuid.generator(@rand.chacha8()),
    process: @trusted_host_process.DaemonChildManager::new(cwd=root),
    by_cwd: Map([]),
    by_id: Map([]),
    rqs: Map([]),
    httpx: server,
    port: server.port(),
    events: @broadcast.Broadcast::new(),
    serve: root,
    conversations: @conversation.Manager::new(
      home=root,
      uuid=@uuid.generator(@rand.chacha8()),
    ),
    home: root,
    pending_codex_auth: Map([]),
    mooncode_sessions: Map([]),
  }
}

///|
async fn integration_fixture_write(path : String, value : Json) -> Unit {
  @fsx.make_directory(@pathx.dirname(path), recursive=true, exists_ok=true)
  @fsx.write_to_file(path, value.stringify())
}

///|
async fn with_integration_http_fixture(
  run : async (IntegrationHttpFixture) -> Unit,
  standard_books~ : Bool = false,
) -> Unit {
  // These fixtures temporarily install synthetic process environment paths.
  integration_http_fixture_lock.acquire()
  defer integration_http_fixture_lock.release()
  let root = @fs.realpath(@fs.tmpdir(prefix="moonclaw-routes23-"))
  let book = root + (if standard_books { "/books/A" } else { "/projectA" })
  let other = root + (if standard_books { "/books/B" } else { "/projectB" })
  let untrusted = root + "/untrusted"
  for path in [book, other, untrusted, book + "/descendant"] {
    @fs.mkdir(path, recursive=true)
  }
  let app_data = root + "/app-data"
  let control_root = app_data + "/control/execution-sandbox"
  @fs.mkdir(control_root, recursive=true, permission=0o700)
  @fs.chmod(control_root, 0o700)
  let config_path = control_root + "/fixture.json"
  let config : @moondesk_sandbox_config.Config = {
    protocol_version: 1,
    instance_id: "0123456789abcdef0123456789abcdef",
    auth_token: "a".repeat(64),
    workspace_id: "fixture",
    workspace_root: root,
    trusted_book_roots: Some([book, other]),
  }
  @fs.write_file(
    config_path,
    config.to_json().stringify(),
    create_mode=CreateNew,
    permission=0o600,
  )
  let old_app = @os.getenv("LEPUSA_APP_DATA_DIR")
  let old_control = @os.getenv("MOONDESK_EXECUTION_SANDBOX_CONFIG")
  defer {
    match old_app {
      Some(value) => @os.setenv("LEPUSA_APP_DATA_DIR", value)
      None => @os.unsetenv("LEPUSA_APP_DATA_DIR")
    }
    match old_control {
      Some(value) => @os.setenv("MOONDESK_EXECUTION_SANDBOX_CONFIG", value)
      None => @os.unsetenv("MOONDESK_EXECUTION_SANDBOX_CONFIG")
    }
  }
  @os.setenv("LEPUSA_APP_DATA_DIR", app_data)
  @os.setenv("MOONDESK_EXECUTION_SANDBOX_CONFIG", config_path)
  let provider = @httpx.Server::new("127.0.0.1", 0)
  defer provider.close()
  let base = "http://127.0.0.1:\{provider.port()}"
  let token = "provider-fixture-long-lived-token"
  let calls = Ref(0)
  let router = @httpx.Router::new()
  router.add_handler(Post, "/mcp", (r, w) => {
    calls.val += 1
    assert_eq(r.headers.get("authorization"), Some("Bearer " + token))
    let body : Json = @httpx.JsonRequestReader::new(r).read()
    let method_ = mooncode_json_string(body, "method", default="")
    w.header().set("Content-Type", "application/json")
    if method_ == "notifications/initialized" {
      w.write_header(202)
      return
    }
    let response : Json = if method_ == "initialize" {
      {
        "jsonrpc": "2.0",
        "id": 1,
        "result": { "protocolVersion": "2025-11-25" },
      }
    } else {
      assert_eq(method_, "tools/list")
      {
        "jsonrpc": "2.0",
        "id": 2,
        "result": {
          "tools": [
            { "name": "fixture_echo", "inputSchema": { "type": "object" } },
          ],
        },
      }
    }
    w.write_header(200)
    w.write(response.stringify())
  })
  router.add_handler(Post, "/embeddings", (r, w) => {
    calls.val += 1
    assert_eq(r.headers.get("authorization"), Some("Bearer " + token))
    let body : Json = @httpx.JsonRequestReader::new(r).read()
    let data : Array[Json] = []
    for index in 0..<mooncode_json_array_items(body, "input").length() {
      data.push({ "index": index, "embedding": [1.0, 0.0] })
    }
    w.header().set("Content-Type", "application/json")
    w.write_header(200)
    w.write(({ "data": data } : Json).stringify())
  })
  router.add_handler(Post, "/v1/realtime/client_secrets", (r, w) => {
    calls.val += 1
    assert_eq(r.headers.get("authorization"), Some("Bearer " + token))
    let _ : Json = @httpx.JsonRequestReader::new(r).read()
    w.header().set("Content-Type", "application/json")
    w.write_header(200)
    w.write("{\"value\":\"fixture-ephemeral\",\"expires_at\":12345}")
  })
  let models_path = @moonsuite.product_artifact_for_workspace_root(
    root, "moonclaw", "models/models.json",
  )
  let model = @model.Model::new(
    name="fixture",
    model_name="fixture-model",
    api_key=token,
    base_url=base + "/v1",
    safe_zone_tokens=1000,
  )
  integration_fixture_write(models_path, [model.to_json()])
  for selected in [book, other] {
    integration_fixture_write(
      @moonsuite.product_artifact_for_workspace_root(
        selected, "moonclaw", "mcp-servers.json",
      ),
      { "servers": [{ "id": "fixture", "url": base + "/mcp", "token": token }] },
    )
    let embedding : Json = {
      "url": base + "/embeddings",
      "model": "fixture-embed",
      "token": token,
    }
    integration_fixture_write(
      @moonsuite.product_artifact_for_workspace_root(
        selected, "moonclaw", "knowledge-embeddings.json",
      ),
      embedding,
    )
    integration_fixture_write(selected + "/book/knowledge/library.json", [
      {
        "id": "fixture-source",
        "path": "knowledge.md",
        "title": "Fixture",
        "embedding_key": mooncode_embedding_key(embedding),
        "chunks": [
          {
            "text": "Automobiles transport passengers.",
            "start_line": 1,
            "end_line": 1,
            "embedding": [1.0, 0.0],
          },
        ],
      },
    ])
  }
  let daemon = integration_fixture_daemon(root)
  assert_true(daemon.models.get_model(name="fixture") is Some(_))
  defer daemon.httpx.close()
  let binding = daemon.mooncode_binding_for_session("fixture-session")
  assert_true(binding.bind_book_root(book))
  binding.model = "fixture"
  // Seed an existing durable session and ledger using synthetic fixture data only.
  integration_fixture_write(
    mooncode_session_snapshot_path(book, "fixture-session"),
    mooncode_session_snapshot(binding),
  )
  @fsx.make_directory(
    @pathx.dirname(mooncode_session_state_path(book, "fixture-session")),
    recursive=true,
    exists_ok=true,
  )
  @fsx.write_to_file(
    mooncode_session_state_path(book, "fixture-session"),
    "active\n",
  )
  @fsx.write_to_file(mooncode_session_journal_path(book, "fixture-session"), "")
  integration_fixture_write(
    mooncode_integration_binding_path(config, "fixture-session", ".json"),
    { "session_id": "fixture-session", "book_root": book },
  )
  let descriptor : Json = {
    "contract": "moondesk-claw-routes.loopback.v1",
    "synthetic": true,
    "port": daemon.port,
    "workspace_root": root,
    "book_root": book,
    "trusted_other_book_root": other,
    "untrusted_book_root": untrusted,
    "session_id": "fixture-session",
    "tool_name": "fixture_echo",
    "query": "vehicle",
    "knowledge_text": "Automobiles transport passengers.",
    "ephemeral_value": "fixture-ephemeral",
    "realtime_model": "gpt-realtime",
  }
  let fixture : IntegrationHttpFixture = {
    daemon,
    workspace: root,
    book,
    other,
    untrusted,
    config_path,
    config,
    descriptor,
    provider_calls: calls,
  }
  @async.with_task_group(group => {
    group.spawn_bg(() => provider.serve(router.handler()), no_wait=true)
    group.spawn_bg(
      () => {
        daemon.httpx.serve(
          @httpx.cors((r, w) => daemon.handle_http_request(group~, r, w)),
        )
      },
      no_wait=true,
    )
    let (code, response) = integration_fixture_post(fixture, "/v1/code/mcp", {
      "book_root": book,
      "session_id": "fixture-session",
    })
    assert_eq(code, 200, msg=response.stringify())
    run(fixture)
  })
}

///|
async fn integration_fixture_post(
  fixture : IntegrationHttpFixture,
  path : String,
  body : Json,
) -> (Int32, Json) {
  let (response, data) = @http.post(
    "http://127.0.0.1:\{fixture.daemon.port}\{path}",
    body.stringify(),
    headers={
      "X-MoonClaw-Execution-Token": fixture.config.auth_token,
      "X-MoonClaw-Instance-ID": fixture.config.instance_id,
    },
  )
  assert_eq(response.headers.get("cache-control"), Some("no-store"))
  if response.code < 400 {
    assert_eq(
      response.headers.get("x-moonclaw-instance-id"),
      Some(fixture.config.instance_id),
    )
  }
  let parsed = @json.parse(data.text())
  assert_false(parsed.stringify().contains(fixture.config.auth_token))
  assert_false(parsed.stringify().contains("provider-fixture-long-lived-token"))
  (response.code, parsed)
}

///|
async test "real integration routes enforce auth trust aliases immutable sessions and resource confinement" {
  with_integration_http_fixture(fixture => {
    for family in ["code", "mooncode"] {
      for endpoint in ["mcp", "knowledge", "realtime-session"] {
        let path = "/v1/" + family + "/" + endpoint
        let payload : Json = {
          "book_root": fixture.book,
          "session_id": "fixture-session",
        }
        let (ok, result) = integration_fixture_post(fixture, path, payload)
        assert_eq(ok, 200, msg=path + " " + result.stringify())
        assert_true(result is Object(_))
        if endpoint == "realtime-session" {
          assert_eq(
            mooncode_json_string(result, "value", default=""),
            "fixture-ephemeral",
          )
        }
        if endpoint == "mcp" {
          assert_eq(
            mooncode_json_string(result, "tool", default=""),
            "mcp_list_tools",
          )
        }
        let (missing, _) = @http.post(
          "http://127.0.0.1:\{fixture.daemon.port}\{path}",
          "not-json",
          headers=Map([]),
        )
        assert_eq(missing.code, 401)
        assert_eq(missing.headers.get("cache-control"), Some("no-store"))
        for
          headers in [
            {
              "X-MoonClaw-Execution-Token": "b".repeat(64),
              "X-MoonClaw-Instance-ID": fixture.config.instance_id,
            },
            {
              "X-MoonClaw-Execution-Token": fixture.config.auth_token,
              "X-MoonClaw-Instance-ID": "f".repeat(32),
            },
          ] {
          let (denied, _) = @http.post(
            "http://127.0.0.1:\{fixture.daemon.port}\{path}",
            payload.stringify(),
            headers~,
          )
          assert_eq(denied.code, 401)
        }
        let before = fixture.provider_calls.val
        for
          denied_root in [
            fixture.untrusted,
            fixture.book + "/descendant",
            fixture.workspace,
          ] {
          assert_eq(
            integration_fixture_post(fixture, path, { "book_root": denied_root }).0,
            403,
          )
        }
        assert_eq(
          integration_fixture_post(fixture, path, {
            "book_root": fixture.other,
            "session_id": "fixture-session",
          }).0,
          409,
        )
        assert_eq(
          integration_fixture_post(fixture, path, {
            "book_root": fixture.book,
            "session_id": "../escape",
          }).0,
          400,
        )
        assert_eq(fixture.provider_calls.val, before)
      }
      let (embedded, vectors) = integration_fixture_post(
        fixture,
        "/v1/" + family + "/knowledge",
        {
          "book_root": fixture.book,
          "action": "embed",
          "texts": ["one", "two"],
        },
      )
      assert_eq(embedded, 200)
      assert_true(mooncode_json_bool(vectors, "ok", default=false))
      assert_eq(mooncode_json_array_items(vectors, "vectors").length(), 2)
      let (retrieved, hits) = integration_fixture_post(
        fixture,
        "/v1/" + family + "/knowledge",
        { "book_root": fixture.book, "query": "vehicle" },
      )
      assert_eq(retrieved, 200)
      assert_eq(mooncode_json_string(hits, "retrieval", default=""), "hybrid")
      assert_eq(mooncode_json_array_items(hits, "hits").length(), 1)
    }
    let before = fixture.provider_calls.val
    // Fresh daemon state and separate non-/books product stores must retain one identity.
    fixture.daemon.mooncode_sessions.clear()
    assert_eq(
      integration_fixture_post(fixture, "/v1/code/mcp", {
        "book_root": fixture.other,
        "session_id": "fixture-session",
      }).0,
      409,
    )
    let only_other = {
      ..fixture.config,
      trusted_book_roots: Some([fixture.other]),
    }
    integration_fixture_write(fixture.config_path, only_other.to_json())
    assert_eq(
      integration_fixture_post(fixture, "/v1/code/mcp", {
        "book_root": fixture.other,
        "session_id": "fixture-session",
      }).0,
      409,
    )
    integration_fixture_write(fixture.config_path, fixture.config.to_json())
    assert_eq(fixture.provider_calls.val, before)
    let tampered = mooncode_session_snapshot_path(
      fixture.book,
      "fixture-session",
    )
    let original_snapshot = @book_runtime.read_resource(tampered).unwrap()
    integration_fixture_write(
      tampered,
      mooncode_json_object_with_field(
        @json.parse(original_snapshot),
        "session_id",
        Json("different-session"),
      ),
    )
    assert_eq(
      integration_fixture_post(fixture, "/v1/code/mcp", {
        "book_root": fixture.book,
        "session_id": "fixture-session",
      }).0,
      409,
    )
    assert_false(fixture.daemon.mooncode_sessions.contains("fixture-session"))
    @fsx.write_to_file(tampered, original_snapshot)
    // A pre-ledger snapshot from a separate trusted product store also blocks retargeting.
    let old_binding = fixture.daemon.mooncode_binding_for_session("pre-ledger")
    assert_true(old_binding.bind_book_root(fixture.book))
    integration_fixture_write(
      mooncode_session_snapshot_path(fixture.book, "pre-ledger"),
      mooncode_session_snapshot(old_binding),
    )
    fixture.daemon.mooncode_sessions.clear()
    assert_eq(
      integration_fixture_post(fixture, "/v1/code/mcp", {
        "book_root": fixture.other,
        "session_id": "pre-ledger",
      }).0,
      409,
    )
    let marker = mooncode_session_state_path(fixture.book, "fixture-session")
    @fsx.write_to_file(marker, "archived\n")
    assert_eq(
      integration_fixture_post(fixture, "/v1/code/mcp", {
        "book_root": fixture.book,
        "session_id": "fixture-session",
      }).0,
      409,
    )
    @fsx.write_to_file(marker, "active\n")
    // Final-file, parent, and broken local MCP symlinks must never become fallback reads.
    let outside = fixture.workspace + "/outside-resource.json"
    integration_fixture_write(outside, { "servers": [] })
    for
      (path, endpoint) in [
        (
          @moonsuite.product_artifact_for_workspace_root(
            fixture.book,
            "moonclaw",
            "mcp-servers.json",
          ),
          "mcp",
        ),
        (
          @moonsuite.product_artifact_for_workspace_root(
            fixture.book,
            "moonclaw",
            "knowledge-embeddings.json",
          ),
          "knowledge",
        ),
        (fixture.book + "/book/knowledge/library.json", "knowledge"),
      ] {
      @fs.rename(path, path + ".retained")
      @fs.symlink(path, target=outside)
      assert_eq(
        integration_fixture_post(fixture, "/v1/code/" + endpoint, {
          "book_root": fixture.book,
          "query": "vehicle",
        }).0,
        403,
      )
      @fs.rename(path, path + ".rejected-symlink")
      @fs.rename(path + ".retained", path)
    }
    let models = @moonsuite.product_artifact_for_workspace_root(
      fixture.workspace,
      "moonclaw",
      "models/models.json",
    )
    @fs.rename(models, models + ".retained")
    @fs.symlink(models, target=outside)
    assert_eq(
      integration_fixture_post(fixture, "/v1/code/realtime-session", {
        "book_root": fixture.book,
        "model": "fixture",
      }).0,
      403,
    )
    @fs.rename(models, models + ".rejected-symlink")
    @fs.rename(models + ".retained", models)
    assert_eq(fixture.provider_calls.val, before)
    let omitted = { ..fixture.config, trusted_book_roots: None, }
    integration_fixture_write(fixture.config_path, omitted.to_json())
    assert_eq(
      integration_fixture_post(fixture, "/v1/code/mcp", {
        "book_root": fixture.book,
      }).0,
      403,
    )
    let duplicate = {
      ..fixture.config,
      trusted_book_roots: Some([fixture.book, fixture.book]),
    }
    integration_fixture_write(fixture.config_path, duplicate.to_json())
    assert_eq(
      integration_fixture_post(fixture, "/v1/code/mcp", {
        "book_root": fixture.book,
      }).0,
      503,
    )
    integration_fixture_write(fixture.config_path, fixture.config.to_json())
    @fs.chmod(fixture.config_path, 0o644)
    assert_eq(
      integration_fixture_post(fixture, "/v1/code/mcp", {
        "book_root": fixture.book,
      }).0,
      503,
    )
    @fs.chmod(fixture.config_path, 0o600)
    @os.unsetenv("MOONDESK_EXECUTION_SANDBOX_CONFIG")
    assert_eq(
      integration_fixture_post(fixture, "/v1/code/mcp", {
        "book_root": fixture.book,
      }).0,
      503,
    )
    @os.setenv("MOONDESK_EXECUTION_SANDBOX_CONFIG", fixture.config_path)
    @async.with_task_group(group => {
      let a = group.spawn(() => {
        integration_fixture_post(fixture, "/v1/code/mcp", {
          "book_root": fixture.book,
          "session_id": "simultaneous",
        }).0
      })
      let b = group.spawn(() => {
        integration_fixture_post(fixture, "/v1/code/mcp", {
          "book_root": fixture.other,
          "session_id": "simultaneous",
        }).0
      })
      let results = [a.wait(), b.wait()]
      assert_eq(results, [409, 409])
    })
  })
}

///|
async test "cold daemon preserves shared suite Book binding and suite-owned resource fallback" {
  with_integration_http_fixture(
    fixture => {
      let restarted = integration_fixture_daemon(fixture.workspace)
      defer restarted.httpx.close()
      let cold = { ..fixture, daemon: restarted, }
      @async.with_task_group(group => {
        group.spawn_bg(
          () => {
            restarted.httpx.serve(
              @httpx.cors((r, w) => restarted.handle_http_request(group~, r, w)),
            )
          },
          no_wait=true,
        )
        assert_eq(
          integration_fixture_post(cold, "/v1/code/mcp", {
            "book_root": fixture.book,
            "session_id": "fixture-session",
          }).0,
          200,
        )
        assert_eq(
          integration_fixture_post(cold, "/v1/mooncode/mcp", {
            "book_root": fixture.other,
            "session_id": "fixture-session",
          }).0,
          409,
        )
      })
    },
    standard_books=true,
  )
}

///|
async test "unrecorded supplied identities never create state or reach providers" {
  with_integration_http_fixture(fixture => {
    let memory = fixture.daemon.mooncode_binding_for_session("memory-only")
    assert_true(memory.bind_book_root(fixture.book))
    for id in ["legacy-only", "removed-root-only"] {
      let legacy = fixture.daemon.mooncode_binding_for_session(id)
      assert_true(legacy.bind_book_root(fixture.book))
      integration_fixture_write(
        mooncode_session_snapshot_path(fixture.book, id),
        mooncode_session_snapshot(legacy),
      )
      fixture.daemon.mooncode_sessions.remove(id)
    }
    let legacy_path = mooncode_session_snapshot_path(
      fixture.book,
      "legacy-only",
    )
    let legacy_before = @fsx.read_file(legacy_path)
    let removed_path = mooncode_session_snapshot_path(
      fixture.book,
      "removed-root-only",
    )
    let removed_before = @fsx.read_file(removed_path)
    let before = fixture.provider_calls.val
    for family in ["code", "mooncode"] {
      for endpoint in ["mcp", "knowledge", "realtime-session"] {
        let route = "/v1/" + family + "/" + endpoint
        for id in ["fresh-unrecorded", "memory-only", "legacy-only"] {
          let (code, result) = integration_fixture_post(fixture, route, {
            "book_root": fixture.book,
            "session_id": id,
          })
          assert_eq(code, 409, msg=result.stringify())
          assert_true(
            result.stringify().contains("Session has no recorded Book binding"),
          )
        }
        for invalid in [Json(""), Json::null(), Json(42)] {
          assert_eq(
            integration_fixture_post(fixture, route, {
              "book_root": fixture.book,
              "session_id": invalid,
            }).0,
            400,
          )
        }
      }
    }
    integration_fixture_write(
      fixture.config_path,
      { ..fixture.config, trusted_book_roots: Some([fixture.other]), }.to_json(),
    )
    fixture.daemon.mooncode_sessions.clear()
    for family in ["code", "mooncode"] {
      for endpoint in ["mcp", "knowledge", "realtime-session"] {
        assert_eq(
          integration_fixture_post(fixture, "/v1/" + family + "/" + endpoint, {
            "book_root": fixture.other,
            "session_id": "removed-root-only",
          }).0,
          409,
        )
      }
    }
    assert_eq(fixture.provider_calls.val, before)
    assert_eq(@fsx.read_file(legacy_path), legacy_before)
    assert_eq(@fsx.read_file(removed_path), removed_before)
    for
      id in [
        "fresh-unrecorded", "memory-only", "legacy-only", "removed-root-only",
      ] {
      assert_false(fixture.daemon.mooncode_sessions.contains(id))
      for suffix in [".json", ".lock"] {
        assert_false(
          @fsx.exists(
            mooncode_integration_binding_path(fixture.config, id, suffix),
          ),
        )
      }
      for book in [fixture.book, fixture.other] {
        for
          path in [
            mooncode_session_lock_path(book, id),
            mooncode_session_lifecycle_gate_path(book, id),
            mooncode_session_state_path(book, id),
            mooncode_session_journal_path(book, id),
          ] {
          assert_false(@fsx.exists(path), msg=path)
        }
        if book == fixture.other ||
          id == "fresh-unrecorded" ||
          id == "memory-only" {
          assert_false(@fsx.exists(mooncode_session_dir_by_safe_id(book, id)))
        }
      }
    }
  })
}

///|
async test "recorded binding must parse and match exact supplied identity and Book" {
  with_integration_http_fixture(fixture => {
    let ledger = mooncode_integration_binding_path(
      fixture.config,
      "fixture-session",
      ".json",
    )
    let original = @fsx.read_file(ledger)
    let before = fixture.provider_calls.val
    for
      invalid in [
        Json::null(),
        Json::empty_object(),
        { "session_id": "fixture-session" },
        { "session_id": "different", "book_root": fixture.book },
        { "session_id": "fixture-session", "book_root": fixture.other },
      ] {
      integration_fixture_write(ledger, invalid)
      assert_eq(
        integration_fixture_post(fixture, "/v1/code/mcp", {
          "book_root": fixture.book,
          "session_id": "fixture-session",
        }).0,
        409,
      )
    }
    @fsx.write_to_file(ledger, "{")
    assert_eq(
      integration_fixture_post(fixture, "/v1/mooncode/mcp", {
        "book_root": fixture.book,
        "session_id": "fixture-session",
      }).0,
      409,
    )
    @fsx.write_to_file(ledger, original)
    assert_eq(fixture.provider_calls.val, before)
    assert_eq(
      integration_fixture_post(fixture, "/v1/code/mcp", {
        "book_root": fixture.book,
        "session_id": "fixture-session",
      }).0,
      200,
    )
  })
}

///|
#skip("Explicit cross-repository Desk HTTP qualification with the synthetic owner/provider fixture")
async test "Desk control transport uses the actual admitted Claw route owner" {
  guard @os.getenv("CHECKPOINT23_DESK_ROOT") is Some(desk) else {
    fail("CHECKPOINT23_DESK_ROOT is required")
  }
  guard @os.getenv("MOON_HOME") is Some(moon_home) else {
    fail("Pinned MOON_HOME is required")
  }
  guard @os.getenv("CHECKPOINT23_EVIDENCE_ROOT") is Some(evidence) else {
    fail("CHECKPOINT23_EVIDENCE_ROOT is required")
  }
  with_integration_http_fixture(fixture => {
    @fsx.write_to_file(
      evidence + "/actual-desk-fixture.json",
      fixture.descriptor.stringify(indent=2),
    )
    let (code, stdout, stderr) = @async.with_timeout(1200000, () => {
      @process.collect_output(
        moon_home + "/bin/moon",
        [
          "test", "internal/moonwiki/mooncode_routes_owner_http_wbtest.mbt", "--target",
          "native", "--strip", "-j", "2", "--include-skipped",
        ],
        cwd=desk,
        extra_env={
          "MOONDESK_CLAW_ROUTES_FIXTURE": fixture.descriptor.stringify(),
          "RUST_LOG": "error",
        },
      )
    })
    let log = stdout.text() + stderr.text()
    @fsx.write_to_file(evidence + "/actual-desk-http-tests.log", log)
    assert_eq(code, 0, msg=log)
    assert_true(log.contains("Total tests: 2, passed: 2, failed: 0."))
  })
}
