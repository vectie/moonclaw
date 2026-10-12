///|
struct UiCommandLiveOwner {
  output_id : String
  run_id : String
  step_id : String
} derive(FromJson, ToJson, Debug)

///|
struct UiCommandLiveChunk {
  protocol_version : Int
  output_id : String
  run_id : String
  step_id : String
  stream_id : String
  offset : Int
  next_offset : Int
  available_bytes : Int
  content_base64 : String
  status : String
  terminal : Bool
  retry_after_ms : Int
  next_cursor : String
} derive(FromJson, ToJson, Debug)

///|
struct CommandLiveView {
  owner : UiCommandLiveOwner
  cursor : String
  carry : String
  text : String
  notice : String
  paused : Bool
  pending : Bool
  terminal : Bool
  binary : Bool
  truncated : Bool
} derive(Debug)

///|
struct LiveDisplayPart {
  text : String
  carry : String
  binary : Bool
  count : Int
} derive(FromJson, Debug)

///|
fn selected_command_live_output(
  snapshot : UiSnapshot,
  id : String,
) -> UiCommandLiveOwner? {
  for item in snapshot.linked_remote {
    if item.kind != "fort-command-live-output" || item.id != id {
      continue
    }
    let owner : UiCommandLiveOwner = @json.from_json(item.metadata) catch {
      _ => continue
    }
    if owner.run_id == snapshot.run.id && owner.output_id == id {
      return Some(owner)
    }
  }
  None
}

///|
fn command_live_snapshot(model : Model) -> UiSnapshot? {
  match model.route {
    Run(run) | RunCanvas(run) =>
      if model.selected_run_id == Some(run) &&
        model.snapshot is Some(snapshot) &&
        snapshot.run.id == run {
        Some(snapshot)
      } else {
        None
      }
    Cowork =>
      if model.cowork_detail is Some(detail) &&
        model.selected_cowork_session_key == Some(detail.session.session_key) &&
        detail.linked_run is Some(run) &&
        model.cowork_linked_snapshot is Some(snapshot) &&
        run.id == snapshot.run.id {
        Some(snapshot)
      } else {
        None
      }
    _ => None
  }
}

///|
#cfg(target="js")
extern "js" fn browser_read_command_live(
  base : String,
  run : String,
  output : String,
  cursor : String,
) -> @js.Promise =
  #| async (base, run, output, cursor) => {
  #|   const controller = new AbortController(), timeout = setTimeout(() => controller.abort(), 10000);
  #|   try {
  #|     const response = await fetch(base.replace(/\/$/, "") + "/v1/jobs/runs/" + encodeURIComponent(run) + "/command-outputs/" + encodeURIComponent(output) + "/live/" + encodeURIComponent(cursor), { signal: controller.signal, cache: "no-store", redirect: "error" });
  #|     const reader = response.body.getReader(), pieces = []; let size = 0;
  #|     try { for (;;) { const {done, value} = await reader.read(); if (done) break; size += value.length; if (size > 98304) throw new Error("Live response exceeds its bound"); pieces.push(value); } }
  #|     finally { await reader.cancel(); }
  #|     const bytes = new Uint8Array(size); let at = 0; for (const part of pieces) { bytes.set(part, at); at += part.length; }
  #|     const raw = new TextDecoder("utf-8", {fatal:true}).decode(bytes);
  #|     if (!response.ok) {
  #|       let code = ""; try { code = JSON.parse(raw).error?.code || ""; } catch (_) {}
  #|       const message = response.status === 401 ? "Gateway token required or rejected. Reconnect and resume this cursor." : code === "live_output_reader_unconfigured" ? "The trusted operator has not configured the Fort live-output reader." : "Live output is unavailable, expired, or failed verification. Resume after checking the retained stream; work was not rerun.";
  #|       return JSON.stringify({error: message});
  #|     }
  #|     return raw;
  #|   } catch (_) { return JSON.stringify({error: "Live output disconnected or timed out. Resume the saved cursor; this does not change job status."}); }
  #|   finally { clearTimeout(timeout); }
  #| }

