///|
fn recovery_ui_fixture() -> Model {
  {
    ..init_model(),
    route: Overview,
    recovery: {
      ..recovery_initial(),
      instance_id: "a".repeat(32),
      workspace_id: "book",
      retention_id: "return55-desired-applied",
      pending_attempt_id: "attempt55-desired-applied",
      token: "b".repeat(64),
      generation: 7,
      pending: true,
    },
  }
}

///|
fn recovery_projection_fixture() -> RecoveryProjection {
  {
    protocol_version: 1,
    instance_id: "a".repeat(32),
    workspace_id: "book",
    retention_id: "return55-desired-applied",
    pending_attempt_id: "attempt55-desired-applied",
    request_id: "inspection-7",
    destination_relative: "reviewed/desired-applied",
    approval_digest: "b".repeat(64),
    command_digest: "c".repeat(64),
    outcome: "desired-applied",
    observed_at_ms: 1000L,
    pending_attempt: true,
    retry_allowed: false,
    historical_success_confirmed: false,
  }
}

///|
test "owner recovery rejects stale and mismatched observations and renders no mutation controls" {
  let model = recovery_ui_fixture()
  let value = recovery_projection_fixture()
  let raw = value.to_json().stringify()
  assert_true(recovery_accept(model, 6, raw).recovery.projection is None)
  for
    wrong in [
      { ..value, pending_attempt_id: "other-attempt", },
      { ..value, request_id: "inspection-old", },
      { ..value, retention_id: "other-retention", },
      { ..value, workspace_id: "other", },
      { ..value, instance_id: "other", },
      { ..value, retry_allowed: true, },
      { ..value, historical_success_confirmed: true, },
      { ..value, destination_relative: "/private/CANARY", },
    ] {
    assert_true(
      recovery_accept(model, 7, wrong.to_json().stringify()).recovery.projection
      is None,
    )
  }
  let accepted = recovery_accept(model, 7, raw)
  assert_true(accepted.recovery.projection is Some(_))
  let html = @rabbita.render_to_string(
    @rabbita.static_cell(
      render_recovery_panel(@cmd.Emit(_ => @rabbita.none), accepted),
    ),
  )
  assert_true(html.contains("Observed bytes match"))
  assert_true(html.contains("does not prove the earlier return succeeded"))
  assert_true(html.contains("Unix milliseconds 1000"))
  assert_true(html.contains("Inspect destination read-only"))
  assert_false(html.contains(">Retry return<"))
  assert_false(html.contains(">Unlock<"))
  assert_true(
    recovery_set_field(accepted, "attempt", "another").recovery.projection
    is None,
  )
  let invalidated = recovery_invalidate(accepted)
  assert_true(invalidated.recovery.projection is None)
  assert_eq(invalidated.recovery.token, "")
  assert_true(recovery_accept(invalidated, 7, raw).recovery.projection is None)
  let failed = recovery_accept(
    model, 7, "{\"error\":\"CANARY-private-diagnostic\"}",
  )
  assert_true(failed.recovery.projection is None)
  assert_false(failed.recovery.notice.contains("CANARY"))
}

