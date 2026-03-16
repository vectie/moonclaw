///|
fn parse_job_id_param(
  request : @protocol.Request,
) -> Result[String, @protocol.ErrorShape] {
  let params = match request.params {
    Some(params) => params
    None =>
      return Err(@protocol.ErrorShape::{
        code: "missing_params",
        message: "Missing job lookup parameters",
        details: None,
        retryable: None,
        retry_after_ms: None,
      })
  }
  match params {
    String(id) => Ok(id)
    Object(obj) =>
      match obj.get("job_id") {
        Some(String(id)) => Ok(id)
        _ =>
          Err(@protocol.ErrorShape::{
            code: "missing_job_id",
            message: "Missing job_id in params",
            details: None,
            retryable: None,
            retry_after_ms: None,
          })
      }
    _ =>
      Err(@protocol.ErrorShape::{
        code: "invalid_params",
        message: "Invalid job lookup parameters",
        details: None,
        retryable: None,
        retry_after_ms: None,
      })
  }
}

///|
fn parse_job_run_id_param(
  request : @protocol.Request,
) -> Result[String, @protocol.ErrorShape] {
  let params = match request.params {
    Some(params) => params
    None =>
      return Err(@protocol.ErrorShape::{
        code: "missing_params",
        message: "Missing job run lookup parameters",
        details: None,
        retryable: None,
        retry_after_ms: None,
      })
  }
  match params {
    String(id) => Ok(id)
    Object(obj) =>
      match obj.get("run_id") {
        Some(String(id)) => Ok(id)
        _ =>
          Err(@protocol.ErrorShape::{
            code: "missing_run_id",
            message: "Missing run_id in params",
            details: None,
            retryable: None,
            retry_after_ms: None,
          })
      }
    _ =>
      Err(@protocol.ErrorShape::{
        code: "invalid_params",
        message: "Invalid job run lookup parameters",
        details: None,
        retryable: None,
        retry_after_ms: None,
      })
  }
}

///|
async fn Gateway::handle_jobs_list_method(
  self : Gateway,
  request : @protocol.Request,
  w : @httpx.ResponseWriter,
) -> Unit {
  let jobs = self.job_runtime().store().list_definitions()
  self.send_response(w, @protocol.Response::{
    id: request.id,
    ok: true,
    payload: Some({ "jobs": jobs.map(job => job.to_json()) }),
    error: None,
  })
}

///|
async fn Gateway::handle_jobs_get_method(
  self : Gateway,
  request : @protocol.Request,
  w : @httpx.ResponseWriter,
) -> Unit {
  let job_id = match parse_job_id_param(request) {
    Ok(job_id) => job_id
    Err(error) =>
      return self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: false,
        payload: None,
        error: Some(error),
      })
  }
  match self.job_runtime().store().get_definition(job_id) {
    Some(job) =>
      self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: true,
        payload: Some({ "job": job.to_json() }),
        error: None,
      })
    None =>
      self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: false,
        payload: None,
        error: Some(@protocol.ErrorShape::{
          code: "job_not_found",
          message: "Job not found: \{job_id}",
          details: None,
          retryable: None,
          retry_after_ms: None,
        }),
      })
  }
}

///|
async fn Gateway::handle_jobs_create_method(
  self : Gateway,
  request : @protocol.Request,
  w : @httpx.ResponseWriter,
) -> Unit {
  let definition : @job.JobDefinition = match request.params {
    Some(params) =>
      @json.from_json(params) catch {
        error =>
          return self.send_response(w, @protocol.Response::{
            id: request.id,
            ok: false,
            payload: None,
            error: Some(@protocol.ErrorShape::{
              code: "invalid_params",
              message: "Invalid job definition: \{error}",
              details: None,
              retryable: None,
              retry_after_ms: None,
            }),
          })
      }
    None =>
      return self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: false,
        payload: None,
        error: Some(@protocol.ErrorShape::{
          code: "missing_params",
          message: "Missing job definition payload",
          details: None,
          retryable: None,
          retry_after_ms: None,
        }),
      })
  }
  self.job_runtime().register_definition(definition)
  self.send_response(w, @protocol.Response::{
    id: request.id,
    ok: true,
    payload: Some({ "status": "created", "job": definition.to_json() }),
    error: None,
  })
}

///|
async fn Gateway::handle_jobs_update_method(
  self : Gateway,
  request : @protocol.Request,
  w : @httpx.ResponseWriter,
) -> Unit {
  let definition : @job.JobDefinition = match request.params {
    Some(params) =>
      @json.from_json(params) catch {
        error =>
          return self.send_response(w, @protocol.Response::{
            id: request.id,
            ok: false,
            payload: None,
            error: Some(@protocol.ErrorShape::{
              code: "invalid_params",
              message: "Invalid job definition: \{error}",
              details: None,
              retryable: None,
              retry_after_ms: None,
            }),
          })
      }
    None =>
      return self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: false,
        payload: None,
        error: Some(@protocol.ErrorShape::{
          code: "missing_params",
          message: "Missing job definition payload",
          details: None,
          retryable: None,
          retry_after_ms: None,
        }),
      })
  }
  if self.job_runtime().store().get_definition(definition.id) is None {
    return self.send_response(w, @protocol.Response::{
      id: request.id,
      ok: false,
      payload: None,
      error: Some(@protocol.ErrorShape::{
        code: "job_not_found",
        message: "Job not found: \{definition.id}",
        details: None,
        retryable: None,
        retry_after_ms: None,
      }),
    })
  }
  self.job_runtime().register_definition(definition)
  self.send_response(w, @protocol.Response::{
    id: request.id,
    ok: true,
    payload: Some({ "status": "updated", "job": definition.to_json() }),
    error: None,
  })
}

