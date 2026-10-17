///|
// A checkpoint is a precondition, never a permission or an execution receipt.
fn cowork_recovery_projection(
  session_key : String,
  cwd : String,
  message_count : Int32,
  resume_receipt : Json,
  launch_pending : Bool,
  run : @job.JobRun,
  steps : Array[@job.JobStepRun],
  artifacts : Array[@job.ArtifactRecord],
  event_count : Int32,
  observed_at : Int32,
) -> Json {
  let waiting = steps.filter(step => step.status is WaitingForInput)
  let can_resume = !launch_pending &&
    run.status is WaitingForInput &&
    waiting.length() == 1 &&
    steps.all(step => {
      step.status is Succeeded ||
      step.status is Pending ||
      step.status is WaitingForInput
    })
  let basis : Json = {
    "session_key": session_key,
    "cwd": cwd,
    "message_count": message_count,
    "run": run,
    "steps": steps,
    "artifacts": artifacts,
    "event_count": event_count,
  }
  {
    "contract_version": "moonclaw.blocked-recovery.v1",
    "session_key": session_key,
    "cwd": cwd,
    "run_id": run.id,
    "job_id": run.job_id,
    "status": run.status,
    "observed_at": observed_at,
    "checkpoint": @book_learning.digest(
      @encoding/utf8.encode(basis.stringify()),
    ),
    "can_resume": can_resume,
    "resume_receipt": resume_receipt,
    "launch_pending": launch_pending,
    "steps": steps.map(step => {
      let value : Json = {
        "id": step.id,
        "step_id": step.step_id,
        "status": step.status,
        "summary": step.summary,
        "error": step.error,
      }
      value
    }),
    "artifacts": artifacts.map(artifact => {
      let value : Json = {
        "id": artifact.id,
        "logical_key": artifact.logical_key,
        "version": artifact.version,
      }
      value
    }),
    "guidance": if can_resume {
      "Supply the missing input under the existing approved scope. Only the blocked step is resumed; completed work is retained."
    } else {
      "This snapshot does not establish a resumable input checkpoint. Inspect the same run and its journal; reconcile uncertain effects before considering any retry."
    },
  }
}

///|
async fn Gateway::cowork_recovery_snapshot(
  self : Gateway,
  session_key : String,
  run_id : String,
  lookup_checkpoint~ : String? = None,
) -> Json {
  // Do asynchronous reads first, then take the in-memory state together.
  let event_count = self.job_runtime().store().list_run_events(run_id).length()
  guard self.sessions.get(session_key) is Some(session) &&
    session.linked_run_id == Some(run_id) else {
    raise json_error(409, "Conflict", {
      "error": {
        "message": "Choose the run currently linked to this work thread",
      },
    })
  }
  guard self.job_runtime().store().get_run(run_id) is Some(run) else {
    raise json_error(404, "NotFound", {
      "error": {
        "message": "The retained run is missing; work was not restarted",
      },
    })
  }
  let resume_receipt : Json = match
    last_matching_message(session.messages, message => {
      message.kind == "resume" &&
      message.metadata is { "run_id": String(id), .. } &&
      id == run_id &&
      (match cowork_resume_checkpoint(message.metadata) {
        Some(checkpoint) =>
          lookup_checkpoint is Some(wanted) && checkpoint == wanted
        None => false
      })
    }) {
    Some(message) =>
      {
        "checkpoint": cowork_resume_checkpoint(message.metadata),
        "content_digest": @book_learning.digest(
          @encoding/utf8.encode(message.content),
        ),
        "message_id": message.id,
      }
    None => Json::null()
  }
  cowork_recovery_projection(
    session_key,
    cowork_effective_cwd(session, self.cwd),
    session.messages.length(),
    resume_receipt,
    self.active_job_tasks.contains(run_id),
    run,
    self.job_runtime().store().list_step_runs(run_id),
    self.job_runtime().store().list_artifacts(run_id~),
    event_count,
    current_time_ms(),
  )
}

///|
async fn Gateway::handle_cowork_recovery(
  self : Gateway,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
  encoded_session_key : String,
  encoded_run_id : String,
) -> Unit {
  guard artifact_route_id(encoded_session_key) is Some(session_key) &&
    artifact_route_id(encoded_run_id) is Some(run_id) else {
    raise json_error(400, "BadRequest", {
      "error": { "message": "Choose an existing work thread and linked run" },
    })
  }
  let result = self.cowork_recovery_snapshot(
    session_key,
    run_id,
    lookup_checkpoint=r.headers.get("x-moonclaw-recovery-checkpoint"),
  )
  w.header().set("Cache-Control", "no-store")
  self.write_json(w, result)
}

///|
fn cowork_resume_checkpoint(metadata : Json) -> String? {
  match metadata {
    { "recovery_checkpoint": String(value), .. } => Some(value)
    { "recovery_checkpoint": Array([String(value)]), .. } => Some(value)
    _ => None
  }
}
