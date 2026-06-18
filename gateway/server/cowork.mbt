///|
struct CoworkSessionSummary {
  session_key : String
  session_id : String
  title : String
  updated_at : Int
  state : String
  last_message_preview : String?
  channel : String?
  cwd : String?
  model_override : String?
  provider_override : String?
  has_plan_mode : Bool
  linked_proposal_id : String?
  linked_run_id : String?
} derive(ToJson, FromJson, Debug)

///|
struct CoworkProposalRef {
  id : String
  title : String
  summary : String
  status : String
  request_text : String
  updated_at : Int
} derive(ToJson, FromJson, Debug)

///|
struct CoworkRunRef {
  id : String
  job_id : String
  status : String
  summary : String?
  error : String?
  current_step_id : String?
  workspace_dir : String?
} derive(ToJson, FromJson, Debug)

///|
struct CoworkSessionDetail {
  session : CoworkSessionSummary
  messages : Array[SessionMessage]
  plan_preview : String?
  linked_proposal : CoworkProposalRef?
  linked_run : CoworkRunRef?
} derive(ToJson, FromJson, Debug)

///|
struct CoworkSessionCreateParams {
  cwd : String?
  title : String?
} derive(FromJson, Debug)

///|
struct CoworkMessageParams {
  content : String
  cwd : String?
  model : String?
} derive(FromJson, Debug)

///|
struct CoworkConfigParams {
  title : String?
  cwd : String?
  model : String?
  provider : String?
} derive(FromJson, Debug)

///|
struct CoworkPlanParams {
  request_text : String?
  guidance : String?
  cwd : String?
} derive(FromJson, Debug)

///|
struct CoworkResumeParams {
  content : String
} derive(FromJson, Debug)

///|
async fn read_json_request_body(
  r : @httpx.RequestReader,
) -> Json raise HttpError {
  let body = r.body.read_all().binary() catch {
      error =>
        raise json_error(400, "BadRequest", {
          "error": {
            "code": "read_error",
            "message": "Failed to read request body: \{error}",
          },
        })
    }
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
        "error": { "code": "parse_error", "message": "Invalid JSON: \{error}" },
      })
  }
}

///|
async fn[T : @json.FromJson] decode_request_body(
  r : @httpx.RequestReader,
  kind : String,
) -> T raise HttpError {
  @json.from_json(read_json_request_body(r)) catch {
    error =>
      raise json_error(400, "BadRequest", {
        "error": {
          "code": "invalid_params",
          "message": "Invalid \{kind}: \{error}",
        },
      })
  }
}

///|
async fn Gateway::write_json(
  self : Gateway,
  w : @httpx.ResponseWriter,
  payload : Json,
  status? : Int = 200,
) -> Unit {
  ignore(self)
  w.header().set("Content-Type", "application/json")
  w.write_header(status)
  w.write(payload.stringify())
}

///|
fn compact_cowork_preview(text : String, max_len : Int) -> String {
  let trimmed = text.trim().to_owned()
  if trimmed.length() <= max_len {
    trimmed
  } else {
    "\{trimmed[:max_len - 3].to_owned()}..."
  }
}

///|
fn last_matching_message(
  messages : Array[SessionMessage],
  predicate : (SessionMessage) -> Bool,
) -> SessionMessage? {
  for index in 0..<messages.length() {
    let message = messages[messages.length() - index - 1]
    if predicate(message) {
      return Some(message)
    }
  }
  None
}

///|
fn cowork_message_title(entry : SessionEntry) -> String {
  match entry.title {
    Some(title) if !title.trim().to_owned().is_blank() =>
      return title.trim().to_owned()
    _ => ()
  }
  match entry.plan_mode {
    Some(state) => compact_cowork_preview(state.request_text, 64)
    None =>
      match entry.linked_proposal_id {
        Some(proposal_id) => proposal_id
        None =>
          match
            last_matching_message(entry.messages, fn(message) {
              message.role == "user" &&
              !message.content.trim().to_owned().is_blank()
            }) {
            Some(message) => compact_cowork_preview(message.content, 64)
            None =>
              match
                last_matching_message(entry.messages, fn(message) {
                  !message.content.trim().to_owned().is_blank()
                }) {
                Some(message) => compact_cowork_preview(message.content, 64)
                None => "New chat"
              }
          }
      }
  }
}

