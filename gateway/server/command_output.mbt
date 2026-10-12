///|
async fn Gateway::with_command_outputs(
  self : Gateway,
  snapshot : @job.JobUiSnapshot,
) -> @job.JobUiSnapshot {
  guard self.command_output_config is Some(config) else { return snapshot }
  let live : Array[@job.JobUiRemoteLink] = @execution_sandbox.list_bound_command_live_outputs(
    config,
    snapshot.run.id,
  ).map(output => {
    id: output.output_id,
    kind: "fort-command-live-output",
    title: "Live command output · " + output.step_id,
    status: "bound",
    summary: Some(
      "Read-only tail of the approved command. Stream state never determines job success.",
    ),
    detail: None,
    metadata: output.to_json(),
  }) catch {
    _ =>
      [
        {
          id: "fort-live-output-unavailable",
          kind: "fort-command-live-output",
          title: "Live command output unavailable",
          status: "unavailable",
          summary: Some(
            "Live run bindings failed verification. Restore trusted records and retry; work was not rerun.",
          ),
          detail: None,
          metadata: Json::null(),
        },
      ]
  }
  let outputs = @execution_sandbox.list_bound_command_outputs(
    config,
    snapshot.run.id,
    self.clock.now().ms(),
  ) catch {
    _ =>
      return {
        ..snapshot,
        linked_remote: snapshot.linked_remote +
        live +
        [
          {
            id: "fort-output-unavailable",
            kind: "fort-command-output",
            title: "Command output unavailable",
            status: "unavailable",
            summary: Some(
              "Retained run bindings could not be verified. Retry after restoring the trusted records; work is not rerun.",
            ),
            detail: None,
            metadata: Json::null(),
          },
        ],
      }
  }
  {
    ..snapshot,
    linked_remote: snapshot.linked_remote +
    outputs.map(output => {
      id: output.output_id,
      kind: "fort-command-output",
      title: "Command output · " + output.step_id,
      status: output.status,
      summary: Some(output.message),
      detail: None,
      metadata: output.to_json(),
    }) +
    live,
  }
}

///|
async fn Gateway::handle_read_command_live_output(
  self : Gateway,
  w : @httpx.ResponseWriter,
  raw_run : String,
  raw_output : String,
  raw_cursor : String,
) -> Unit {
  guard self.auth.token is Some(token) && !token.is_blank() else {
    raise json_error(401, "Unauthorized", {
      "error": {
        "code": "live_output_auth_required",
        "message": "Live command output requires a configured gateway bearer token.",
      },
    })
  }
  guard artifact_route_id(raw_run) is Some(run_id) &&
    artifact_route_id(raw_output) is Some(output_id) &&
    artifact_route_id(raw_cursor) is Some(cursor) &&
    cursor.length() <= 100 else {
    raise json_error(400, "BadRequest", {
      "error": {
        "code": "invalid_live_output_identity",
        "message": "Choose a command bound to this run and its saved cursor.",
      },
    })
  }
  guard self.job_runtime().store().get_run(run_id) is Some(_) else {
    raise json_error(404, "NotFound", {
      "error": {
        "code": "output_run_missing",
        "message": "The selected run is unavailable. Refresh the original run.",
      },
    })
  }
  guard self.command_output_config is Some(config) else {
    raise json_error(409, "Conflict", {
      "error": {
        "code": "live_output_reader_unconfigured",
        "message": "The trusted operator has not configured live command output retrieval.",
      },
    })
  }
  guard config.live_output_reader_path is Some(_) else {
    raise json_error(409, "Conflict", {
      "error": {
        "code": "live_output_reader_unconfigured",
        "message": "The trusted operator has not configured the Fort live-output reader.",
      },
    })
  }
  let chunk = @execution_sandbox.read_bound_command_live_output(
    config, run_id, output_id, cursor,
  ) catch {
    error =>
      raise json_error(409, "Conflict", {
        "error": {
          "code": "live_output_unavailable",
          "message": if error.to_string().contains("not configured") {
            "The trusted operator has not configured the Fort live-output reader."
          } else if error.to_string().contains("expired") {
            "Live output expired or failed verification. Refresh the run for its verified terminal output."
          } else {
            "Live output is unavailable or its cursor could not be verified. Retry from the saved cursor after restoring trusted records. Work was not rerun."
          },
        },
      })
  }
  w.header().set("Content-Type", "application/json")
  w.header().set("Cache-Control", "no-store")
  w.header().set("X-Content-Type-Options", "nosniff")
  w.write_header(200)
  w.write(chunk.to_json().stringify())
}

///|
async fn Gateway::handle_download_command_output(
  self : Gateway,
  w : @httpx.ResponseWriter,
  raw_run : String,
  raw_output : String,
) -> Unit {
  guard artifact_route_id(raw_run) is Some(run_id) &&
    artifact_route_id(raw_output) is Some(output_id) else {
    raise json_error(400, "BadRequest", {
      "error": {
        "code": "invalid_output_identity",
        "message": "Select a retained command output from this run.",
      },
    })
  }
  guard self.job_runtime().store().get_run(run_id) is Some(_) else {
    raise json_error(404, "NotFound", {
      "error": {
        "code": "output_run_missing",
        "message": "The selected run is unavailable. Refresh and choose the original run.",
      },
    })
  }
  guard self.command_output_config is Some(config) else {
    raise json_error(409, "Conflict", {
      "error": {
        "code": "output_reader_unconfigured",
        "message": "The trusted operator has not configured complete command output retrieval.",
      },
    })
  }
  let bytes = @execution_sandbox.download_bound_command_output(
    config,
    run_id,
    output_id,
    self.clock.now().ms(),
  ) catch {
    error =>
      raise json_error(409, "Conflict", {
        "error": {
          "code": "command_output_unavailable",
          "message": command_output_public_error(error.to_string()),
        },
      })
  }
  w.header().set("Content-Type", "application/octet-stream")
  w
  .header()
  .set(
    "Content-Disposition",
    artifact_download_disposition(output_id + "-complete-output.bin"),
  )
  w.header().set("Cache-Control", "no-store")
  w.header().set("X-Content-Type-Options", "nosniff")
  w.write_header(200)
  w.write(bytes)
}

///|
// Never reflect a filesystem, config, protocol body, credential or key in HTTP.
fn command_output_public_error(error : String) -> String {
  if error.contains("expired") {
    "The retained command output has expired. Work was not rerun."
  } else if error.contains("not configured") {
    "The trusted operator has not configured the Fort complete-output reader."
  } else if error.contains("verification") || error.contains("mismatch") {
    "The retained command output failed verification. No bytes were downloaded; work was not rerun."
  } else if error.contains("no retained signed") {
    "This execution has no original signed output reference. It cannot be reconstructed or downloaded."
  } else {
    "The original run output or its retained file is missing or unavailable. Refresh the run, or restore its trusted retained records, then retry. Work was not rerun."
  }
}
