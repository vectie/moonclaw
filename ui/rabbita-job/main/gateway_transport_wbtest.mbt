///|
#cfg(target="js")
extern "js" fn test_gateway_transport(
  install : (String) -> Unit,
) -> @js.Promise =
  #| async (install) => {
  #|   await new Promise(resolve => setTimeout(resolve, 0));
  #|   const originalFetch = globalThis.fetch, originalDocument = globalThis.document;
  #|   const create = URL.createObjectURL, revoke = URL.revokeObjectURL, timer = globalThis.setTimeout;
  #|   const check = (ok, message) => { if (!ok) throw new Error(message); };
  #|   const calls = [], blobs = [], clicks = [], revoked = [];
  #|   const bytes = new Uint8Array([0, 255, 128, 192, 10]);
  #|   let mode = "ok", deferred, deferredBody;
  #|   const response = () => new Response(bytes, { headers: { "Content-Disposition": "attachment; filename*=UTF-8''%E6%8A%A5%E5%91%8A%F0%9F%93%84.pdf" } });
  #|   try {
  #|     delete globalThis.__moonclawTransport;
  #|     globalThis.fetch = async (input, options = {}) => {
  #|       calls.push({ url: String(typeof input === "object" && !(input instanceof URL) ? input.url : input), options });
  #|       if (mode === "pending") return await new Promise(resolve => { deferred = resolve; });
  #|       if (mode === "body") { const result = response(); result.blob = () => new Promise(resolve => { deferredBody = resolve; }); return result; }
  #|       if (mode === "missing") return new Response(JSON.stringify({ error: { message: "Restore retained file and retry" } }), { status: 410 });
  #|       if (mode === "unauthorized") return new Response("{}", { status: 401 });
  #|       return response();
  #|     };
  #|     globalThis.document = { body: { appendChild() {} }, createElement() { return { click() { clicks.push({ name: this.download, href: this.href }); }, remove() {} }; } };
  #|     URL.createObjectURL = blob => { blobs.push(blob); return "blob:fixture-" + blobs.length; };
  #|     URL.revokeObjectURL = url => revoked.push(url);
  #|     globalThis.setTimeout = (fn, ms) => ms === 30000 ? timer(fn, 0) : timer(fn, ms);
  #|     const base = "http://127.0.0.1:18123/base";
  #|     install(base); const transport = globalThis.__moonclawTransport;
  #|     check(transport.setToken(base, "fixture-session-secret"), "token accepted");
  #|     await fetch(new URL(base + "/v1/jobs/runs"));
  #|     check(calls.at(-1).options.headers.get("Authorization") === "Bearer fixture-session-secret", "read bearer header");
  #|     check(calls.at(-1).options.redirect === "error", "redirect refused");
  #|     for (const url of ["http://127.0.0.1:18124/base/v1/jobs", "http://127.0.0.1:18123/baseevil/v1/jobs", base + "/v11/jobs", base + "/ui"]) {
  #|       await fetch(url); check(!calls.at(-1).options.headers?.get("Authorization"), "token scoped to exact gateway and API path");
  #|     }
  #|     let result = JSON.parse(await transport.download(base, "run-owned", "artifact-exact"));
  #|     check(result.ok && clicks.length === 1 && clicks[0].name === "报告📄.pdf", "Unicode download filename");
  #|     check(String(new Uint8Array(await blobs[0].arrayBuffer())) === String(bytes), "binary blob preserved");
  #|     check(calls.at(-1).url === base + "/v1/jobs/runs/run-owned/artifacts/artifact-exact/download", "exact identifiers");
  #|     check(!calls.some(call => call.url.includes("fixture-session-secret")), "no token in URL");
  #|     await transport.download(base, "run-owned", "artifact-exact"); check(clicks.length === 2, "repeat download");
  #|     mode = "missing"; result = JSON.parse(await transport.download(base, "run-owned", "artifact-exact"));
  #|     check(!result.ok && result.error.includes("Restore") && clicks.length === 2, "missing file visible without download");
  #|     mode = "unauthorized"; result = JSON.parse(await transport.download(base, "run-owned", "artifact-exact"));
  #|     check(!result.ok && result.error.includes("Gateway token"), "auth failure recovery");
  #|     mode = "pending"; const pending = transport.download(base, "run-owned", "artifact-exact");
  #|     await Promise.resolve(); transport.cancel(); deferred(response()); result = JSON.parse(await pending);
  #|     check(!result.ok && clicks.length === 2, "cancel rejects late download");
  #|     const queuedTicket = transport.downloadEpoch(); transport.cancel(); const beforeQueued = calls.length;
  #|     result = JSON.parse(await transport.download(base, "run-owned", "artifact-exact", queuedTicket));
  #|     check(!result.ok && calls.length === beforeQueued, "cancel rejects effect queued before navigation without a request");
  #|     mode = "body"; const stale = fetch(base + "/v1/jobs").then(r => r.blob());
  #|     await new Promise(resolve => timer(resolve, 0));
  #|     transport.setToken(base, "replacement-fixture"); deferredBody(new Blob([bytes]));
  #|     check(await stale.then(() => false, () => true), "token change rejects stale body");
  #|     mode = "pending"; const old = transport.download(base, "run-owned", "artifact-exact");
  #|     await Promise.resolve(); transport.configure("http://127.0.0.1:18124"); deferred(response());
  #|     check(!JSON.parse(await old).ok && clicks.length === 2, "gateway change rejects stale download");
  #|     mode = "ok"; await fetch("http://127.0.0.1:18124/v1/jobs");
  #|     check(!calls.at(-1).options.headers.has("Authorization"), "gateway change clears token");
  #|     transport.setToken("http://127.0.0.1:18124", "fixture"); transport.clear(); await fetch("http://127.0.0.1:18124/v1/jobs");
  #|     check(!calls.at(-1).options.headers.has("Authorization"), "clear token");
  #|     for (const malformed of ["CANARY-CRLF\r\ninjected", "CANARY-NUL\x00suffix", "CANARY-UNICODE☃", "CANARY-CONTROL\x7f"]) {
  #|       check(!transport.setToken("http://127.0.0.1:18124", malformed), "malformed token rejected generically");
  #|       await fetch("http://127.0.0.1:18124/v1/jobs");
  #|       check(!calls.at(-1).options.headers.has("Authorization"), "malformed token never transmitted");
  #|     }
  #|     let headerError = "";
  #|     await fetch("http://127.0.0.1:18124/v1/jobs", { headers: { "Authorization": "CANARY-HEADER\x00" } }).catch(error => { headerError = error.message; });
  #|     check(headerError.includes("could not be prepared") && !headerError.includes("CANARY"), "header errors never echo credentials");
  #|     await new Promise(resolve => timer(resolve, 10)); check(revoked.length === blobs.length, "object URLs released");
  #|     return "passed";
  #|   } finally {
  #|     globalThis.__moonclawTransport?.clear(); delete globalThis.__moonclawTransport;
  #|     globalThis.fetch = originalFetch; globalThis.document = originalDocument;
  #|     URL.createObjectURL = create; URL.revokeObjectURL = revoke; globalThis.setTimeout = timer;
  #|   }
  #| }

///|
test "gateway transport scopes token and preserves cancellable binary downloads" {
  @js.async_test(() => {
    let result : String = test_gateway_transport(configure_gateway_transport)
      .wait()
      .cast()
    assert_eq(result, "passed")
  })
}