///|
fn session_last_message_preview(messages : Array[SessionMessage]) -> String? {
  match
    last_matching_message(messages, fn(message) {
      !message.content.trim().to_owned().is_blank()
    }) {
    Some(message) => Some(compact_cowork_preview(message.content, 120))
    None => None
  }
}

///|
fn cowork_session_state(entry : SessionEntry) -> String {
  if entry.plan_mode is Some(_) {
    "Plan"
  } else if entry.linked_run_id is Some(_) {
    "Run"
  } else if entry.linked_proposal_id is Some(_) {
    "Proposal"
  } else {
    "Chat"
  }
}

///|
fn cowork_session_summary(
  session_key : String,
  entry : SessionEntry,
) -> CoworkSessionSummary {
  CoworkSessionSummary::{
    session_key,
    session_id: entry.session_id,
    title: cowork_message_title(entry),
    updated_at: entry.updated_at,
    state: cowork_session_state(entry),
    last_message_preview: session_last_message_preview(entry.messages),
    channel: entry.channel,
    cwd: entry.cwd,
    model_override: entry.model_override,
    provider_override: entry.provider_override,
    has_plan_mode: entry.plan_mode is Some(_),
    linked_proposal_id: entry.linked_proposal_id,
    linked_run_id: entry.linked_run_id,
  }
}

///|
fn cowork_effective_cwd(entry : SessionEntry, fallback : String) -> String {
  match entry.cwd {
    Some(cwd) if !cwd.trim().to_owned().is_blank() => cwd
    _ => fallback
  }
}

///|
fn proposal_status_text(status : @job.JobProposalStatus) -> String {
  match status {
    @job.JobProposalStatus::Draft => "Draft"
    @job.JobProposalStatus::Confirmed => "Confirmed"
    @job.JobProposalStatus::Rejected => "Rejected"
  }
}

///|
fn proposal_ref_from_store(
  store : @job.SystemStore,
  proposal_id : String?,
) -> CoworkProposalRef? {
  match proposal_id {
    Some(id) =>
      match store.get_job_proposal(id) {
        Some(proposal) =>
          Some(CoworkProposalRef::{
            id: proposal.id,
            title: proposal.title,
            summary: proposal.summary,
            status: proposal_status_text(proposal.status),
            request_text: proposal.request_text,
            updated_at: proposal.updated_at,
          })
        None => None
      }
    None => None
  }
}

///|
fn current_run_step_id(store : @job.SystemStore, run_id : String) -> String? {
  let steps = store.list_step_runs(run_id)
  for step in steps {
    if step.status is @job.RunStatus::Running ||
      step.status is @job.RunStatus::WaitingForInput {
      return Some(step.step_id)
    }
  }
  None
}

///|
fn run_ref_from_store(
  store : @job.SystemStore,
  run_id : String?,
) -> CoworkRunRef? {
  match run_id {
    Some(id) =>
      match store.get_run(id) {
        Some(run) =>
          Some(CoworkRunRef::{
            id: run.id,
            job_id: run.job_id,
            status: run.status.to_json().stringify(),
            summary: run.summary,
            error: run.error,
            current_step_id: current_run_step_id(store, run.id),
            workspace_dir: run.workspace_dir,
          })
        None => None
      }
    None => None
  }
}

///|
fn cowork_plan_preview_text(entry : SessionEntry) -> String? {
  entry.plan_mode.map(fn(state) {
    @job.render_job_plan_preview_for_chat(
      @job.plan_preview_from_proposal(state.latest_candidate),
    )
  })
}

///|
fn Gateway::cowork_session_detail(
  self : Gateway,
  session_key : String,
  entry : SessionEntry,
) -> CoworkSessionDetail {
  let store = self.job_runtime().store()
  CoworkSessionDetail::{
    session: cowork_session_summary(session_key, entry),
    messages: entry.messages,
    plan_preview: cowork_plan_preview_text(entry),
    linked_proposal: proposal_ref_from_store(store, entry.linked_proposal_id),
    linked_run: run_ref_from_store(store, entry.linked_run_id),
  }
}

///|
fn Gateway::append_session_message(
  self : Gateway,
  entry : SessionEntry,
  role : String,
  kind : String,
  content : String,
  metadata? : Json = {},
) -> SessionEntry {
  {
    ..entry,
    updated_at: current_time_ms(),
    messages: [
      ..entry.messages,
      SessionMessage::{
        id: self.uuid.v4().to_string(),
        role,
        kind,
        content,
        timestamp: current_time_ms(),
        metadata,
      },
    ],
  }
}

