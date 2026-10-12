///|
fn live_ui_fixture() -> Model {
  let owner = UiCommandLiveOwner::{
    output_id: "output-1",
    run_id: "run-1",
    step_id: "step-1",
  }
  let snapshot = {
    ..test_canvas_snapshot([]),
    linked_remote: [
      {
        id: owner.output_id,
        kind: "fort-command-live-output",
        title: "Live command",
        status: "bound",
        summary: None,
        detail: None,
        metadata: owner.to_json(),
      },
    ],
  }
  {
    ..init_model(),
    route: Run("run-1"),
    selected_run_id: Some("run-1"),
    snapshot: Some(snapshot),
    command_live_generation: 7,
    command_live_view: Some({
      owner,
      cursor: "start",
      carry: "",
      text: "",
      notice: "",
      paused: false,
      pending: true,
      terminal: false,
      binary: false,
      truncated: false,
    }),
  }
}

///|
fn live_ui_chunk(
  content : String,
  offset : Int,
  next : Int,
  terminal? : Bool = false,
) -> UiCommandLiveChunk {
  {
    protocol_version: 1,
    output_id: "output-1",
    run_id: "run-1",
    step_id: "step-1",
    stream_id: "a".repeat(64),
    offset,
    next_offset: next,
    available_bytes: next,
    content_base64: content,
    status: if terminal {
      "killed"
    } else {
      "running"
    },
    terminal,
    retry_after_ms: 100,
    next_cursor: "a".repeat(64) + ":" + next.to_string(),
  }
}

///|
test "live display preserves split UTF8 and escapes binary without HTML execution" {
  let first : LiveDisplayPart = @json.from_json(
    @json.parse(decode_live_display("4oI=", "", false)),
  )
  assert_eq(first.text, "")
  assert_eq(first.carry, "4oI=")
  let second : LiveDisplayPart = @json.from_json(
    @json.parse(decode_live_display("rAA8c2NyaXB0Pv8=", first.carry, false)),
  )
  assert_eq(second.text, "€[0x00]<script>�")
  assert_true(second.binary)
  assert_eq(second.carry, "")
  let last : LiveDisplayPart = @json.from_json(
    @json.parse(decode_live_display("", first.carry, true)),
  )
  assert_eq(last.text, "�")
  let initial = live_ui_fixture()
  let rendered = {
    ..initial,
    command_live_view: Some({
      ..initial.command_live_view.unwrap(),
      text: second.text,
      binary: true,
    }),
  }
  let html = @rabbita.render_to_string(
    @rabbita.static_cell(
      render_command_live_view(@cmd.Emit(_ => @rabbita.none), rendered),
    ),
  )
  assert_true(html.contains("&lt;script&gt;"))
  assert_false(html.contains("<script>"))
  assert_true(html.contains("invalid UTF-8 is replaced"))
}

