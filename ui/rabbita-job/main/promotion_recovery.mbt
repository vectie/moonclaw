///|
struct RecoveryProjection {
  protocol_version : Int
  instance_id : String
  workspace_id : String
  retention_id : String
  pending_attempt_id : String
  request_id : String
  destination_relative : String
  approval_digest : String
  command_digest : String
  outcome : String
  observed_at_ms : Int64
  pending_attempt : Bool
  retry_allowed : Bool
  historical_success_confirmed : Bool
} derive(FromJson, ToJson)

///|
struct RecoveryUiState {
  instance_id : String
  workspace_id : String
  retention_id : String
  pending_attempt_id : String
  token : String
  generation : Int
  pending : Bool
  projection : RecoveryProjection?
  notice : String
}

///|
fn recovery_initial() -> RecoveryUiState {
  {
    instance_id: "",
    workspace_id: "",
    retention_id: "",
    pending_attempt_id: "",
    token: "",
    generation: 0,
    pending: false,
    projection: None,
    notice: "Enter the original pending return identifiers. Inspection reads only; the attempt stays unresolved.",
  }
}

///|
fn recovery_invalidate(model : Model) -> Model {
  {
    ..model,
    recovery: {
      ..model.recovery,
      generation: model.recovery.generation + 1,
      token: "",
      pending: false,
      projection: None,
      notice: "Context changed. Refresh the exact pending return before using its observation.",
    },
  }
}

///|
fn recovery_set_field(model : Model, field : String, value : String) -> Model {
  let state = model.recovery
  if value.length() > 128 {
    return model
  }
  let state = match field {
    "instance" => { ..state, instance_id: value, }
    "workspace" => { ..state, workspace_id: value, }
    "retention" => { ..state, retention_id: value, }
    "attempt" => { ..state, pending_attempt_id: value, }
    "token" => { ..state, token: value, }
    _ => state
  }
  {
    ..model,
    recovery: {
      ..state,
      generation: state.generation + 1,
      pending: false,
      projection: None,
      notice: "Selection changed. Inspect this exact attempt to read its current destination state.",
    },
  }
}

///|
#cfg(target="js")
extern "js" fn browser_inspect_recovery(
  base : String,
  token : String,
  body : String,
) -> @js.Promise =
  #| async (base, token, body) => {
  #|   const abort = new AbortController(), timer = setTimeout(() => abort.abort(), 15000);
  #|   try {
  #|     const response = await fetch(base.replace(/\/$/, "") + "/v1/execution-sandbox/promotion-recovery", {method:"POST", headers:{"Content-Type":"application/json", "x-moonclaw-execution-token":token}, body, cache:"no-store", redirect:"error", signal:abort.signal});
  #|     const reader = response.body.getReader(), pieces = []; let size = 0;
  #|     try { for (;;) { const part = await reader.read(); if (part.done) break; size += part.value.length; if (size > 16384) throw new Error("bound"); pieces.push(part.value); } } finally { await reader.cancel(); }
  #|     if (!response.ok) return JSON.stringify({error:"Inspection could not be verified. Check access and the exact pending attempt; it remains unresolved."});
  #|     const bytes = new Uint8Array(size); let at = 0; for (const part of pieces) { bytes.set(part, at); at += part.length; }
  #|     return new TextDecoder("utf-8", {fatal:true}).decode(bytes);
  #|   } catch (_) { return JSON.stringify({error:"Inspection refresh failed. No current observation is available; the return stays unresolved."}); }
  #|   finally { clearTimeout(timer); }
  #| }

///|
fn recovery_request_json(state : RecoveryUiState, generation : Int) -> Json {
  {
    "protocol_version": 1,
    "instance_id": state.instance_id,
    "workspace_id": state.workspace_id,
    "retention_id": state.retention_id,
    "pending_attempt_id": state.pending_attempt_id,
    "request_id": "inspection-" + generation.to_string(),
  }
}

///|
fn recovery_start(dispatch : Dispatch[Msg], model : Model) -> (Cmd, Model) {
  let state = model.recovery
  let safe = fn(id : String) {
    id.length() >= 1 &&
    id.length() <= 128 &&
    id.all(c => {
      c.is_ascii_alphabetic() || c.is_ascii_digit() || c == '-' || c == '_'
    })
  }
  guard !state.pending &&
    [
      state.instance_id,
      state.workspace_id,
      state.retention_id,
      state.pending_attempt_id,
    ].all(safe) &&
    state.token.length() == 64 else {
    return (
      @rabbita.none,
      {
        ..model,
        recovery: {
          ..state,
          projection: None,
          notice: "Provide the four opaque identifiers and the execution route token. No trusted paths are accepted.",
        },
      },
    )
  }
  let generation = state.generation + 1
  let body = recovery_request_json(state, generation).stringify()
  let cmd = @rabbita.perform(raw => dispatch(RecoveryRead(generation, raw)), async fn() noraise {
    wait_browser_value_json(
      browser_inspect_recovery(model.gateway_base, state.token, body),
    )
  })
  (
    cmd,
    {
      ..model,
      recovery: {
        ..state,
        generation,
        pending: true,
        projection: None,
        notice: "Reading the exact pending return destination…",
      },
    },
  )
}