///|
async fn Gateway::save_session_detail(
  self : Gateway,
  session_key : String,
  entry : SessionEntry,
) -> Unit {
  self.sessions.save_entry(session_key, entry)
}

///|
fn cowork_session_key(gateway : Gateway) -> String {
  "cowork:\{gateway.uuid.v4().to_string()}"
}

///|
fn cowork_session_for_write(
  gateway : Gateway,
  session_key : String,
  cwd : String,
) -> SessionEntry {
  gateway.sessions.get_or_create(session_key~, cwd~)
}

///|
async fn Gateway::handle_list_cowork_sessions(
  self : Gateway,
  _r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let sessions : Array[(String, SessionEntry)] = []
  for session_key, entry in self.sessions.sessions {
    if !entry.messages.is_empty() ||
      entry.plan_mode is Some(_) ||
      entry.linked_proposal_id is Some(_) ||
      entry.linked_run_id is Some(_) ||
      session_key.has_prefix("cowork:") {
      sessions.push((session_key, entry))
    }
  }
  sessions.sort_by(fn(left, right) {
    right.1.updated_at.compare(left.1.updated_at)
  })
  self.write_json(w, {
    "sessions": sessions.map(fn(item) {
      cowork_session_summary(item.0, item.1).to_json()
    }),
  })
}

///|
async fn Gateway::handle_create_cowork_session(
  self : Gateway,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let params : CoworkSessionCreateParams = decode_request_body(
    r, "cowork session params",
  )
  let session_key = cowork_session_key(self)
  let cwd = params.cwd.unwrap_or(self.cwd)
  let mut entry = cowork_session_for_write(self, session_key, cwd)
  match params.title {
    Some(title) => {
      let trimmed = title.trim().to_owned()
      if !trimmed.is_blank() {
        entry = { ..entry, title: Some(trimmed) }
        entry = self.append_session_message(
          entry,
          "system",
          "status",
          "Conversation ready: \{trimmed}",
          metadata={ "title": trimmed },
        )
      }
    }
    None => ()
  }
  self.save_session_detail(session_key, entry)
  self.write_json(
    w,
    { "session": self.cowork_session_detail(session_key, entry).to_json() },
    status=201,
  )
}

///|
async fn Gateway::handle_get_cowork_session(
  self : Gateway,
  _r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
  session_key : String,
) -> Unit {
  let entry = match self.sessions.get(session_key) {
    Some(entry) => entry
    None =>
      raise json_error(404, "NotFound", {
        "error": {
          "code": "session_not_found",
          "message": "Cowork session not found: \{session_key}",
        },
      })
  }
  self.write_json(w, {
    "session": self.cowork_session_detail(session_key, entry).to_json(),
  })
}

///|
async fn Gateway::handle_update_cowork_config(
  self : Gateway,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
  session_key : String,
) -> Unit {
  let params : CoworkConfigParams = decode_request_body(
    r, "cowork config params",
  )
  let session = match self.sessions.get(session_key) {
    Some(entry) => entry
    None =>
      raise json_error(404, "NotFound", {
        "error": {
          "code": "session_not_found",
          "message": "Cowork session not found: \{session_key}",
        },
      })
  }
  let title = match params.title {
    Some(value) => {
      let trimmed = value.trim().to_owned()
      if trimmed.is_blank() {
        None
      } else {
        Some(trimmed)
      }
    }
    None => session.title
  }
  let cwd = match params.cwd {
    Some(value) => {
      let trimmed = value.trim().to_owned()
      if trimmed.is_blank() {
        None
      } else {
        Some(trimmed)
      }
    }
    None => session.cwd
  }
  let model_override = match params.model {
    Some(value) => {
      let trimmed = value.trim().to_owned()
      if trimmed.is_blank() {
        None
      } else {
        Some(trimmed)
      }
    }
    None => session.model_override
  }
  let provider_override = match params.provider {
    Some(value) => {
      let trimmed = value.trim().to_owned()
      if trimmed.is_blank() {
        None
      } else {
        Some(trimmed)
      }
    }
    None => session.provider_override
  }
  let updated = SessionEntry::{
    ..session,
    title,
    cwd,
    model_override,
    provider_override,
    updated_at: current_time_ms(),
  }
  self.save_session_detail(session_key, updated)
  self.write_json(w, {
    "session": self.cowork_session_detail(session_key, updated).to_json(),
  })
}

