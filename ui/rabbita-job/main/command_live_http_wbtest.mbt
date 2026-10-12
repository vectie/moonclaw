///|
#cfg(target="js")
extern "js" fn test_live_native_flow(
  install : (String) -> Unit,
  read : (String, String, String, String) -> @js.Promise,
  accept : (String, String) -> String,
) -> @js.Promise =
  #| async (install, read, accept) => {
  #|   const base = process.env.MOONCLAW_HTTP_FIXTURE_URL, output = process.env.MOONCLAW_LIVE_FIXTURE_OUTPUT;
  #|   if (!/^http:\/\/127\.0\.0\.1:\d+$/.test(base || "") || !output) throw new Error("Native live fixture required");
  #|   const check = (ok, why) => { if (!ok) throw new Error(why); }, originalFetch = globalThis.fetch, originalStorage = globalThis.sessionStorage;
  #|   const storage = new Map(); globalThis.sessionStorage = {getItem:k => storage.get(k), setItem:(k,v) => storage.set(k,v)};
  #|   try {
  #|     delete globalThis.__moonclawTransport; install(base); globalThis.__moonclawTransport.setToken(base, "fixture-only-token");
  #|     const snapshot = await (await fetch(base + "/v1/jobs/runs/run-1/ui")).text();
  #|     let state = JSON.parse(accept("snapshot", snapshot)); check(state.found && state.run_status === "Running", "bound command discoverable while analysis run is running");
  #|     const first = await read(base, "run-1", output, "start");
  #|     state = JSON.parse(accept("chunk", first));
  #|     check(state.text === "prefix<safe>\n" && state.carry === "4oI=" && !state.terminal, "actual native bytes rendered preterminal and split UTF8 retained");
  #|     check(state.html.includes("&lt;safe&gt;") && state.html.includes("Pause tail"), "shipped escaped tail UI rendered");
  #|     const cursor = state.cursor;
  #|     accept("pause", ""); const stale = JSON.parse(accept("stale", first)); check(stale.cursor === cursor && stale.text === state.text, "late paused response ignored");
  #|     const append = await fetch(base + "/fixture/append", {method:"POST", headers:{Authorization:"Bearer fixture-only-token"}}); check(append.status === 204, "fixture appended after first live read");
  #|     state = JSON.parse(accept("reload", "")); check(state.cursor === cursor && state.carry === "4oI=" && state.text === "", "actual session cursor and UTF8 carry resume after reload");
  #|     const second = await read(base, "run-1", output, cursor), replay = await read(base, "run-1", output, cursor);
  #|     check(second === replay, "native cursor replay is byte-identical");
  #|     state = JSON.parse(accept("chunk", second)); check(state.text === "€[0x00]�tail\n" && state.binary && !state.terminal, "appended split UTF8 and binary pass native reader gateway UI");
  #|     const accepted = JSON.parse(accept("stale", second)); check(accepted.text === state.text && accepted.cursor === state.cursor, "duplicate response does not duplicate text");
  #|     const tailCursor = state.cursor; accept("resume", "");
  #|     const empty = await read(base, "run-1", output, tailCursor); state = JSON.parse(accept("chunk", empty));
  #|     check(!state.terminal && state.run_status === "Running", "empty native read does not succeed job");
  #|     const wrong = JSON.parse(await read(base, "other-run", output, "start")); check(typeof wrong.error === "string", "cross-run read denied");
  #|     const finish = await fetch(base + "/fixture/terminal", {method:"POST", headers:{Authorization:"Bearer fixture-only-token"}}); check(finish.status === 204, "fixture terminal state recorded separately");
  #|     accept("resume", ""); state = JSON.parse(accept("chunk", await read(base, "run-1", output, tailCursor)));
  #|     check(state.terminal && state.run_status === "Running" && state.html.includes("not job success"), "native killed terminal stream preserves independent job state");
  #|     const cancelled = JSON.parse(await (await fetch(base + "/v1/jobs/runs/run-1/ui")).text()).snapshot;
  #|     check(cancelled.run.status === "Cancelled", "authoritative cancellation comes from run snapshot");
  #|     globalThis.__moonclawTransport.clear();
  #|     check(JSON.parse(await read(base, "run-1", output, tailCursor)).error.includes("token"), "authentication required for cursor resume");
  #|     return "ACTUAL_FORT_LIVE_CLAW_UI_PASSED";
  #|   } finally { globalThis.__moonclawTransport?.clear(); delete globalThis.__moonclawTransport; globalThis.fetch = originalFetch; globalThis.sessionStorage = originalStorage; }
  #| }

///|
#skip("Run only through the native live Fort/Claw authenticated fixture")
test "shipped live viewer tails appended native Fort bytes before terminal receipt" {
  @js.async_test(() => {
    let model = Ref(live_ui_fixture())
    let stale_generation = Ref(0)
    let stale_cursor = Ref("start")
    let result : String = test_live_native_flow(
        configure_gateway_transport,
        browser_read_command_live,
        (action, raw) => {
          match action {
            "snapshot" => {
              let json = @json.parse(raw) catch { _ => abort("snapshot JSON") }
              guard parse_snapshot_payload(json) is Ok(snapshot) else {
                abort("snapshot decode")
              }
              let output = snapshot.linked_remote.filter(item => {
                  item.kind == "fort-command-live-output"
                })[0]
              let owner = selected_command_live_output(snapshot, output.id).unwrap()
              model.val = {
                ..model.val,
                snapshot: Some(snapshot),
                command_live_view: Some({
                  ..model.val.command_live_view.unwrap(),
                  owner,
                }),
              }
            }
            "chunk" => {
              let view = model.val.command_live_view.unwrap()
              stale_generation.val = model.val.command_live_generation
              stale_cursor.val = view.cursor
              model.val = artifact_test_update(
                model.val,
                CommandLiveRead(stale_generation.val, view.cursor, raw),
              )
            }
            "pause" =>
              model.val = artifact_test_update(model.val, PauseCommandLive)
            "resume" =>
              model.val = artifact_test_update(model.val, ResumeCommandLive)
            "stale" =>
              model.val = artifact_test_update(
                model.val,
                CommandLiveRead(stale_generation.val, stale_cursor.val, raw),
              )
            "reload" => {
              let id = model.val.command_live_view.unwrap().owner.output_id
              model.val = artifact_test_update(
                invalidate_command_live(model.val),
                TailCommandOutput(id),
              )
            }
            _ => abort("unknown fixture action")
          }
          let view = model.val.command_live_view.unwrap()
          (
            {
              "found": true,
              "run_status": normalize_status(
                model.val.snapshot.unwrap().run.status,
              ),
              "text": view.text,
              "carry": view.carry,
              "cursor": view.cursor,
              "terminal": view.terminal,
              "binary": view.binary,
              "html": @rabbita.render_to_string(
                @rabbita.static_cell(
                  render_command_live_view(
                    @cmd.Emit(_ => @rabbita.none),
                    model.val,
                  ),
                ),
              ),
            } : Json).stringify()
        },
      )
      .wait()
      .cast()
    assert_eq(result, "ACTUAL_FORT_LIVE_CLAW_UI_PASSED")
    println(result)
  })
}
