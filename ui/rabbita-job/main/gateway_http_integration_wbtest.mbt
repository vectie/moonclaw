///|
#cfg(target="js")
extern "js" fn test_actual_gateway(
  install : (String) -> Unit,
  verify_text : (String) -> Bool,
) -> @js.Promise =
  #| async (install, verifyText) => {
  #|   const base = process.env.MOONCLAW_HTTP_FIXTURE_URL;
  #|   if (!base || !/^http:\/\/127\.0\.0\.1:\d+$/.test(base)) throw new Error("Native gateway fixture URL required");
  #|   const check = (ok, message) => { if (!ok) throw new Error(message); };
  #|   const originalFetch = globalThis.fetch, originalDocument = globalThis.document;
  #|   const create = URL.createObjectURL, revoke = URL.revokeObjectURL, timer = globalThis.setTimeout;
  #|   const blobs = [], clicks = [];
  #|   try {
  #|     delete globalThis.__moonclawTransport; install(base);
  #|     const transport = globalThis.__moonclawTransport;
  #|     const denied = await fetch(base + "/v1/artifacts"); check(denied.status === 401, "native read requires auth"); await denied.text();
  #|     transport.setToken(base, "fixture-only-token");
  #|     const read = await fetch(base + "/v1/artifacts"); check(read.status === 200, "native authenticated read");
  #|     check((await read.json()).artifacts.some(a => a.id === "artifact-exact" && a.run_id === "run-owned"), "native artifact identity");
  #|     const text = await fetch(base + "/v1/artifacts/text-exact"); check(text.status === 200, "native text GET");
  #|     check(verifyText(await text.text()), "native text response reaches shipped decoder and editor unchanged");
  #|     globalThis.document = { body: { appendChild() {} }, createElement() { return { click() { clicks.push(this.download); }, remove() {} }; } };
  #|     URL.createObjectURL = blob => { blobs.push(blob); return "blob:actual-gateway-fixture"; };
  #|     URL.revokeObjectURL = () => {};
  #|     globalThis.setTimeout = (fn, ms) => ms === 30000 ? timer(fn, 0) : timer(fn, ms);
  #|     const result = JSON.parse(await transport.download(base, "run-owned", "artifact-exact"));
  #|     check(result.ok && clicks[0] === "报告📄.pdf", "native download accepted by browser boundary");
  #|     const binary = new Uint8Array(await blobs[0].arrayBuffer());
  #|     check(String(binary) === String(new Uint8Array([37,80,68,70,45,49,46,55,0,255,128,192,254,10,69,79,70])), "native raw HTTP bytes preserved end to end");
  #|     const wrong = JSON.parse(await transport.download(base, "other-run", "artifact-exact")); check(!wrong.ok && clicks.length === 1, "native wrong run refused");
  #|     transport.clear(); const unauth = JSON.parse(await transport.download(base, "run-owned", "artifact-exact")); check(!unauth.ok && unauth.error.includes("token"), "native cleared token refused");
  #|     return "ACTUAL_GATEWAY_UI_PASSED";
  #|   } finally {
  #|     globalThis.__moonclawTransport?.clear(); delete globalThis.__moonclawTransport;
  #|     globalThis.fetch = originalFetch; globalThis.document = originalDocument;
  #|     URL.createObjectURL = create; URL.revokeObjectURL = revoke; globalThis.setTimeout = timer;
  #|   }
  #| }

///|
#skip("Run through the native artifact HTTP fixture, which supplies an isolated authenticated gateway")
test "UI fetch and binary download integrate with actual authenticated gateway" {
  let initial = init_model()
  @js.async_test(() => {
    let result : String = test_actual_gateway(configure_gateway_transport, raw => {
        let json = @json.parse(raw) catch { _ => return false }
        let loaded = match parse_loaded_artifact_payload(json) {
          Ok(loaded) => loaded
          Err(_) => return false
        }
        let pending = artifact_test_update(initial, OpenArtifact("text-exact"))
        let displayed = artifact_test_update(
          pending,
          ArtifactLoaded(
            "text-exact",
            pending.artifact_request_generation,
            Ok(loaded),
          ),
        )
        displayed.artifact_editor_draft == "retained text 世界" &&
        displayed.artifact_modal is Some(result) &&
        result.artifact.id == "text-exact"
      })
      .wait()
      .cast()
    assert_eq(result, "ACTUAL_GATEWAY_UI_PASSED")
    println(result)
  })
}