///|
fn cowork_trimmed_text(text : String, max_len : Int) -> String {
  let trimmed = text.trim().to_owned()
  if trimmed.length() <= max_len {
    trimmed
  } else {
    "\{trimmed[:max_len - 3].to_owned()}..."
  }
}

///|
fn cowork_tool_call_text(tool_call : @ai.ToolCall) -> String {
  let arguments = tool_call.arguments.unwrap_or("{}")
  [
    "Tool: \{tool_call.name}",
    "",
    "Arguments:",
    cowork_trimmed_text(arguments, 1600),
  ].join("\n")
}

///|
fn cowork_tool_result_text(
  tool_call : @ai.ToolCall,
  rendered : String,
) -> String {
  [
    "Tool: \{tool_call.name}",
    "",
    "Result:",
    cowork_trimmed_text(rendered, 2400),
  ].join("\n")
}

///|
fn cowork_agent_error_shape(
  code : String,
  message : String,
) -> @protocol.ErrorShape {
  @protocol.ErrorShape::{
    code,
    message,
    details: None,
    retryable: None,
    retry_after_ms: None,
  }
}

///|
async fn Gateway::execute_cowork_agent_message(
  self : Gateway,
  session : SessionEntry,
  cwd : String,
  content : String,
  model_name : String,
) -> Result[SessionEntry, @protocol.ErrorShape] {
  let model = match @model.load(home=self.home, cwd~, name=model_name) {
    Some(model) => model
    None =>
      return Err(
        cowork_agent_error_shape(
          "model_not_found",
          "Model not found: \{model_name}",
        ),
      )
  }
  let agent = @agent.new(
    model,
    cwd~,
    logger=self.logger,
    uuid=self.uuid,
    system_message=content,
    home=self.home,
  )
  let mut updated_session = session
  let mut final_content = ""
  let mut thinking_started = false
  agent.event_target.add_listener(event => {
    match event.desc {
      PreConversation =>
        if !thinking_started {
          thinking_started = true
          updated_session = self.append_session_message(
            updated_session, "assistant", "thinking", "Thinking through the request and preparing the next action.",
          )
        }
      PreToolCall(tool_call) =>
        updated_session = self.append_session_message(
          updated_session,
          "assistant",
          "tool_call",
          cowork_tool_call_text(tool_call),
          metadata={ "tool_name": tool_call.name, "tool_call_id": tool_call.id },
        )
      PostToolCall(tool_call, rendered~, ..) =>
        updated_session = self.append_session_message(
          updated_session,
          "assistant",
          "tool_result",
          cowork_tool_result_text(tool_call, rendered),
          metadata={ "tool_name": tool_call.name, "tool_call_id": tool_call.id },
        )
      AssistantMessageDelta(delta) if !delta.is_blank() && !thinking_started => {
        thinking_started = true
        updated_session = self.append_session_message(
          updated_session, "assistant", "thinking", "Drafting the response.",
        )
      }
      AssistantMessage(content, usage~, tool_calls~) => {
        if !content.is_blank() {
          final_content = content
        }
        if !tool_calls.is_empty() && final_content.is_blank() {
          final_content = tool_calls
            .map(fn(tool_call) { tool_call.name })
            .join(", ")
        }
        ignore(usage)
      }
      _ => ()
    }
  })
  agent.start() catch {
    error =>
      return Err(
        cowork_agent_error_shape(
          "agent_failed",
          "Cowork agent failed: \{error}",
        ),
      )
  }
  agent.close()
  let conversation_id = agent.id().to_string()
  Ok(
    self.append_session_message(
      SessionEntry::{
        ..updated_session,
        session_id: conversation_id,
        model_override: Some(model_name),
        cwd: Some(cwd),
      },
      "assistant",
      "assistant",
      final_content,
      metadata={ "model": model_name, "conversation_id": conversation_id },
    ),
  )
}

