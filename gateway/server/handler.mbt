///|
async fn Gateway::handle_agent(
  self : Gateway,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
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
  let json = @json.parse(text) catch {
    e =>
      raise json_error(400, "BadRequest", {
        "error": { "code": "parse_error", "message": "Invalid JSON: \{e}" },
      })
  }
  let params : @protocol.AgentParams = @json.from_json(json) catch {
    e =>
      raise json_error(400, "BadRequest", {
        "error": {
          "code": "invalid_params",
          "message": "Invalid agent params: \{e}",
        },
      })
  }
  let run_id = match params.run_id {
    Some(id) => id
    None => self.uuid.v4().to_string()
  }
  let idempotency_key = match params.idempotency_key {
    Some(key) => key
    None => run_id
  }
  match self.dedupe.get(idempotency_key) {
    Some(entry) => {
      let response = if entry.ok {
        @protocol.Response::{
          id: run_id,
          ok: true,
          payload: entry.payload,
          error: None,
        }
      } else {
        @protocol.Response::{
          id: run_id,
          ok: false,
          payload: None,
          error: entry.error,
        }
      }
      return self.send_response(w, response)
    }
    None => ()
  }
  let accepted = @protocol.AgentAcceptedPayload::{
    run_id,
    status: "accepted",
    accepted_at: current_time_ms(),
  }
  w.header().set("Content-Type", "application/json")
  w.write_header(202)
  w.write(accepted.to_json().stringify())
  w.flush()
  @async.with_task_group(group => {
    group.spawn_bg(() => {
      self.execute_agent_async(run_id~, idempotency_key~, params)
    })
  })
}

///|
async fn Gateway::execute_agent_async(
  self : Gateway,
  run_id~ : String,
  idempotency_key~ : String,
  params : @protocol.AgentParams,
) -> Unit {
  self.pending_requests = self.pending_requests + 1
  let result = self.execute_agent(run_id~, params)
  self.pending_requests = self.pending_requests - 1
  match result {
    Ok(output) => {
      self.dedupe.set(idempotency_key, DedupeEntry::{
        ts: current_time_ms(),
        ok: true,
        payload: Some(output),
        error: None,
      })
      self.events.put(GatewayEvent::AgentCompleted(run_id))
    }
    Err(error) =>
      self.dedupe.set(idempotency_key, DedupeEntry::{
        ts: current_time_ms(),
        ok: false,
        payload: None,
        error: Some(error),
      })
  }
}

///|
async fn Gateway::execute_agent(
  self : Gateway,
  run_id~ : String,
  params : @protocol.AgentParams,
) -> Result[Json, @protocol.ErrorShape] {
  let cwd = match params.cwd {
    Some(cwd) => cwd
    None => self.cwd
  }
  let session_key = direct_session_key(params.session_key, run_id)
  let session = self.sessions.get_or_create(session_key~, cwd~)
  self.sessions.save_entry(session_key, SessionEntry::{
    session_id: session.session_id,
    updated_at: current_time_ms(),
    channel: session.channel,
    model_override: session.model_override,
    provider_override: session.provider_override,
    cwd: Some(cwd),
  })
  let model_name = match params.model {
    Some(m) => m
    None =>
      match session.model_override {
        Some(m) => m
        None => "default"
      }
  }

  self.logger.info("Spawning agent for run \{run_id} with model \{model_name}")
  self.events.put(GatewayEvent::AgentStarted(run_id))

  let created_at = current_time_ms()
  self.agent_runs[run_id] = AgentRun::{
    run_id,
    session_key,
    status: "running",
    created_at,
    completed_at: None,
    result: None,
    error: None,
  }

  let model = match @model.load(home=self.home, cwd~, name=model_name) {
    Some(m) => m
    None => {
      let error_shape = @protocol.ErrorShape::{
        code: "model_not_found",
        message: "Model not found: \{model_name}",
        details: None,
        retryable: None,
        retry_after_ms: None,
      }
      self.agent_runs[run_id] = AgentRun::{
        run_id,
        session_key,
        status: "failed",
        created_at,
        completed_at: Some(current_time_ms()),
        result: None,
        error: Some(error_shape),
      }
      self.sessions.save_entry(session_key, SessionEntry::{
        session_id: session.session_id,
        updated_at: current_time_ms(),
        channel: session.channel,
        model_override: Some(model_name),
        provider_override: session.provider_override,
        cwd: Some(cwd),
      })
      return Err(error_shape)
    }
  }

  let agent = @agent.new(
    model,
    cwd~,
    logger=self.logger,
    uuid=self.uuid,
    system_message=params.message,
    home=self.home,
  )

  let mut final_content = ""

  agent.event_target.add_listener(event => {
    let event_json = event.to_json()
    match event.desc {
      AssistantMessage(content, ..) if !content.is_blank() =>
        final_content = content
      _ => ()
    }
    match event_json {
      Object(obj) => {
        let kind = match obj.get("desc") {
          Some(Object(desc)) =>
            match desc.get("type") {
              Some(String(t)) => t
              _ => "unknown"
            }
          _ => "unknown"
        }
        let agent_event = @protocol.AgentEventPayload::{
          run_id,
          kind,
          delta: None,
          content: Some(event_json.stringify()),
          usage: None,
        }
        self.agent_events.put(agent_event)
      }
      _ => ()
    }
  })

  agent.start()
  agent.close()

  let completed_at = current_time_ms()
  let conversation_id = agent.id().to_string()
  self.agent_runs[run_id] = AgentRun::{
    run_id,
    session_key,
    status: "completed",
    created_at,
    completed_at: Some(completed_at),
    result: Some({
      "run_id": run_id,
      "status": "completed",
      "session_key": session_key,
      "model": model_name,
      "content": final_content,
      "conversation_id": conversation_id,
      "completed_at": completed_at,
    }),
    error: None,
  }
  self.sessions.save_entry(session_key, SessionEntry::{
    session_id: conversation_id,
    updated_at: completed_at,
    channel: session.channel,
    model_override: Some(model_name),
    provider_override: session.provider_override,
    cwd: Some(cwd),
  })
  self.events.put(GatewayEvent::SessionChanged(run_id))
  Ok({
    "run_id": run_id,
    "status": "completed",
    "session_key": session_key,
    "model": model_name,
    "content": final_content,
    "conversation_id": conversation_id,
    "completed_at": completed_at,
  })
}