///|
test "tail resume cursor replay stale navigation and empty reads never complete a run" {
  let initial = live_ui_fixture()
  let original_status = initial.snapshot.unwrap().run.status
  let first = artifact_test_update(
    initial,
    CommandLiveRead(
      7,
      "start",
      live_ui_chunk("YWJj", 0, 3).to_json().stringify(),
    ),
  )
  assert_eq(first.command_live_view.unwrap().text, "abc")
  assert_eq(first.snapshot.unwrap().run.status, original_status)
  let replay = artifact_test_update(
    first,
    CommandLiveRead(
      7,
      "start",
      live_ui_chunk("YWJj", 0, 3).to_json().stringify(),
    ),
  )
  assert_eq(replay.command_live_view.unwrap().text, "abc")
  let paused = artifact_test_update(first, PauseCommandLive)
  assert_true(paused.command_live_view.unwrap().paused)
  let resumed = artifact_test_update(paused, ResumeCommandLive)
  assert_true(resumed.command_live_view.unwrap().pending)
  let stale = artifact_test_update(
    resumed,
    CommandLiveRead(
      7,
      "start",
      live_ui_chunk("bGF0ZQ==", 0, 4).to_json().stringify(),
    ),
  )
  assert_eq(stale.command_live_view.unwrap().text, "abc")
  let cursor = resumed.command_live_view.unwrap().cursor
  let empty = artifact_test_update(
    resumed,
    CommandLiveRead(
      resumed.command_live_generation,
      cursor,
      live_ui_chunk("", 3, 3).to_json().stringify(),
    ),
  )
  assert_false(empty.command_live_view.unwrap().terminal)
  assert_eq(empty.snapshot.unwrap().run.status, original_status)
  let polling = artifact_test_update(
    empty,
    PollCommandLive(empty.command_live_generation),
  )
  let empty_replay = artifact_test_update(
    polling,
    CommandLiveRead(
      empty.command_live_generation,
      cursor,
      live_ui_chunk("", 3, 3).to_json().stringify(),
    ),
  )
  assert_true(empty_replay.command_live_view.unwrap().pending)
  assert_eq(
    empty_replay.command_live_generation,
    polling.command_live_generation,
  )
  let failed = artifact_test_update(
    polling,
    CommandLiveRead(polling.command_live_generation, cursor, "{}"),
  )
  assert_true(failed.command_live_view.unwrap().paused)
  assert_eq(failed.command_live_view.unwrap().cursor, cursor)
  let moved = artifact_test_update(polling, SelectRun("run-2"))
  assert_true(moved.command_live_view is None)
  let late = artifact_test_update(
    moved,
    CommandLiveRead(
      polling.command_live_generation,
      cursor,
      live_ui_chunk("", 3, 3, terminal=true).to_json().stringify(),
    ),
  )
  assert_true(late.command_live_view is None)
  let terminal = artifact_test_update(
    polling,
    CommandLiveRead(
      polling.command_live_generation,
      cursor,
      live_ui_chunk("", 3, 3, terminal=true).to_json().stringify(),
    ),
  )
  assert_true(terminal.command_live_view.unwrap().terminal)
  assert_true(
    terminal.command_live_view.unwrap().notice.contains("not job success"),
  )
  assert_eq(terminal.snapshot.unwrap().run.status, original_status)
}

///|
test "live UI refuses cross-run stream cursor bounds and length mismatch" {
  let initial = live_ui_fixture()
  let good = live_ui_chunk("YWJj", 0, 3)
  for
    bad in [
      { ..good, run_id: "run-2", },
      { ..good, output_id: "output-2", },
      { ..good, step_id: "step-2", },
      { ..good, offset: 1, },
      { ..good, next_offset: 2, },
      { ..good, available_bytes: 67108865, },
      { ..good, content_base64: "!!!!", },
      { ..good, protocol_version: 9, },
      { ..good, terminal: true, },
      { ..good, next_cursor: "bad", },
    ] {
    let result = artifact_test_update(
      initial,
      CommandLiveRead(7, "start", bad.to_json().stringify()),
    )
    assert_eq(result.command_live_view.unwrap().text, "")
    assert_true(result.command_live_view.unwrap().paused)
  }
  let capped = {
    ..initial,
    command_live_view: Some({
      ..initial.command_live_view.unwrap(),
      text: "x".repeat(65536),
    }),
  }
  let result = artifact_test_update(
    capped,
    CommandLiveRead(7, "start", good.to_json().stringify()),
  )
  assert_eq(result.command_live_view.unwrap().text.length(), 65536)
  assert_true(result.command_live_view.unwrap().text.has_suffix("abc"))
  assert_true(result.command_live_view.unwrap().truncated)
  let cleared = artifact_test_update(result, ClearGatewayToken)
  assert_true(cleared.command_live_view is None)
}

///|
test "terminal live read preserves RunCanvas and Cowork navigation and tail" {
  let initial = live_ui_fixture()
  let snapshot = initial.snapshot.unwrap()
  let detail = {
    ..cowork_request_test_session("thread-1"),
    linked_run: Some({
      id: snapshot.run.id,
      job_id: snapshot.run.job_id,
      status: snapshot.run.status,
      summary: None,
      error: None,
      current_step_id: None,
      workspace_dir: None,
    }),
  }
  for
    model in [
      { ..initial, route: RunCanvas("run-1"), },
      {
        ..initial,
        route: Cowork,
        selected_cowork_session_key: Some("thread-1"),
        cowork_detail: Some(detail),
        cowork_linked_snapshot: Some(snapshot),
      },
    ] {
    let result = artifact_test_update(
      model,
      CommandLiveRead(
        7,
        "start",
        live_ui_chunk("YWJj", 0, 3, terminal=true).to_json().stringify(),
      ),
    )
    assert_true(result.route == model.route)
    assert_eq(result.command_live_view.unwrap().text, "abc")
    assert_true(result.command_live_view.unwrap().terminal)
    assert_eq(
      result.snapshot.unwrap().run.status,
      model.snapshot.unwrap().run.status,
    )
  }
}