///|
async fn Gateway::handle_cowork_send_message(
  self : Gateway,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
  session_key : String,
) -> Unit {
  let params : CoworkMessageParams = decode_request_body(
    r, "cowork message params",
  )
  let content = params.content.trim().to_owned()
  if content.is_blank() {
    raise json_error(400, "BadRequest", {
      "error": {
        "code": "missing_content",
        "message": "Cowork message content is required",
      },
    })
  }
  let mut session = cowork_session_for_write(
    self,
    session_key,
    params.cwd.unwrap_or(self.cwd),
  )
  let cwd = params.cwd.unwrap_or(cowork_effective_cwd(session, self.cwd))
  session = self.append_session_message(session, "user", "user", content)
  self.save_session_detail(session_key, session)
  let mut final_session = match self.sessions.get(session_key) {
    Some(entry) => entry
    None => session
  }
  match final_session.plan_mode {
    Some(state) => {
      let notes = [..state.notes, content]
      let effective_request = planning_request_text(state.request_text, notes)
      let candidate = self.job_app.plan_proposal(effective_request)
      let candidate = @job.promote_plan_candidate(
        candidate,
        "plan-preview",
        state.request_text,
        current_time_ms(),
      )
      let preview_text = @job.render_job_plan_preview_for_chat(
        @job.plan_preview_from_proposal(candidate),
      )
      final_session = self.append_session_message(
        SessionEntry::{
          ..final_session,
          plan_mode: Some(PlanModeState::{
            request_text: state.request_text,
            notes,
            latest_candidate: candidate,
            updated_at: current_time_ms(),
          }),
        },
        "assistant",
        "plan_preview",
        preview_text,
      )
      self.save_session_detail(session_key, final_session)
      self.write_json(w, {
        "session": self
        .cowork_session_detail(session_key, final_session)
        .to_json(),
      })
    }
    None => {
      let model_name = match params.model {
        Some(value) if !value.trim().to_owned().is_blank() =>
          value.trim().to_owned()
        _ =>
          match final_session.model_override {
            Some(value) if !value.trim().to_owned().is_blank() =>
              value.trim().to_owned()
            _ => "default"
          }
      }
      match
        self.execute_cowork_agent_message(
          final_session, cwd, content, model_name,
        ) {
        Ok(updated_session) => {
          final_session = updated_session
          self.save_session_detail(session_key, final_session)
          self.write_json(w, {
            "session": self
            .cowork_session_detail(session_key, final_session)
            .to_json(),
          })
        }
        Err(error) => {
          final_session = self.append_session_message(
            final_session,
            "assistant",
            "error",
            error.message,
            metadata=error.to_json(),
          )
          self.save_session_detail(session_key, final_session)
          raise json_error(500, "AgentError", {
            "error": error.to_json(),
            "session": self
            .cowork_session_detail(session_key, final_session)
            .to_json(),
          })
        }
      }
    }
  }
}

///|
fn cowork_plan_request_text(params : CoworkPlanParams) -> String {
  match params.request_text {
    Some(text) if !text.trim().to_owned().is_blank() => text.trim().to_owned()
    _ => params.guidance.unwrap_or("").trim().to_owned()
  }
}

///|
async fn Gateway::handle_cowork_plan(
  self : Gateway,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
  session_key : String,
) -> Unit {
  let params : CoworkPlanParams = decode_request_body(r, "cowork plan params")
  let request_text = cowork_plan_request_text(params)
  if request_text.is_blank() {
    raise json_error(400, "BadRequest", {
      "error": {
        "code": "missing_request_text",
        "message": "Plan request text is required",
      },
    })
  }
  let mut session = cowork_session_for_write(
    self,
    session_key,
    params.cwd.unwrap_or(self.cwd),
  )
  let cwd = params.cwd.unwrap_or(cowork_effective_cwd(session, self.cwd))
  ignore(cwd)
  session = self.append_session_message(
    session, "user", "command", request_text,
  )
  let candidate = self.job_app.plan_proposal(request_text)
  let preview_text = @job.render_job_plan_preview_for_chat(
    @job.plan_preview_from_proposal(candidate),
  )
  session = self.append_session_message(
    SessionEntry::{
      ..session,
      plan_mode: Some(PlanModeState::{
        request_text,
        notes: [],
        latest_candidate: candidate,
        updated_at: current_time_ms(),
      }),
      linked_proposal_id: None,
      linked_run_id: None,
    },
    "assistant",
    "plan_preview",
    preview_text,
  )
  self.save_session_detail(session_key, session)
  self.write_json(w, {
    "session": self.cowork_session_detail(session_key, session).to_json(),
  })
}

