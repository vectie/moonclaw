///|
async fn Gateway::read_json_body(
  self : Gateway,
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
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let jobs = self.jobs.store().list_definitions()
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
  match self.jobs.store().get_definition(job_id) {
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
  self.jobs.register_definition(definition)
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
  if self.jobs.store().get_definition(job_id) is None {
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
  self.jobs.register_definition(updated)
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
  r : @httpx.RequestReader,
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
  r : @httpx.RequestReader,
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
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let runs = self.jobs.store().list_runs()
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
  match self.jobs.store().get_run(run_id) {
    Some(run) => {
      let steps = self.jobs.store().list_step_runs(run_id)
      let artifacts = self.jobs.store().list_artifacts(run_id?=Some(run_id))
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
