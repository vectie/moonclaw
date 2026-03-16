///|
async fn Gateway::read_json_body(
  _self : Gateway,
  r : @httpx.RequestReader,
  invalid_message : String,
) -> Json {
  let body = r.body.read_all().binary()
  let text : String = @encoding/utf8.decode(body) catch {
    _ =>
      raise json_error(400, "BadRequest", {
        "error": {
          "code": "invalid_utf8",
          "message": "Invalid UTF-8 in request body",
        },
      })
  }
  @json.parse(text) catch {
    error =>
      raise json_error(400, "BadRequest", {
        "error": {
          "code": "invalid_json",
          "message": "\{invalid_message}: \{error}",
        },
      })
  }
}

///|
async fn Gateway::handle_list_jobs(
  self : Gateway,
  _r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let jobs = self.job_runtime().store().list_definitions()
  let result : Json = { "jobs": jobs.map(job => job.to_json()) }
  w.header().set("Content-Type", "application/json")
  w.write_header(200)
  w.write(result.stringify())
}

///|
async fn Gateway::handle_get_job(
  self : Gateway,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let paths = r.path.split("/").collect()
  let job_id = match paths {
    ["", "v1", "jobs", id] => id.to_string()
    _ =>
      raise json_error(400, "BadRequest", {
        "error": {
          "code": "missing_job_id",
          "message": "Missing job id in path",
        },
      })
  }
  match self.job_runtime().store().get_definition(job_id) {
    Some(job) => {
      let result : Json = { "job": job.to_json() }
      w.header().set("Content-Type", "application/json")
      w.write_header(200)
      w.write(result.stringify())
    }
    None =>
      raise json_error(404, "NotFound", {
        "error": {
          "code": "job_not_found",
          "message": "Job not found: \{job_id}",
        },
      })
  }
}

///|
async fn Gateway::handle_create_job(
  self : Gateway,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let payload = self.read_json_body(r, "Invalid job definition payload")
  let definition : @job.JobDefinition = @json.from_json(payload) catch {
    error =>
      raise json_error(400, "BadRequest", {
        "error": {
          "code": "invalid_params",
          "message": "Invalid job definition: \{error}",
        },
      })
  }
  self.job_runtime().register_definition(definition)
  let result : Json = {
    "status": "created".to_json(),
    "job": definition.to_json(),
  }
  w.header().set("Content-Type", "application/json")
  w.write_header(200)
  w.write(result.stringify())
}

///|
async fn Gateway::handle_update_job(
  self : Gateway,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
  job_id : String,
) -> Unit {
  if self.job_runtime().store().get_definition(job_id) is None {
    raise json_error(404, "NotFound", {
      "error": {
        "code": "job_not_found",
        "message": "Job not found: \{job_id}",
      },
    })
  }
  let payload = self.read_json_body(r, "Invalid job definition payload")
  let definition : @job.JobDefinition = @json.from_json(payload) catch {
    error =>
      raise json_error(400, "BadRequest", {
        "error": {
          "code": "invalid_params",
          "message": "Invalid job definition: \{error}",
        },
      })
  }
  let updated = @job.JobDefinition::{ ..definition, id: job_id }
  self.job_runtime().register_definition(updated)
  let result : Json = {
    "status": "updated".to_json(),
    "job": updated.to_json(),
  }
  w.header().set("Content-Type", "application/json")
  w.write_header(200)
  w.write(result.stringify())
}

///|
async fn Gateway::handle_run_job(
  self : Gateway,
  _r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
  job_id : String,
) -> Unit {
  match self.trigger_job_definition(job_id) {
    Ok(run) => {
      let result : Json = {
        "status": "started".to_json(),
        "run": run.to_json(),
      }
      w.header().set("Content-Type", "application/json")
      w.write_header(200)
      w.write(result.stringify())
    }
    Err(error) =>
      raise json_error(400, "BadRequest", {
        "error": { "code": "job_run_failed", "message": error },
      })
  }
}

///|
async fn Gateway::handle_cancel_job(
  self : Gateway,
  _r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
  job_id : String,
  force : Bool,
) -> Unit {
  match self.cancel_job_definition_run(job_id, force~) {
    Ok(run) => {
      w.header().set("Content-Type", "application/json")
      w.write_header(200)
      let status = if force { "force_cancelling" } else { "cancelling" }
      let result : Json = { "status": status.to_json(), "run": run.to_json() }
      w.write(result.stringify())
    }
    Err(error) =>
      raise json_error(400, "BadRequest", {
        "error": {
          "code": if force {
            "job_force_cancel_failed"
          } else {
            "job_cancel_failed"
          },
          "message": error,
        },
      })
  }
}

///|
async fn Gateway::handle_list_job_runs(
  self : Gateway,
  _r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let runs = self.job_runtime().store().list_runs()
  let result : Json = { "runs": runs.map(run => run.to_json()) }
  w.header().set("Content-Type", "application/json")
  w.write_header(200)
  w.write(result.stringify())
}