///|
async fn Gateway::handle_cowork_preview(
  self : Gateway,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
  session_key : String,
) -> Unit {
  let params : CoworkPlanParams = decode_request_body(
    r, "cowork preview params",
  )
  let mut session = match self.sessions.get(session_key) {
    Some(entry) => entry
    None =>
      raise json_error(404, "NotFound", {
        "error": {
          "code": "session_not_found",
          "message": "Cowork session not found: \{session_key}",
        },
      })
  }
  let state = match session.plan_mode {
    Some(state) => state
    None =>
      raise json_error(409, "Conflict", {
        "error": {
          "code": "plan_mode_inactive",
          "message": "No active plan mode for this session",
        },
      })
  }
  let guidance = params.guidance.unwrap_or("").trim().to_owned()
  let next_state = if guidance.is_blank() {
    state
  } else {
    let notes = [..state.notes, guidance]
    let candidate = self.job_app.plan_proposal(
      planning_request_text(state.request_text, notes),
    )
    let candidate = @job.promote_plan_candidate(
      candidate,
      "plan-preview",
      state.request_text,
      current_time_ms(),
    )
    session = self.append_session_message(session, "user", "command", guidance)
    PlanModeState::{
      request_text: state.request_text,
      notes,
      latest_candidate: candidate,
      updated_at: current_time_ms(),
    }
  }
  let preview_text = @job.render_job_plan_preview_for_chat(
    @job.plan_preview_from_proposal(next_state.latest_candidate),
  )
  session = self.append_session_message(
    SessionEntry::{ ..session, plan_mode: Some(next_state) },
    "assistant",
    "plan_preview",
    preview_text,
  )
  self.save_session_detail(session_key, session)
  self.write_json(w, {
    "session": self.cowork_session_detail(session_key, session).to_json(),
  })
}

///|
async fn Gateway::handle_cowork_promote(
  self : Gateway,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
  session_key : String,
) -> Unit {
  let params : CoworkPlanParams = decode_request_body(
    r, "cowork promote params",
  )
  let mut session = match self.sessions.get(session_key) {
    Some(entry) => entry
    None =>
      raise json_error(404, "NotFound", {
        "error": {
          "code": "session_not_found",
          "message": "Cowork session not found: \{session_key}",
        },
      })
  }
  let state = match session.plan_mode {
    Some(state) => state
    None =>
      raise json_error(409, "Conflict", {
        "error": {
          "code": "plan_mode_inactive",
          "message": "No active plan mode for this session",
        },
      })
  }
  let guidance = params.guidance.unwrap_or("").trim().to_owned()
  let promoted_state = if guidance.is_blank() {
    state
  } else {
    let notes = [..state.notes, guidance]
    let candidate = self.job_app.plan_proposal(
      planning_request_text(state.request_text, notes),
    )
    let candidate = @job.promote_plan_candidate(
      candidate,
      "plan-preview",
      state.request_text,
      current_time_ms(),
    )
    session = self.append_session_message(session, "user", "command", guidance)
    PlanModeState::{
      request_text: state.request_text,
      notes,
      latest_candidate: candidate,
      updated_at: current_time_ms(),
    }
  }
  let proposal_id = @job.human_readable_proposal_id(
    promoted_state.request_text,
    current_time_ms(),
    self.job_app.next_id(),
  )
  let proposal = @job.promote_plan_candidate(
    promoted_state.latest_candidate,
    proposal_id,
    promoted_state.request_text,
    current_time_ms(),
  )
  let proposal_message = @job.render_job_proposal_for_chat(proposal)
  let message_id = self.uuid.v4().to_string()
  @job.save_presented_job_proposal(
    self.job_runtime().store(),
    proposal,
    message_id,
  )
  session = {
    ..session,
    updated_at: current_time_ms(),
    plan_mode: None,
    linked_proposal_id: Some(proposal.id),
    linked_run_id: None,
    messages: [
      ..session.messages,
      SessionMessage::{
        id: message_id,
        role: "assistant",
        kind: "proposal",
        content: proposal_message,
        timestamp: current_time_ms(),
        metadata: { "proposal_id": proposal.id },
      },
    ],
  }
  self.save_session_detail(session_key, session)
  self.write_json(w, {
    "session": self.cowork_session_detail(session_key, session).to_json(),
  })
}