///|
fn recovery_accept(model : Model, generation : Int, raw : String) -> Model {
  let state = model.recovery
  if generation != state.generation || !state.pending || model.route != Overview {
    return model
  }
  let projection : RecoveryProjection? = try {
    let value : RecoveryProjection = @json.from_json(@json.parse(raw))
    let relative = value.destination_relative
    guard value.protocol_version == 1 &&
      value.instance_id == state.instance_id &&
      value.workspace_id == state.workspace_id &&
      value.retention_id == state.retention_id &&
      value.pending_attempt_id == state.pending_attempt_id &&
      value.request_id == "inspection-" + generation.to_string() &&
      value.pending_attempt &&
      !value.retry_allowed &&
      !value.historical_success_confirmed &&
      value.observed_at_ms > 0L &&
      relative.length() > 0 &&
      relative.length() <= 4096 &&
      !relative.has_prefix("/") &&
      !relative.contains("\u{0}") &&
      !relative
      .split("/")
      .any(part => part == ".." || part == "." || part == "") &&
      [
        "desired-applied", "reviewed-prestate", "diverged", "unavailable", "manual-recovery",
      ].contains(value.outcome) else {
      fail("binding")
    }
    Some(value)
  } catch {
    _ => None
  }
  {
    ..model,
    recovery: {
      ..state,
      pending: false,
      projection,
      notice: if projection is Some(_) {
        "Read-only observation. Preserve the pending return and ask the responsible operator to review recovery."
      } else {
        "Inspection refresh failed or the pending attempt changed. No current observation is available; retrying the return remains disabled."
      },
    },
  }
}

///|
fn recovery_outcome_label(outcome : String) -> String {
  match outcome {
    "desired-applied" =>
      "Observed bytes match the reviewed output. This does not prove the earlier return succeeded."
    "reviewed-prestate" =>
      "Observed destination matches its reviewed pre-return state. The locked attempt still needs review."
    "diverged" =>
      "Observed destination differs from both reviewed states. Preserve it for operator review."
    "manual-recovery" =>
      "The historical workspace root cannot be proven. Manual recovery review is required."
    _ =>
      "The destination could not be safely observed. Keep the return unresolved."
  }
}

///|
fn render_recovery_panel(dispatch : Dispatch[Msg], model : Model) -> Html {
  let state = model.recovery
  let field = fn(label : String, key : String, value : String) {
    @html.label([
      span(label),
      input(value~, input_type=@html.Text, on_input=value => {
        dispatch(SetRecoveryField(key, value))
      }),
    ])
  }
  @html.details(id="promotion-recovery", [
    @html.summary("Inspect an interrupted artifact return"),
    p(
      "Use the original pending attempt from the host’s return request. Inspection never retries, unlocks, rolls back or promotes anything.",
    ),
    field("Instance ID", "instance", state.instance_id),
    field("Workspace ID", "workspace", state.workspace_id),
    field("Retention ID", "retention", state.retention_id),
    field("Original pending attempt ID", "attempt", state.pending_attempt_id),
    @html.label([
      span("Execution route token (kept in this view only)"),
      input(input_type=@html.Password, value=state.token, on_input=value => {
        dispatch(SetRecoveryField("token", value))
      }),
    ]),
    button(
      type_="button",
      attrs=@html.Attrs::build().disabled(state.pending),
      on_click=dispatch(InspectRecovery),
      "Inspect destination read-only",
    ),
    button(
      type_="button",
      on_click=dispatch(ClearRecovery),
      "Clear observation and token",
    ),
    p(
      attrs=@html.Attrs::build().role("status").aria_live("polite"),
      state.notice,
    ),
    match state.projection {
      Some(value) =>
        div([
          h3(recovery_outcome_label(value.outcome)),
          p("Exact pending attempt: " + value.pending_attempt_id),
          p("Reviewed destination: " + value.destination_relative),
          p(
            "Observed at Unix milliseconds " +
            value.observed_at_ms.to_string() +
            ". This is a point-in-time observation; refresh before operator review.",
          ),
          p(
            "Return remains unresolved. Historical success is unconfirmed. No mutation control is available here.",
          ),
        ])
      None => nothing
    },
  ])
}