///|
// Keep at most three trailing bytes across reads. Invalid UTF-8 is displayed with
// replacement characters; control bytes are printable escapes, never terminal commands.
#cfg(target="js")
extern "js" fn decode_live_display(
  content : String,
  carry : String,
  terminal : Bool,
) -> String =
  #| (content, carry, terminal) => {
  #|   try {
  #|   const raw = atob(content), prior = atob(carry);
  #|   if (raw.length > 65536 || prior.length > 3 || btoa(raw) !== content) throw new Error("Invalid live bytes");
  #|   const bytes = Uint8Array.from(prior + raw, c => c.charCodeAt(0)); let end = bytes.length;
  #|   if (!terminal) {
  #|     for (let i = Math.max(0, bytes.length - 3); i < bytes.length; i++) {
  #|       const b = bytes[i], need = b >= 0xc2 && b <= 0xdf ? 2 : b >= 0xe0 && b <= 0xef ? 3 : b >= 0xf0 && b <= 0xf4 ? 4 : 0;
  #|       if (need && bytes.length - i < need && bytes.slice(i + 1).every(x => x >= 0x80 && x <= 0xbf)) { end = i; break; }
  #|     }
  #|   }
  #|   let text = new TextDecoder("utf-8").decode(bytes.slice(0, end));
  #|   const binary = /[\u0000-\u0008\u000b-\u001f\u007f\ufffd]/.test(text);
  #|   text = text.replace(/[\u0000-\u0008\u000b-\u001f\u007f]/g, c => "[0x" + c.charCodeAt(0).toString(16).padStart(2,"0") + "]");
  #|   return JSON.stringify({text, carry:btoa(String.fromCharCode(...bytes.slice(end))), binary, count:raw.length});
  #|   } catch (_) { return JSON.stringify({error:"Invalid live bytes"}); }
  #| }

///|
#cfg(target="js")
extern "js" fn command_live_saved_cursor(
  base : String,
  run : String,
  output : String,
  value : String,
) -> String =
  #| (base, run, output, value) => {
  #|   const key = "moonclaw.live-cursor.v1:" + JSON.stringify([base, run, output]);
  #|   try {
  #|     if (value !== "") { sessionStorage.setItem(key, value); return value; }
  #|     return sessionStorage.getItem(key) || "";
  #|   } catch (_) { return ""; }
  #| }

///|
fn invalidate_command_live(model : Model) -> Model {
  {
    ..model,
    command_live_generation: model.command_live_generation + 1,
    command_live_view: None,
  }
}

///|
fn start_command_live(
  dispatch : Dispatch[Msg],
  model : Model,
  id : String,
) -> (Cmd, Model) {
  guard command_live_snapshot(model) is Some(snapshot) &&
    selected_command_live_output(snapshot, id) is Some(owner) else {
    return (@rabbita.none, model)
  }
  if model.command_live_view is Some(view) &&
    view.owner.run_id == owner.run_id &&
    view.owner.output_id == id &&
    !view.paused {
    return (@rabbita.none, model)
  }
  let saved = command_live_saved_cursor(
    model.gateway_base,
    owner.run_id,
    id,
    "",
  )
  let saved_json = @json.parse(saved) catch { _ => Json::null() }
  let (cursor, carry) = match saved_json {
    { "cursor": String(cursor), "carry": String(carry), .. } if cursor.length() <=
      100 &&
      carry.length() <= 4 => (cursor, carry)
    _ => ("start", "")
  }
  let view : CommandLiveView = {
    owner,
    cursor,
    carry,
    text: "",
    notice: "Reading the saved cursor. Earlier text is not copied on reload.",
    paused: false,
    pending: false,
    terminal: false,
    binary: false,
    truncated: cursor != "start",
  }
  poll_command_live(dispatch, {
    ..model,
    command_live_generation: model.command_live_generation + 1,
    command_live_view: Some(view),
  })
}

