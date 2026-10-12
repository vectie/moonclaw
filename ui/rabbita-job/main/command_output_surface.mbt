///|
struct UiCommandOutput {
  output_id : String
  run_id : String
  step_id : String
  status : String
  size_bytes : Int64
  sha256 : String
  expires_at_ms : Int64
  message : String
  receipt_status : String
  exit_code : Int?
  output_truncated : Bool
  limit_reason : String?
} derive(FromJson, ToJson, Debug)

///|
fn selected_command_output(
  snapshot : UiSnapshot,
  id : String,
) -> UiCommandOutput? {
  for remote in snapshot.linked_remote {
    if remote.kind != "fort-command-output" || remote.id != id {
      continue
    }
    let output : UiCommandOutput = @json.from_json(remote.metadata) catch {
      _ => continue
    }
    if output.run_id == snapshot.run.id && output.output_id == id {
      return Some(output)
    }
  }
  None
}

///|
fn render_command_outputs(
  dispatch : Dispatch[Msg],
  snapshot : UiSnapshot,
) -> Html {
  let outputs = snapshot.linked_remote.filter(item => {
    item.kind == "fort-command-output"
  })
  div(class="focus-block command-output-block", [
    p(class="kv-label", "Command output"),
    div(
      snapshot.linked_remote
      .filter(item => item.kind == "fort-command-live-output")
      .map(item => {
        match selected_command_live_output(snapshot, item.id) {
          Some(owner) =>
            article(class="artifact-card", [
              p(class="node-title", "Command · " + owner.step_id),
              button(
                class="tree-control-button",
                on_click=dispatch(TailCommandOutput(owner.output_id)),
                "Tail live output",
              ),
              p(
                class="muted",
                "Pause, resume or reload the saved cursor. Stream end never means job success.",
              ),
            ])
          None =>
            p(
              class="warning",
              item.summary.unwrap_or(
                "Live run bindings are unavailable. Restore trusted records and retry.",
              ),
            )
        }
      }),
    ),
    p(
      class="muted",
      "Download the complete output retained for an original command. This never reruns work.",
    ),
    if outputs.is_empty() {
      p(
        class="empty",
        "No run-bound command output was retained. Older runs cannot be reconstructed here.",
      )
    } else {
      div(
        class="artifact-list",
        outputs.map(remote => {
          let output = selected_command_output(snapshot, remote.id)
          article(class="artifact-card", [
            p(class="node-title", remote.title),
            p(
              class="muted",
              remote.summary.unwrap_or("Retained output unavailable"),
            ),
            match output {
              Some(value) =>
                div([
                  p(
                    class="muted",
                    "\{value.size_bytes} retained bytes · \{value.status}",
                  ),
                  p(
                    class="muted",
                    "Command " +
                    value.receipt_status +
                    value.exit_code
                    .map(code => " · exit " + code.to_string())
                    .unwrap_or(""),
                  ),
                  if value.limit_reason == Some("output-limit") {
                    p(
                      class="warning",
                      "Command reached its approved output ceiling. The download contains all retained bytes up to that ceiling; later output was not captured.",
                    )
                  } else if value.output_truncated {
                    p(
                      class="muted",
                      "The run preview is abbreviated or decoded for display. The download preserves the exact retained bytes.",
                    )
                  } else {
                    nothing
                  },
                  match value.limit_reason {
                    Some(reason) if reason != "output-limit" =>
                      p(class="muted", "Execution stopped: " + reason)
                    _ => nothing
                  },
                  if value.status == "available" {
                    button(
                      class="tree-control-button",
                      on_click=dispatch(DownloadCommandOutput(value.output_id)),
                      "Download retained output",
                    )
                  } else {
                    nothing
                  },
                  @html.details([
                    @html.summary("Output details"),
                    p(class="mono", "Run: " + value.run_id),
                    p(class="mono", "Output: " + value.output_id),
                    p(class="mono", "SHA-256: " + value.sha256),
                  ]),
                ])
              None => nothing
            },
          ])
        }),
      )
    },
  ])
}

///|
#cfg(target="js")
extern "js" fn browser_download_command_output(
  base : String,
  run : String,
  id : String,
  ticket : Int,
) -> @js.Promise =
  #| (base, run, id, ticket) => globalThis.__moonclawTransport.download(base, run, id, ticket, "command-outputs")

///|
fn download_command_output(
  dispatch : Dispatch[Msg],
  model : Model,
  id : String,
) -> (Cmd, Model) {
  if model.artifact_download_pending is Some(_) {
    return (@rabbita.none, model)
  }
  let snapshot = if model.route is Cowork {
    model.cowork_linked_snapshot
  } else {
    model.snapshot
  }
  guard snapshot is Some(snapshot) &&
    selected_command_output(snapshot, id) is Some(output) &&
    output.status == "available" else {
    return (
      @rabbita.none,
      {
        ..model,
        artifact_download_notice: Some(
          "Refresh this run and choose an available original command output.",
        ),
      },
    )
  }
  let owns = match model.route {
    Run(run) | RunCanvas(run) =>
      run == snapshot.run.id && model.selected_run_id == Some(run)
    Cowork =>
      model.cowork_detail is Some(detail) &&
      model.selected_cowork_session_key == Some(detail.session.session_key) &&
      detail.linked_run is Some(run) &&
      run.id == snapshot.run.id
    _ => false
  }
  guard owns else {
    return (
      @rabbita.none,
      {
        ..model,
        artifact_download_notice: Some(
          "Wait for the selected run to load before downloading its output.",
        ),
      },
    )
  }
  let generation = model.artifact_download_generation + 1
  let ticket = artifact_download_ticket()
  let command = @rabbita.perform(
    result => dispatch(ArtifactDownloadFinished(generation, result)),
    fn() noraise {
      parse_browser_copy_result(
        wait_browser_value_json(
          browser_download_command_output(
            model.gateway_base,
            snapshot.run.id,
            id,
            ticket,
          ),
        ),
      )
    },
  )
  (
    command,
    {
      ..model,
      artifact_download_generation: generation,
      artifact_download_pending: Some("command-output:" + id),
      artifact_download_notice: Some(
        "Downloading exact retained command output…",
      ),
    },
  )
}