///|
async fn Gateway::handle_get_job_run(
  self : Gateway,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let paths = r.path.split("/").collect()
  let run_id = match paths {
    ["", "v1", "jobs", "runs", id] => id.to_string()
    _ =>
      raise json_error(400, "BadRequest", {
        "error": {
          "code": "missing_run_id",
          "message": "Missing run id in path",
        },
      })
  }
  match self.job_runtime().store().get_run(run_id) {
    Some(run) => {
      let steps = self.job_runtime().store().list_step_runs(run_id)
      let artifacts = self.job_runtime().store().list_artifacts(run_id~)
      let result : Json = {
        "run": run.to_json(),
        "steps": steps.map(step => step.to_json()).to_json(),
        "artifacts": artifacts.map(artifact => artifact.to_json()).to_json(),
      }
      w.header().set("Content-Type", "application/json")
      w.write_header(200)
      w.write(result.stringify())
    }
    None =>
      raise json_error(404, "NotFound", {
        "error": {
          "code": "job_run_not_found",
          "message": "Job run not found: \{run_id}",
        },
      })
  }
}

///|
async fn Gateway::handle_get_job_ui(
  self : Gateway,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let paths = r.path.split("/").collect()
  let run_id = match paths {
    ["", "v1", "jobs", "runs", id, "ui"] => id.to_string()
    _ =>
      raise json_error(400, "BadRequest", {
        "error": {
          "code": "missing_run_id",
          "message": "Missing run id in path",
        },
      })
  }
  let remote = self.resolve_remote_ui_for_job_run(run_id)
  match
    @job.build_job_ui_snapshot(
      self.job_runtime().store(),
      run_id,
      linked_remote=remote.links,
      handoffs=remote.handoffs,
    ) {
    Some(snapshot) => {
      let result : Json = { "snapshot": snapshot.to_json() }
      w.header().set("Content-Type", "application/json")
      w.write_header(200)
      w.write(result.stringify())
    }
    None =>
      raise json_error(404, "NotFound", {
        "error": {
          "code": "job_run_not_found",
          "message": "Job run not found: \{run_id}",
        },
      })
  }
}

///|
async fn Gateway::handle_get_job_ui_events(
  self : Gateway,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let paths = r.path.split("/").collect()
  let run_id = match paths {
    ["", "v1", "jobs", "runs", id, "events"] => id.to_string()
    _ =>
      raise json_error(400, "BadRequest", {
        "error": {
          "code": "missing_run_id",
          "message": "Missing run id in path",
        },
      })
  }
  match self.job_runtime().store().get_run(run_id) {
    Some(_) => {
      let result : Json = {
        "timeline": @job.load_run_ui_timeline(
          self.job_runtime().store(),
          run_id,
        )
        .map(entry => entry.to_json())
        .to_json(),
      }
      w.header().set("Content-Type", "application/json")
      w.write_header(200)
      w.write(result.stringify())
    }
    None =>
      raise json_error(404, "NotFound", {
        "error": {
          "code": "job_run_not_found",
          "message": "Job run not found: \{run_id}",
        },
      })
  }
}

///|
fn Gateway::job_run_is_live(_self : Gateway, run : @job.JobRun) -> Bool {
  run.status is @job.RunStatus::Pending || run.status is @job.RunStatus::Running
}

///|
async fn Gateway::handle_stream_job_ui_events(
  self : Gateway,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let paths = r.path.split("/").collect()
  let run_id = match paths {
    ["", "v1", "jobs", "runs", id, "events", "stream"] => id.to_string()
    _ =>
      raise json_error(400, "BadRequest", {
        "error": {
          "code": "missing_run_id",
          "message": "Missing run id in path",
        },
      })
  }
  if self.job_runtime().store().get_run(run_id) is None {
    raise json_error(404, "NotFound", {
      "error": {
        "code": "job_run_not_found",
        "message": "Job run not found: \{run_id}",
      },
    })
  }
  let sse = @httpx.EventStreamWriter::new(w)
  sse.write_header(200)
  sse.write_event(
    event="connected",
    data=@encoding/utf8.encode({ "run_id": run_id }.to_json().stringify()),
  )
  let mut sent = 0
  while true {
    let timeline = @job.load_run_ui_timeline(self.job_runtime().store(), run_id)
    if sent < timeline.length() {
      for index in sent..<timeline.length() {
        let entry = timeline[index]
        sse.write_event(
          id=entry.id,
          event="job_ui_event",
          data=@encoding/utf8.encode(entry.to_json().stringify()),
        )
      }
      sent = timeline.length()
    }
    let current_run = match self.job_runtime().store().get_run(run_id) {
      Some(run) => run
      None => break
    }
    if !self.job_run_is_live(current_run) {
      sse.write_event(
        event="job_ui_complete",
        data=@encoding/utf8.encode(current_run.to_json().stringify()),
      )
      break
    }
    @async.sleep(700)
  }
}