///|
async fn Gateway::handle_events_stream(
  self : Gateway,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let sse = @httpx.EventStreamWriter::new(w)
  sse.write_header(200)
  sse.write_event(event="connected", data=b"Gateway event stream connected")
  self.agent_events.listen_forever(include_history=false, event => {
    sse.write_event(
      event="agent_event",
      data=event.to_json().stringify().to_bytes(),
    )
  })
}

///|
async fn Gateway::handle_get_run(
  self : Gateway,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let paths = r.path.split("/").collect()
  let run_id = match paths {
    ["", "v1", "runs", id] => id.to_string()
    _ =>
      raise json_error(400, "BadRequest", {
        "error": {
          "code": "missing_run_id",
          "message": "Missing run_id in path",
        },
      })
  }
  match self.agent_runs.get(run_id) {
    Some(run) => {
      w.header().set("Content-Type", "application/json")
      w.write_header(200)
      w.write(run.to_json().stringify())
    }
    None =>
      raise json_error(404, "NotFound", {
        "error": {
          "code": "run_not_found",
          "message": "Run not found: \{run_id}",
        },
      })
  }
}

///|
async fn Gateway::handle_list_runs(
  self : Gateway,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  w.header().set("Content-Type", "application/json")
  w.write_header(200)
  let runs = self.agent_runs.values().to_array()
  let result : Json = { "runs": runs.map(run => run.to_json()) }
  w.write(result.stringify())
}

///|
async fn Gateway::handle_list_artifacts(
  self : Gateway,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let artifacts = @job.ArtifactStore::new(store=self.job_runtime().store()).list()
  w.header().set("Content-Type", "application/json")
  w.write_header(200)
  let result : Json = {
    "artifacts": artifacts.map(artifact => artifact.to_json()),
  }
  w.write(result.stringify())
}

///|
async fn Gateway::handle_get_artifact(
  self : Gateway,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let paths = r.path.split("/").collect()
  let artifact_id = match paths {
    ["", "v1", "artifacts", id] => id.to_string()
    _ =>
      raise json_error(400, "BadRequest", {
        "error": {
          "code": "missing_artifact_id",
          "message": "Missing artifact_id in path",
        },
      })
  }
  let artifacts = @job.ArtifactStore::new(store=self.job_runtime().store())
  match artifacts.get(artifact_id) {
    Some(artifact) => {
      w.header().set("Content-Type", "application/json")
      w.write_header(200)
      let result : Json = {
        "artifact": artifact.to_json(),
        "content": artifacts.read_text(artifact_id),
      }
      w.write(result.stringify())
    }
    None =>
      raise json_error(404, "NotFound", {
        "error": {
          "code": "artifact_not_found",
          "message": "Artifact not found: \{artifact_id}",
        },
      })
  }
}

///|
async fn Gateway::handle_job_ask(
  self : Gateway,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
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
  let json = @json.parse(text) catch {
    error =>
      raise json_error(400, "BadRequest", {
        "error": { "code": "parse_error", "message": "Invalid JSON: \{error}" },
      })
  }
  let params : @job.JobAskParams = @json.from_json(json) catch {
    error =>
      raise json_error(400, "BadRequest", {
        "error": {
          "code": "invalid_params",
          "message": "Invalid job ask params: \{error}",
        },
      })
  }
  let answer = match
    @job.ChatService::new(store=self.job_runtime().store()).ask(params) {
    Ok(answer) => answer
    Err(error) =>
      raise json_error(400, "BadRequest", {
        "error": { "code": "job_ask_failed", "message": error },
      })
  }
  w.header().set("Content-Type", "application/json")
  w.write_header(200)
  w.write(answer.to_json().stringify())
}