///|
async fn Gateway::handle_jobs_run_method(
  self : Gateway,
  request : @protocol.Request,
  w : @httpx.ResponseWriter,
) -> Unit {
  let job_id = match parse_job_id_param(request) {
    Ok(job_id) => job_id
    Err(error) =>
      return self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: false,
        payload: None,
        error: Some(error),
      })
  }
  match self.trigger_job_definition(job_id) {
    Ok(run) =>
      self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: true,
        payload: Some({ "status": "started", "run": run.to_json() }),
        error: None,
      })
    Err(error) =>
      self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: false,
        payload: None,
        error: Some(@protocol.ErrorShape::{
          code: "job_run_failed",
          message: error,
          details: None,
          retryable: None,
          retry_after_ms: None,
        }),
      })
  }
}

///|
async fn Gateway::handle_jobs_cancel_method(
  self : Gateway,
  request : @protocol.Request,
  w : @httpx.ResponseWriter,
) -> Unit {
  let job_id = match parse_job_id_param(request) {
    Ok(job_id) => job_id
    Err(error) =>
      return self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: false,
        payload: None,
        error: Some(error),
      })
  }
  match self.cancel_job_definition_run(job_id) {
    Ok(run) =>
      self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: true,
        payload: Some({ "status": "cancelling", "run": run.to_json() }),
        error: None,
      })
    Err(error) =>
      self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: false,
        payload: None,
        error: Some(@protocol.ErrorShape::{
          code: "job_cancel_failed",
          message: error,
          details: None,
          retryable: None,
          retry_after_ms: None,
        }),
      })
  }
}

///|
async fn Gateway::handle_jobs_force_cancel_method(
  self : Gateway,
  request : @protocol.Request,
  w : @httpx.ResponseWriter,
) -> Unit {
  let job_id = match parse_job_id_param(request) {
    Ok(job_id) => job_id
    Err(error) =>
      return self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: false,
        payload: None,
        error: Some(error),
      })
  }
  match self.cancel_job_definition_run(job_id, force=true) {
    Ok(run) =>
      self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: true,
        payload: Some({ "status": "force_cancelling", "run": run.to_json() }),
        error: None,
      })
    Err(error) =>
      self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: false,
        payload: None,
        error: Some(@protocol.ErrorShape::{
          code: "job_force_cancel_failed",
          message: error,
          details: None,
          retryable: None,
          retry_after_ms: None,
        }),
      })
  }
}

///|
async fn Gateway::handle_job_runs_list_method(
  self : Gateway,
  request : @protocol.Request,
  w : @httpx.ResponseWriter,
) -> Unit {
  let runs = self.job_runtime().store().list_runs()
  self.send_response(w, @protocol.Response::{
    id: request.id,
    ok: true,
    payload: Some({ "runs": runs.map(run => run.to_json()) }),
    error: None,
  })
}

///|
async fn Gateway::handle_job_runs_get_method(
  self : Gateway,
  request : @protocol.Request,
  w : @httpx.ResponseWriter,
) -> Unit {
  let run_id = match parse_job_run_id_param(request) {
    Ok(run_id) => run_id
    Err(error) =>
      return self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: false,
        payload: None,
        error: Some(error),
      })
  }
  match self.job_runtime().store().get_run(run_id) {
    Some(run) =>
      self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: true,
        payload: Some({
          "run": run.to_json(),
          "steps": self
          .job_runtime()
          .store()
          .list_step_runs(run_id)
          .map(step => step.to_json())
          .to_json(),
          "artifacts": self
          .job_runtime()
          .store()
          .list_artifacts(run_id~)
          .map(artifact => artifact.to_json())
          .to_json(),
        }),
        error: None,
      })
    None =>
      self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: false,
        payload: None,
        error: Some(@protocol.ErrorShape::{
          code: "job_run_not_found",
          message: "Job run not found: \{run_id}",
          details: None,
          retryable: None,
          retry_after_ms: None,
        }),
      })
  }
}

///|
async fn Gateway::handle_job_ui_get_method(
  self : Gateway,
  request : @protocol.Request,
  w : @httpx.ResponseWriter,
) -> Unit {
  let run_id = match parse_job_run_id_param(request) {
    Ok(run_id) => run_id
    Err(error) =>
      return self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: false,
        payload: None,
        error: Some(error),
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
    Some(snapshot) =>
      self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: true,
        payload: Some({ "snapshot": snapshot.to_json() }),
        error: None,
      })
    None =>
      self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: false,
        payload: None,
        error: Some(@protocol.ErrorShape::{
          code: "job_run_not_found",
          message: "Job run not found: \{run_id}",
          details: None,
          retryable: None,
          retry_after_ms: None,
        }),
      })
  }
}

///|
async fn Gateway::handle_job_ui_events_method(
  self : Gateway,
  request : @protocol.Request,
  w : @httpx.ResponseWriter,
) -> Unit {
  let run_id = match parse_job_run_id_param(request) {
    Ok(run_id) => run_id
    Err(error) =>
      return self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: false,
        payload: None,
        error: Some(error),
      })
  }
  match self.job_runtime().store().get_run(run_id) {
    Some(_) =>
      self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: true,
        payload: Some({
          "timeline": @job.load_run_ui_timeline(
            self.job_runtime().store(),
            run_id,
          )
          .map(entry => entry.to_json())
          .to_json(),
        }),
        error: None,
      })
    None =>
      self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: false,
        payload: None,
        error: Some(@protocol.ErrorShape::{
          code: "job_run_not_found",
          message: "Job run not found: \{run_id}",
          details: None,
          retryable: None,
          retry_after_ms: None,
        }),
      })
  }
}
