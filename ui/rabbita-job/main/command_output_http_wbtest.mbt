///|
#cfg(target="js")
extern "js" fn test_command_output_gateway(
  install : (String) -> Unit,
  verify_snapshot : (String) -> Bool,
) -> @js.Promise =
  #| async (install, verifySnapshot) => {
  #|   const base = process.env.MOONCLAW_HTTP_FIXTURE_URL;
  #|   if (!base || !/^http:\/\/127\.0\.0\.1:\d+$/.test(base)) throw new Error("Native gateway fixture required");
  #|   const check = (ok, why) => { if (!ok) throw new Error(why); };
  #|   const originalFetch = globalThis.fetch, originalDocument = globalThis.document;
  #|   const create = URL.createObjectURL, revoke = URL.revokeObjectURL, timer = globalThis.setTimeout;
  #|   const blobs = [], clicks = [];
  #|   try {
  #|     delete globalThis.__moonclawTransport; install(base);
  #|     const transport = globalThis.__moonclawTransport;
  #|     transport.setToken(base, "fixture-only-token");
  #|     const read = await fetch(base + "/v1/jobs/runs/run-1/ui"); check(read.ok, "native run loaded");
  #|     const rawSnapshot = await read.text();
  #|     check(verifySnapshot(rawSnapshot), "native payload reaches shipped MoonBit snapshot decoder and command-output action");
  #|     const snapshot = JSON.parse(rawSnapshot).snapshot;
  #|     const output = snapshot.linked_remote.find(r => r.kind === "fort-command-output");
  #|     check(output?.metadata.run_id === "run-1" && output?.metadata.output_id === "run-fort-cross-product", "actual retained output projected into run");
  #|     check(!JSON.stringify(output).includes("signature") && !JSON.stringify(output).includes("artifact_signing_key"), "capability stays at trusted host");
  #|     globalThis.document = { body: { appendChild() {} }, createElement() { return { click() { clicks.push(this.download); }, remove() {} }; } };
  #|     URL.createObjectURL = blob => { blobs.push(blob); return "blob:fort-output-fixture"; }; URL.revokeObjectURL = () => {};
  #|     globalThis.setTimeout = (fn, ms) => ms === 30000 ? timer(fn, 0) : timer(fn, ms);
  #|     const result = JSON.parse(await transport.download(base, "run-1", output.id, transport.downloadEpoch(), "command-outputs"));
  #|     check(result.ok && clicks.length === 1, "browser saved actual Fort download");
  #|     const expected = [70,111,114,116,0,255,128,192,254,10,101,120,97,99,116];
  #|     check(String(new Uint8Array(await blobs[0].arrayBuffer())) === String(expected), "Fort signed raw bytes survive process HTTP Blob save boundary");
  #|     const repeated = JSON.parse(await transport.download(base, "run-1", output.id, transport.downloadEpoch(), "command-outputs"));
  #|     check(repeated.ok && clicks.length === 2, "duplicate reads are safe");
  #|     const wrong = JSON.parse(await transport.download(base, "other-run", output.id, transport.downloadEpoch(), "command-outputs"));
  #|     check(!wrong.ok && clicks.length === 2, "wrong run cannot download another run output");
  #|     const ticket = transport.downloadEpoch(); transport.cancel();
  #|     const cancelled = JSON.parse(await transport.download(base, "run-1", output.id, ticket, "command-outputs"));
  #|     check(!cancelled.ok && clicks.length === 2, "cancel before deferred download does not save");
  #|     transport.clear();
  #|     const denied = JSON.parse(await transport.download(base, "run-1", output.id, transport.downloadEpoch(), "command-outputs"));
  #|     check(!denied.ok && denied.error.includes("token"), "cleared gateway token denied");
  #|     return "ACTUAL_FORT_CLAW_UI_PASSED";
  #|   } finally {
  #|     globalThis.__moonclawTransport?.clear(); delete globalThis.__moonclawTransport;
  #|     globalThis.fetch = originalFetch; globalThis.document = originalDocument;
  #|     URL.createObjectURL = create; URL.revokeObjectURL = revoke; globalThis.setTimeout = timer;
  #|   }
  #| }

///|
#skip("Run through the native Fort/Claw fixture, which supplies an isolated authenticated gateway")
test "shipped UI downloads actual Fort retained binary through authenticated Claw gateway" {
  @js.async_test(() => {
    let value : String = test_command_output_gateway(
        configure_gateway_transport,
        raw => {
          let json = @json.parse(raw) catch { _ => return false }
          guard parse_snapshot_payload(json) is Ok(snapshot) &&
            selected_command_output(snapshot, "run-fort-cross-product")
            is Some(output) &&
            output.run_id == "run-1" &&
            output.status == "available" else {
            return false
          }
          let html = @rabbita.render_to_string(
            @rabbita.static_cell(
              render_command_outputs(@cmd.Emit(_ => @rabbita.none), snapshot),
            ),
          )
          html.contains("Download retained output") &&
          html.contains("Command exited")
        },
      )
      .wait()
      .cast()
    assert_eq(value, "ACTUAL_FORT_CLAW_UI_PASSED")
    println(value)
  })
}