///|
fn poll_command_live(dispatch : Dispatch[Msg], model : Model) -> (Cmd, Model) {
  guard model.command_live_view is Some(view) &&
    !view.paused &&
    !view.pending &&
    !view.terminal &&
    command_live_snapshot(model) is Some(snapshot) &&
    snapshot.run.id == view.owner.run_id &&
    selected_command_live_output(snapshot, view.owner.output_id) is Some(_) else {
    return (@rabbita.none, model)
  }
  let generation = model.command_live_generation + 1
  let cmd = @rabbita.perform(
    raw => dispatch(CommandLiveRead(generation, view.cursor, raw)),
    async fn() noraise {
      wait_browser_value_json(
        browser_read_command_live(
          model.gateway_base,
          view.owner.run_id,
          view.owner.output_id,
          view.cursor,
        ),
      )
    },
  )
  (
    cmd,
    {
      ..model,
      command_live_generation: generation,
      command_live_view: Some({ ..view, pending: true, }),
    },
  )
}

///|
fn command_live_failure(
  model : Model,
  view : CommandLiveView,
  notice : String,
) -> (Cmd, Model) {
  (
    @rabbita.none,
    {
      ..model,
      command_live_generation: model.command_live_generation + 1,
      command_live_view: Some({ ..view, pending: false, paused: true, notice, }),
    },
  )
}

///|
fn accept_command_live(
  dispatch : Dispatch[Msg],
  model : Model,
  generation : Int,
  cursor : String,
  raw : String,
) -> (Cmd, Model) {
  guard generation == model.command_live_generation &&
    model.command_live_view is Some(view) &&
    view.pending &&
    !view.paused &&
    view.cursor == cursor &&
    command_live_snapshot(model) is Some(snapshot) &&
    snapshot.run.id == view.owner.run_id else {
    return (@rabbita.none, model)
  }
  let chunk : UiCommandLiveChunk = @json.from_json(@json.parse(raw)) catch {
    _ => {
      let error = @json.parse(raw) catch { _ => Json::null() }
      let notice = match error {
        { "error": String(message), .. } if message.length() <= 300 => message
        _ =>
          "Live output disconnected, expired or unavailable. Resume the saved cursor; job status is unchanged."
      }
      return command_live_failure(model, view, notice)
    }
  }
  let expected = if cursor == "start" {
    "start"
  } else {
    chunk.stream_id + ":" + chunk.offset.to_string()
  }
  guard chunk.protocol_version == 1 &&
    chunk.run_id == view.owner.run_id &&
    chunk.output_id == view.owner.output_id &&
    chunk.step_id == view.owner.step_id &&
    chunk.stream_id.length() == 64 &&
    chunk.stream_id.all(c => c.is_ascii_digit() || (c >= 'a' && c <= 'f')) &&
    cursor == expected &&
    (cursor != "start" || chunk.offset == 0) &&
    chunk.offset >= 0 &&
    chunk.next_offset >= chunk.offset &&
    chunk.next_offset <= chunk.available_bytes &&
    chunk.available_bytes <= 67108864 &&
    chunk.next_offset - chunk.offset <= 65536 &&
    chunk.next_cursor == chunk.stream_id + ":" + chunk.next_offset.to_string() &&
    ["running", "exited", "killed", "failed"].contains(chunk.status) &&
    chunk.terminal ==
    (chunk.status != "running" && chunk.next_offset == chunk.available_bytes) &&
    chunk.retry_after_ms >= 0 &&
    chunk.retry_after_ms <= 5000 else {
    return command_live_failure(
      model, view, "Live output identity or cursor failed verification. No bytes were appended.",
    )
  }
  let decoded : LiveDisplayPart = @json.from_json(
    @json.parse(
      decode_live_display(chunk.content_base64, view.carry, chunk.terminal),
    ),
  ) catch {
    _ =>
      return command_live_failure(
        model, view, "Live output bytes failed verification. No bytes were appended.",
      )
  }
  guard decoded.count == chunk.next_offset - chunk.offset &&
    decoded.carry.length() <= 4 else {
    return command_live_failure(
      model, view, "Live output byte length failed verification. No bytes were appended.",
    )
  }
  let combined = view.text + decoded.text
  let truncated = combined.length() > 65536 || view.truncated
  let text = if combined.length() > 65536 {
    combined[combined.length() - 65536:].to_owned()
  } else {
    combined
  }
  ignore(
    command_live_saved_cursor(
      model.gateway_base,
      view.owner.run_id,
      view.owner.output_id,
      ({ "cursor": chunk.next_cursor, "carry": decoded.carry } : Json).stringify(),
    ),
  )
  let next = {
    ..model,
    command_live_view: Some({
      ..view,
      cursor: chunk.next_cursor,
      carry: decoded.carry,
      text,
      truncated,
      binary: view.binary || decoded.binary,
      terminal: chunk.terminal,
      pending: false,
      paused: chunk.terminal,
      notice: if chunk.terminal {
        "Output stream ended. This is not job success. Refresh the run for its verified receipt and complete-output download."
      } else if decoded.count == 0 {
        "Waiting for appended output. An empty read does not complete the job."
      } else {
        "Tailing approved command output. Job status comes from the run, not this stream."
      },
    }),
  }
  let cmd = if chunk.terminal {
    if model.route is Cowork {
      fetch_cowork_linked_snapshot(
        dispatch,
        model.gateway_base,
        view.owner.run_id,
      )
    } else {
      fetch_snapshot(dispatch, model.gateway_base, view.owner.run_id)
    }
  } else {
    @rabbita.delay(
      dispatch(PollCommandLive(generation)),
      chunk.retry_after_ms.max(250),
    )
  }
  (cmd, next)
}