///|
#cfg(target="js")
extern "js" fn real_recovery_ui_http(
  install : (String) -> Unit,
  inspect : (String, String, String) -> @js.Promise,
  render : (String) -> Bool,
) -> @js.Promise =
  #| async (install, inspect, render) => {
  #|   const fs = await import("node:fs/promises"), base = process.env.MOONCLAW_HTTP_FIXTURE_URL;
  #|   if (!/^http:\/\/127\.0\.0\.1:\d+$/.test(base || "")) throw new Error("private real gateway required");
  #|   const cases = JSON.parse(await fs.readFile(process.env.ROUND55_FIXTURE_ROOT + "/cases.json", "utf8"));
  #|   const check = (ok, why) => { if (!ok) throw new Error(why); };
  #|   const oldFetch = globalThis.fetch;
  #|   try {
  #|     delete globalThis.__moonclawTransport; install(base); globalThis.__moonclawTransport.setToken(base, "fixture-only-token");
  #|     const transportFetch = globalThis.fetch, reads = []; globalThis.fetch = async (...args) => { const response = await transportFetch(...args); reads.push({status:response.status, body:await response.clone().text()}); return response; };
  #|     for (const item of cases) {
  #|       const request = {protocol_version:1, instance_id:"a".repeat(32), workspace_id:"book", retention_id:item.retention_id, pending_attempt_id:item.pending_attempt_id, request_id:"inspection-7"};
  #|       const raw = await inspect(base, "b".repeat(64), JSON.stringify(request)), value = JSON.parse(raw);
  #|       check(value.outcome === item.outcome && value.pending_attempt_id === request.pending_attempt_id, "actual Fort observation bound to original attempt: " + item.outcome + " / " + JSON.stringify(reads.at(-1)));
  #|       check(value.pending_attempt === true && value.retry_allowed === false && value.historical_success_confirmed === false, "read-only unresolved semantics");
  #|       check(!raw.includes("CANARY") && !raw.includes(process.env.ROUND55_FIXTURE_ROOT), "no private paths or secrets");
  #|       check(render(raw), "actual HTTP observation passes compiled UI binding and owner DOM rendering");
  #|       const wrong = JSON.parse(await inspect(base, "b".repeat(64), JSON.stringify({...request, pending_attempt_id:"wrong-attempt"})));
  #|       check(typeof wrong.error === "string", "stale attempt refused");
  #|       const denied = JSON.parse(await inspect(base, "c".repeat(64), JSON.stringify(request)));
  #|       check(typeof denied.error === "string", "wrong execution token refused");
  #|     }
  #|     globalThis.__moonclawTransport.clear();
  #|     const denied = JSON.parse(await inspect(base, "b".repeat(64), JSON.stringify({protocol_version:1, instance_id:"a".repeat(32), workspace_id:"book", retention_id:cases[0].retention_id, pending_attempt_id:cases[0].pending_attempt_id, request_id:"inspection-7"})));
  #|     check(typeof denied.error === "string", "gateway bearer token required independently");
  #|     return "ROUND55_ACTUAL_FORT_GATEWAY_COMPILED_UI_PASSED";
  #|   } finally { globalThis.__moonclawTransport?.clear(); delete globalThis.__moonclawTransport; globalThis.fetch = oldFetch; }
  #| }

///|
#skip("Requires the private real Fort inspector and authenticated Claw gateway fixture")
test "real Fort observation reaches normal gateway and compiled owner DOM" {
  @js.async_test(() => {
    // Initialize once before the fixture installs its authenticated gateway.
    // init_model intentionally reconfigures transport; doing it per outcome
    // would correctly clear the token as a gateway context change.
    let fixture_model = recovery_ui_fixture()
    let result : String = real_recovery_ui_http(
        configure_gateway_transport,
        browser_inspect_recovery,
        raw => {
          let value : RecoveryProjection = @json.from_json(@json.parse(raw)) catch {
            _ => return false
          }
          let model = {
            ..fixture_model,
            recovery: {
              ..fixture_model.recovery,
              retention_id: value.retention_id,
              pending_attempt_id: value.pending_attempt_id,
            },
          }
          let model = recovery_accept(model, 7, raw)
          guard model.recovery.projection is Some(projection) else {
            return false
          }
          let html = @rabbita.render_to_string(
            @rabbita.static_cell(
              render_recovery_panel(@cmd.Emit(_ => @rabbita.none), model),
            ),
          )
          projection.outcome == value.outcome &&
          html.contains("Return remains unresolved") &&
          html.contains(value.destination_relative) &&
          html.contains("Inspect destination read-only")
        },
      )
      .wait()
      .cast()
    assert_eq(result, "ROUND55_ACTUAL_FORT_GATEWAY_COMPILED_UI_PASSED")
    println(result)
  })
}