///|
test "complete download handoff requires a separate verified terminal snapshot" {
  let initial = live_ui_fixture()
  let terminal = artifact_test_update(
    initial,
    CommandLiveRead(
      7,
      "start",
      live_ui_chunk("YWJj", 0, 3, terminal=true).to_json().stringify(),
    ),
  )
  let render = model => {
    @rabbita.render_to_string(
      @rabbita.static_cell(
        render_command_live_view(@cmd.Emit(_ => @rabbita.none), model),
      ),
    )
  }
  assert_false(render(terminal).contains("Download retained output"))
  let snapshot = command_output_test_snapshot()
  let remote = snapshot.linked_remote[0]
  let output = selected_command_output(snapshot, remote.id).unwrap()
  let matching = { ..output, output_id: "output-1", }
  let ready = {
    ..terminal,
    snapshot: Some({
      ..terminal.snapshot.unwrap(),
      linked_remote: [
        ..terminal.snapshot.unwrap().linked_remote,
        { ..remote, id: "output-1", metadata: matching.to_json(), },
      ],
    }),
  }
  assert_true(render(ready).contains("Download retained output"))
  let pending = artifact_test_update(ready, DownloadCommandOutput("output-1"))
  assert_eq(pending.artifact_download_pending, Some("command-output:output-1"))
}

///|
#cfg(target="js")
extern "js" fn live_test_late_body(
  install : (String) -> Unit,
  read : (String, String, String, String) -> @js.Promise,
  invalidate : () -> Unit,
  accept : (String) -> Bool,
  raw : String,
) -> @js.Promise =
  #| async (install, read, invalidate, accept, raw) => {
  #|   const originalFetch = globalThis.fetch, originalTransport = globalThis.__moonclawTransport;
  #|   let controller, started; const bodyStarted = new Promise(resolve => started = resolve);
  #|   try {
  #|     delete globalThis.__moonclawTransport;
  #|     globalThis.fetch = async () => new Response(new ReadableStream({ start(c) { controller = c; c.enqueue(new TextEncoder().encode(raw.slice(0, 10))); started(); } }), {status:200});
  #|     install("http://127.0.0.1:49999"); globalThis.__moonclawTransport.setToken("http://127.0.0.1:49999", "fixture-token");
  #|     const pending = read("http://127.0.0.1:49999", "run-1", "output-1", "start");
  #|     await bodyStarted; await Promise.resolve(); invalidate();
  #|     // Deliberately ignore AbortSignal as a hostile/late transport can.
  #|     controller.enqueue(new TextEncoder().encode(raw.slice(10))); controller.close();
  #|     const late = await pending;
  #|     if (!accept(late)) throw new Error("Late body appended after token invalidation");
  #|     return "LATE_BODY_CONTEXT_PASSED";
  #|   } finally { globalThis.__moonclawTransport?.clear(); globalThis.__moonclawTransport = originalTransport; globalThis.fetch = originalFetch; }
  #| }

///|
test "token change while live HTTP body streams cannot append late output" {
  @js.async_test(() => {
    let model = Ref(live_ui_fixture())
    let result : String = live_test_late_body(
        configure_gateway_transport,
        browser_read_command_live,
        () => model.val = artifact_test_update(model.val, ClearGatewayToken),
        raw => {
          model.val = artifact_test_update(
            model.val,
            CommandLiveRead(7, "start", raw),
          )
          model.val.command_live_view is None
        },
        live_ui_chunk("YWJj", 0, 3).to_json().stringify(),
      )
      .wait()
      .cast()
    assert_eq(result, "LATE_BODY_CONTEXT_PASSED")
  })
}