///|
fn render_command_live_view(dispatch : Dispatch[Msg], model : Model) -> Html {
  guard model.command_live_view is Some(view) else { return nothing }
  let terminal_output = match command_live_snapshot(model) {
    Some(snapshot) => selected_command_output(snapshot, view.owner.output_id)
    None => None
  }
  section(class="panel command-live-view", [
    h2(class="panel-title", "Live command output · " + view.owner.step_id),
    p(attrs=@html.Attrs::build().role("status"), view.notice),
    p(
      class="muted",
      "Read-only display · maximum 65,536 characters · cursor " + view.cursor,
    ),
    div(class="toolbar", [
      if !view.paused {
        button(on_click=dispatch(PauseCommandLive), "Pause tail")
      } else if !view.terminal {
        button(on_click=dispatch(ResumeCommandLive), "Resume tail")
      } else {
        nothing
      },
      button(on_click=dispatch(ReloadCommandLive), "Reload from cursor"),
      button(on_click=dispatch(CloseCommandLive), "Close live output"),
      if terminal_output is Some(output) && output.status == "available" {
        button(
          on_click=dispatch(DownloadCommandOutput(output.output_id)),
          "Download retained output",
        )
      } else {
        nothing
      },
    ]),
    if view.binary {
      p(
        class="warning",
        "Binary/control bytes are escaped; invalid UTF-8 is replaced. Use the verified terminal download for exact bytes.",
      )
    } else {
      nothing
    },
    if view.carry != "" {
      p(class="muted", "Waiting for the rest of a split UTF-8 character.")
    } else {
      nothing
    },
    if view.truncated {
      p(
        class="warning",
        "Earlier display text was omitted or capped. The cursor continues without copying the full spool.",
      )
    } else {
      nothing
    },
    @html.pre(class="command-live-text", [@html.text(view.text)]),
  ])
}