///|
async fn Gateway::handle_cowork_confirm_proposal(
  self : Gateway,
  _r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
  session_key : String,
  proposal_id : String,
) -> Unit {
  let mut session = match self.sessions.get(session_key) {
    Some(entry) => entry
    None =>
      raise json_error(404, "NotFound", {
        "error": {
          "code": "session_not_found",
          "message": "Cowork session not found: \{session_key}",
        },
      })
  }
  let proposal = match
    self.job_runtime().store().get_job_proposal(proposal_id) {
    Some(proposal) => proposal
    None =>
      raise json_error(404, "NotFound", {
        "error": {
          "code": "proposal_not_found",
          "message": "Proposal not found: \{proposal_id}",
        },
      })
  }
  let confirmed = match
    self.job_app.confirm_proposal(proposal, proposal_id, async fn(
      job_id,
      initial_input,
    ) {
      self.trigger_job_definition(job_id, initial_input~)
    }) {
    Ok(confirmed) => confirmed
    Err(error) =>
      raise json_error(409, "Conflict", {
        "error": { "code": "proposal_confirm_failed", "message": error },
      })
  }
  let content = @job.render_confirmed_job_reply(
    proposal_id,
    @job.definition_display_title(confirmed.compilation.definition),
    @job.format_job_timestamp(confirmed.compilation.definition.created_at),
    confirmed.compilation.definition.id,
    confirmed.run.id,
    confirmed.compilation.family,
  )
  session = self.append_session_message(
    SessionEntry::{
      ..session,
      linked_proposal_id: Some(proposal_id),
      linked_run_id: Some(confirmed.run.id),
    },
    "assistant",
    "run_event",
    content,
    metadata={
      "proposal_id": proposal_id,
      "run_id": confirmed.run.id,
      "job_id": confirmed.compilation.definition.id,
    },
  )
  self.save_session_detail(session_key, session)
  self.write_json(w, {
    "session": self.cowork_session_detail(session_key, session).to_json(),
  })
}

///|
async fn Gateway::handle_cowork_resume_run(
  self : Gateway,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
  session_key : String,
  run_id : String,
) -> Unit {
  let params : CoworkResumeParams = decode_request_body(
    r, "cowork resume params",
  )
  let mut session = match self.sessions.get(session_key) {
    Some(entry) => entry
    None =>
      raise json_error(404, "NotFound", {
        "error": {
          "code": "session_not_found",
          "message": "Cowork session not found: \{session_key}",
        },
      })
  }
  let run = match self.job_runtime().store().get_run(run_id) {
    Some(run) => run
    None =>
      raise json_error(404, "NotFound", {
        "error": {
          "code": "run_not_found",
          "message": "Run not found: \{run_id}",
        },
      })
  }
  guard run.status is @job.RunStatus::WaitingForInput else {
    raise json_error(409, "Conflict", {
      "error": {
        "code": "run_not_waiting",
        "message": "Run is not waiting for input: \{run_id}",
      },
    })
  }
  let definition = match self.job_runtime().store().get_definition(run.job_id) {
    Some(definition) => definition
    None =>
      raise json_error(404, "NotFound", {
        "error": {
          "code": "job_not_found",
          "message": "Job definition not found: \{run.job_id}",
        },
      })
  }
  let resume_content = params.content.trim().to_owned()
  if resume_content.is_blank() {
    raise json_error(400, "BadRequest", {
      "error": {
        "code": "missing_resume_content",
        "message": "Resume content is required",
      },
    })
  }
  let merged_input = @job.merge_initial_input_for_resume(
    self.definition_initial_input(definition.id),
    { "resume_content": resume_content },
  )
  seed_resume_notification_cursor(
    self.job_app.state(),
    run.id,
    self.job_runtime().store().list_run_events(run.id).length(),
    current_time_ms(),
  )
  self.launch_job_run(run.id, initial_input=Some(merged_input))
  session = self.append_session_message(
    session,
    "user",
    "resume",
    resume_content,
    metadata={ "run_id": run.id },
  )
  session = self.append_session_message(
    session,
    "assistant",
    "run_event",
    "Resumed waiting run `\{run.id}` for job `\{definition.id}`.",
    metadata={ "run_id": run.id, "job_id": definition.id },
  )
  self.save_session_detail(session_key, session)
  self.write_json(w, {
    "session": self.cowork_session_detail(session_key, session).to_json(),
  })
}
