///|
async test "canonical watch wakes on a committed append and reconnects without replay" {
  @fsx.with_temporary_directory("mooncode-canonical-watch-XXXXXX", async fn(
    root,
  ) {
    let session = "watch-session"
    let daemon = mooncode_control_test_daemon(root)
    defer daemon.httpx.close()
    mooncode_management_test_create_session(daemon, root, session)
    let initial = daemon.mooncode_watch_response(
      root,
      session,
      MoonCodeJournalSequence::zero(),
      0,
      25,
    )
    assert_true(mooncode_json_bool(initial, "changed", default=false))
    let since = mooncode_journal_cursor_parse(
      mooncode_json_string(initial, "revision", default=""),
    )
    let heartbeat = daemon.mooncode_watch_response(root, session, since, 0, 25)
    assert_true(mooncode_json_bool(heartbeat, "heartbeat", default=false))
    assert_true(
      mooncode_journal_json_field(heartbeat, "snapshot") is Some(Null),
    )
    @async.with_task_group(group => {
      let watch = group.spawn(() => {
        daemon.mooncode_watch_response(root, session, since, 1000, 25)
      })
      @async.sleep(50)
      mooncode_append_session_journal(root, session, "event", {
        "id": "watch-result",
        "kind": "runtime.planner_selected",
        "command_id": "cmd-1",
        "created_at": "2026-11-05T00:00:00Z",
        "status": "running",
      })
      let advanced = watch.wait()
      assert_eq(
        mooncode_json_string(advanced, "revision", default=""),
        since.next().text(),
      )
      assert_true(mooncode_json_bool(advanced, "changed", default=false))
      let next = mooncode_journal_cursor_parse(
        mooncode_json_string(advanced, "revision", default=""),
      )
      let resumed = daemon.mooncode_watch_response(root, session, next, 0, 25)
      assert_true(
        mooncode_journal_json_field(resumed, "snapshot") is Some(Null),
      )
    })
  })
}

///|
async test "native watch HTTP uses the admitted session route and exact snapshot contract" {
  with_integration_http_fixture(async fn(fixture) {
    let url = "http://127.0.0.1:\{fixture.daemon.port}/v1/code/sessions/fixture-session/watch?book_root=\{fixture.book}&wait_ms=0"
    let (denied, _) = @http.get(url)
    assert_eq(denied.code, 401)
    mooncode_append_session_journal(
      fixture.book,
      "fixture-session",
      "command",
      mooncode_claim_projection_command(fixture.book, "fixture-session"),
    )
    let headers = {
      "X-MoonClaw-Execution-Token": fixture.config.auth_token,
      "X-MoonClaw-Instance-ID": fixture.config.instance_id,
    }
    let (response, data) = @http.get(url, headers~)
    assert_eq(response.code, 200)
    let snapshot = @json.parse(data.text())
    assert_eq(
      mooncode_json_string(snapshot, "contract_id", default=""),
      "moonsuite-conversation-watch.v2",
    )
    assert_eq(mooncode_json_string(snapshot, "revision", default=""), "1")
    assert_eq(
      mooncode_json_string(
        mooncode_json_object_field_or_empty(snapshot, "snapshot"),
        "session_id",
        default="",
      ),
      "fixture-session",
    )
    let (response, data) = @http.get(url + "&since_revision=1", headers~)
    assert_eq(response.code, 200)
    let heartbeat = @json.parse(data.text())
    assert_true(mooncode_json_bool(heartbeat, "heartbeat", default=false))
    assert_true(
      mooncode_journal_json_field(heartbeat, "snapshot") is Some(Null),
    )
  })
}
