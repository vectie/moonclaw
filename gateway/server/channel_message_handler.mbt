///|
fn Gateway::register_active_channel_session(
  self : Gateway,
  session_key : String,
  queue : @event.ExternalEventQueue,
) -> Unit {
  self.active_channel_sessions[session_key] = queue
}

///|
fn Gateway::clear_active_channel_session(
  self : Gateway,
  session_key : String,
) -> Unit {
  self.active_channel_sessions.remove(session_key) |> ignore()
}

///|
fn Gateway::cancel_active_channel_session(
  self : Gateway,
  session_key : String,
) -> Bool {
  match self.active_channel_sessions.get(session_key) {
    Some(queue) => {
      queue.send(Cancelled)
      true
    }
    None => false
  }
}

///|
async fn Gateway::force_cancel_active_channel_session(
  self : Gateway,
  session_key : String,
) -> Bool {
  let cancelled = self.cancel_active_channel_session(session_key)
  ignore(self.sessions.reset_and_save(session_key))
  self.clear_active_channel_session(session_key)
  cancelled
}

///|
fn configured_primary_model_from_json(json : Json?) -> String? {
  match json {
    Some(Object(root)) =>
      match root.get("agents") {
        Some(Object(agents)) =>
          match agents.get("defaults") {
            Some(Object(defaults)) =>
              match defaults.get("model") {
                Some(Object(model)) =>
                  match model.get("primary") {
                    Some(String(primary)) if !primary.trim().is_empty() =>
                      Some(primary.trim().to_owned())
                    _ => None
                  }
                _ => None
              }
            _ => None
          }
        _ => None
      }
    _ => None
  }
}

///|
fn moonclaw_config_path_candidates(
  cwd : String,
  home : String,
) -> Array[String] {
  let candidates = [
    @moonsuite.product_artifact_for_workspace_root(
      cwd, "moonclaw", "moonclaw.json",
    ),
  ]
  if cwd != home {
    candidates.push(
      @moonsuite.product_artifact_for_workspace_root(
        home, "moonclaw", "moonclaw.json",
      ),
    )
  }
  candidates
}

///|
async fn Gateway::configured_primary_model_for_cwd(
  self : Gateway,
  cwd : String,
) -> String? {
  for path in moonclaw_config_path_candidates(cwd, self.home) {
    let text = @fsx.read_file(path) catch { _ => continue }
    let json = @json.parse(text) catch { _ => continue }
    if configured_primary_model_from_json(Some(json)) is Some(primary) {
      return Some(primary)
    }
  }
  None
}

///|
fn channel_model_provider_override(model : @model.Model) -> String? {
  match model.model_type {
    SaaS(CodexOAuth) => Some("codex")
    SaaS(Copilot) => Some("copilot")
    SaaS(Qwen) => Some("qwen")
    SaaS(Kimi) => Some("kimi")
    SaaS(KimiCoding) => Some("kimi-coding")
    _ => None
  }
}

///|
fn channel_model_session_name(model : @model.Model) -> String {
  model.selector()
}

///|
fn resolve_channel_model_override(
  model_override : String?,
  provider_override : String?,
  configured_primary : String?,
) -> String? {
  ignore(provider_override)
  match model_override {
    Some(model_name) if model_name.contains("/") =>
      Some(model_name.trim().to_owned())
    Some(_) => configured_primary
    None => configured_primary
  }
}

///|
async fn Gateway::store_channel_session(
  self : Gateway,
  session_key : String,
  conversation_id : String,
  channel_id : String,
  cwd : String,
  model : @model.Model,
) -> Unit {
  self.sessions.save_entry(session_key, {
    session_id: conversation_id,
    title: self.sessions
    .get(session_key)
    .map(fn(entry) { entry.title })
    .unwrap_or(None),
    updated_at: current_time_ms(),
    channel: Some(channel_id),
    model_override: Some(channel_model_session_name(model)),
    provider_override: channel_model_provider_override(model),
    cwd: Some(cwd),
    plan_mode: self.sessions
    .get(session_key)
    .map(fn(entry) { entry.plan_mode })
    .unwrap_or(None),
    messages: self.sessions
    .get(session_key)
    .map(fn(entry) { entry.messages })
    .unwrap_or([]),
    linked_proposal_id: self.sessions
    .get(session_key)
    .map(fn(entry) { entry.linked_proposal_id })
    .unwrap_or(None),
    linked_run_id: self.sessions
    .get(session_key)
    .map(fn(entry) { entry.linked_run_id })
    .unwrap_or(None),
  })
}

///|
async fn Gateway::resume_or_create_channel_agent(
  self : Gateway,
  model : @model.Model,
  session : SessionEntry?,
  cwd : String,
  user_message : String,
) -> @moonclaw.Moonclaw {
  match session {
    Some(entry) => {
      let id = @uuid.parse(entry.session_id) catch {
        _ =>
          return @moonclaw.Moonclaw::new(
            logger=self.logger,
            model~,
            home=self.home,
            cwd~,
            user_message~,
          )
      }
      @moonclaw.Moonclaw::resume_(
        logger=self.logger,
        model~,
        home=self.home,
        id,
        user_message~,
      )
    }
    None =>
      @moonclaw.Moonclaw::new(
        logger=self.logger,
        model~,
        home=self.home,
        cwd~,
        user_message~,
      )
  }
}

///|
fn Gateway::channel_reply_message(
  self : Gateway,
  channel_id : String,
  account_id : String,
  incoming : @channel.Message,
  content : String,
) -> @channel.Message {
  {
    id: self.uuid.v4().to_string(),
    channel: channel_id,
    from: account_id,
    to: incoming.to,
    content,
    content_type: "text",
    timestamp: current_time_ms(),
    thread_id: incoming.thread_id,
    reply_to: Some(incoming.id),
    attachments: [],
  }
}

///|
fn channel_model_debug_summary(
  requested_model : String?,
  model : @model.Model,
) -> String {
  let requested = requested_model.unwrap_or("auto")
  "requested=\{requested}; loaded=\{channel_model_session_name(model)}; provider=\{model.model_type}"
}

///|
fn thinking_status_text() -> String {
  "thinking"
}

///|
fn tool_status_text(tool_name : String) -> String {
  ignore(tool_name)
  "tool"
}

///|
fn drafting_status_text() -> String {
  "drafting"
}

///|
fn is_non_text_attachment_message(message : @channel.Message) -> Bool {
  if message.attachments.is_empty() {
    return false
  }
  match message.content_type {
    "file" | "media" | "image" | "audio" | "video" => true
    _ => false
  }
}

///|
async fn Gateway::send_channel_progress_message(
  self : Gateway,
  channel_id : String,
  account_id : String,
  incoming : @channel.Message,
  content : String,
) -> Unit {
  let message = @channel.Message::{
    ..self.channel_reply_message(channel_id, account_id, incoming, content),
    content_type: "progress",
  }
  match
    self.channel_manager.send_message(
      channel_id,
      message.to,
      message,
      Some(account_id),
    ) {
    Ok(_) => ()
    Err(error) =>
      self.logger.warn(
        "Failed to send channel progress message: \{channel_id} / \{account_id} / \{error}",
      )
  }
}

///|
fn Gateway::routable_acp_sessions(
  self : Gateway,
  session_key : String,
) -> Array[@acp.AcpSession] {
  let sessions = []
  for session in self.acp_runtime().list_sessions_for_key(session_key) {
    if session.status == "attached" || session.status == "running" {
      sessions.push(session)
    }
  }
  sessions
}

///|
fn acp_result_content(result : Json) -> String {
  match result {
    { "content": String(content), .. } if !content.is_blank() => content
    { "status": String(status), .. } =>
      "ACP run completed with status: \{status}"
    _ => "ACP run completed."
  }
}

///|
async fn Gateway::run_bound_acp_session(
  self : Gateway,
  session : @acp.AcpSession,
  message : String,
) -> Result[String, String] {
  let target = match self.acp_runtime().get_target(session.target_id) {
    Some(target) => target
    None => return Err("ACP target not found: \{session.target_id}")
  }
  let run_id = self.uuid.v4().to_string()
  let metadata = merged_acp_run_metadata(session, None)
  let launch = match
    @acp.prepare_launch_plan(
      target,
      session,
      @acp.new_run_request(message~, metadata?),
    ) {
    Ok(plan) => plan
    Err(error) => return Err(error)
  }
  let request = @acp.new_run_request(
    message~,
    run_id~,
    cwd=launch.cwd,
    model?=launch.model,
    idempotency_key=run_id,
    metadata?,
  )
  ignore(
    self
    .acp_runtime()
    .start_run(
      run_id,
      session,
      target,
      request.to_json(),
      launch.to_json(),
      current_time_ms(),
    ),
  )
  ignore(
    self
    .acp_runtime()
    .set_session_status(session.id, "running", current_time_ms()),
  )
  match self.execute_managed_acp_process(run_id, launch, request) {
    Ok(outcome) => {
      let now = current_time_ms()
      let result = outcome.result
      if outcome.status == "completed" {
        self.finalize_acp_session_after_run(session.id, "completed", now)
        ignore(
          self
          .acp_runtime()
          .finish_run(run_id, "completed", now, result=Some(result)),
        )
        return Ok(acp_result_content(result))
      }
      match outcome.error {
        Some(error) =>
          self.finalize_acp_session_after_run(
            session.id,
            outcome.status,
            now,
            error=Some(error),
          )
        None =>
          self.finalize_acp_session_after_run(session.id, outcome.status, now)
      }
      ignore(
        self
        .acp_runtime()
        .finish_run(
          run_id,
          outcome.status,
          now,
          result=Some(result),
          error=outcome.error,
        ),
      )
      if outcome.status == "cancelled" {
        Ok("ACP run cancelled.")
      } else {
        Err(outcome.error.unwrap_or("ACP backend failed"))
      }
    }
    Err(error) => {
      self.finalize_acp_session_after_run(
        session.id,
        "failed",
        current_time_ms(),
        error=Some(error),
      )
      ignore(
        self
        .acp_runtime()
        .finish_run(run_id, "failed", current_time_ms(), error=Some(error)),
      )
      Err(error)
    }
  }
}

///|
async fn Gateway::handle_acp_chat_command(
  self : Gateway,
  channel_id : String,
  account_id : String,
  message : @channel.Message,
) -> @channel.Message? {
  let action = @acp.parse_acp_chat_action(message.content)
  if action is Some(_) && !self.security_runtime().allows_native_commands(true) {
    return Some(
      self.channel_reply_message(
        channel_id,
        account_id,
        message,
        @security.render_native_commands_disabled(),
      ),
    )
  }
  let session_key = message_session_key(
    channel_id,
    account_id,
    message,
    dm_scope=self.security_runtime().session_dm_scope(),
  )
  match action {
    Some(Targets) =>
      Some(
        self.channel_reply_message(
          channel_id,
          account_id,
          message,
          @acp.render_acp_targets(self.acp_runtime().list_targets()),
        ),
      )
    Some(Status) =>
      Some(
        self.channel_reply_message(
          channel_id,
          account_id,
          message,
          @acp.render_acp_status(
            session_key,
            self.acp_runtime().list_sessions_for_key(session_key),
            self.acp_runtime().list_runs(),
          ),
        ),
      )
    Some(Attach(args)) => {
      let target_id = args.trim().to_owned()
      guard !target_id.is_blank() else {
        return Some(
          self.channel_reply_message(
            channel_id,
            account_id,
            message,
            @acp.render_acp_attach_usage(),
          ),
        )
      }
      let session = match
        self
        .acp_runtime()
        .open_session(
          self.uuid.v4().to_string(),
          target_id,
          session_key,
          current_time_ms(),
          metadata={
            "channel_id": channel_id,
            "account_id": account_id,
            "recipient": message.to,
            "thread_id": message.thread_id,
          },
        ) {
        Ok(session) => session
        Err(error) =>
          return Some(
            self.channel_reply_message(channel_id, account_id, message, error),
          )
      }
      Some(
        self.channel_reply_message(
          channel_id,
          account_id,
          message,
          @acp.render_acp_attached(session),
        ),
      )
    }
    Some(Detach(args)) => {
      let sessions = self.acp_runtime().list_sessions_for_key(session_key)
      let trimmed = args.trim().to_owned()
      let target_session = if trimmed.is_blank() {
        if sessions.length() != 1 {
          return Some(
            self.channel_reply_message(
              channel_id,
              account_id,
              message,
              if sessions.is_empty() {
                @acp.render_acp_no_session()
              } else {
                @acp.render_acp_ambiguous_sessions(sessions)
              },
            ),
          )
        }
        sessions[0]
      } else {
        let mut found = None
        for session in sessions {
          if session.id == trimmed {
            found = Some(session)
            break
          }
        }
        match found {
          Some(session) => session
          None =>
            return Some(
              self.channel_reply_message(
                channel_id,
                account_id,
                message,
                "ACP session not found for this chat: \{trimmed}",
              ),
            )
        }
      }
      let removed = match self.active_acp_run_for_session(target_session.id) {
        Some(run) =>
          match self.cancel_active_acp_run(run.id) {
            Err(error) =>
              return Some(
                self.channel_reply_message(
                  channel_id,
                  account_id,
                  message,
                  "Failed to detach ACP session: \{error}",
                ),
              )
            Ok(false) =>
              return Some(
                self.channel_reply_message(
                  channel_id,
                  account_id,
                  message,
                  "ACP session run is not active in this gateway process: \{run.id}",
                ),
              )
            Ok(true) => {
              let updated = match
                self
                .acp_runtime()
                .set_session_status(
                  target_session.id,
                  "detaching",
                  current_time_ms(),
                  last_error=Some("ACP session detach requested."),
                ) {
                Ok(updated) => updated
                Err(_) => target_session
              }
              ignore(
                self
                .acp_runtime()
                .finish_run(
                  run.id,
                  "cancelling",
                  current_time_ms(),
                  error=Some("ACP session detach requested."),
                ),
              )
              return Some(
                self.channel_reply_message(
                  channel_id,
                  account_id,
                  message,
                  "ACP session detach requested.\nSession: \{updated.id}\nRun: \{run.id}\nStatus: \{updated.status}",
                ),
              )
            }
          }
        None =>
          match self.acp_runtime().delete_session(target_session.id) {
            Some(session) => session
            None =>
              return Some(
                self.channel_reply_message(
                  channel_id,
                  account_id,
                  message,
                  "ACP session not found: \{target_session.id}",
                ),
              )
          }
      }
      Some(
        self.channel_reply_message(
          channel_id,
          account_id,
          message,
          @acp.render_acp_detached(removed),
        ),
      )
    }
    Some(Run(args)) => {
      let content = args.trim().to_owned()
      guard !content.is_blank() else {
        return Some(
          self.channel_reply_message(
            channel_id,
            account_id,
            message,
            @acp.render_acp_run_usage(),
          ),
        )
      }
      let sessions = self.routable_acp_sessions(session_key)
      guard !sessions.is_empty() else {
        return Some(
          self.channel_reply_message(
            channel_id,
            account_id,
            message,
            @acp.render_acp_no_session(),
          ),
        )
      }
      guard sessions.length() == 1 else {
        return Some(
          self.channel_reply_message(
            channel_id,
            account_id,
            message,
            @acp.render_acp_ambiguous_sessions(sessions),
          ),
        )
      }
      match self.run_bound_acp_session(sessions[0], content) {
        Ok(reply_text) =>
          Some(
            self.channel_reply_message(
              channel_id, account_id, message, reply_text,
            ),
          )
        Err(error) =>
          Some(
            self.channel_reply_message(
              channel_id,
              account_id,
              message,
              @acp.render_acp_run_failed(error),
            ),
          )
      }
    }
    None => None
  }
}

///|
fn configured_dm_policy(
  store : ChannelStateStore,
  channel_id : String,
  account_id : String,
) -> String {
  let state = match store.states.get(channel_id) {
    Some(state) => state
    None => return "open"
  }
  for account in state.accounts {
    if account.account_id != account_id {
      continue
    }
    match account.config {
      { "dm_policy": String(policy), .. } => return policy
      { "dmPolicy": String(policy), .. } => return policy
      _ => ()
    }
  }
  match state.config.accounts.get(account_id) {
    Some({ "dm_policy": String(policy), .. }) => policy
    Some({ "dmPolicy": String(policy), .. }) => policy
    _ => "open"
  }
}

///|
fn Gateway::configured_dm_policy(
  self : Gateway,
  channel_id : String,
  account_id : String,
) -> String {
  configured_dm_policy(self.channel_state, channel_id, account_id)
}

///|
fn Gateway::security_scope_key(
  _self : Gateway,
  channel_id : String,
  account_id : String,
  message : @channel.Message,
) -> String {
  @security.approval_scope_key(
    channel_id,
    account_id,
    message.to,
    message.thread_id,
  )
}

///|
async fn Gateway::handle_security_chat_command(
  self : Gateway,
  channel_id : String,
  account_id : String,
  message : @channel.Message,
) -> @channel.Message? {
  match @security.parse_security_chat_action(message.content) {
    Some(Pair) => {
      let record = self
        .security_runtime()
        .approve_pairing(channel_id, account_id, message.to, current_time_ms())
      Some(
        self.channel_reply_message(
          channel_id,
          account_id,
          message,
          "Pairing approved for \{record.channel_id}/\{record.account_id}/\{record.recipient}",
        ),
      )
    }
    Some(PairStatus) =>
      Some(
        self.channel_reply_message(
          channel_id,
          account_id,
          message,
          self
          .security_runtime()
          .pairing_status_text(channel_id, account_id, message.to),
        ),
      )
    Some(RevokePair) =>
      Some(
        self.channel_reply_message(
          channel_id,
          account_id,
          message,
          if self
            .security_runtime()
            .revoke_pairing(channel_id, account_id, message.to) {
            "Pairing revoked for \{channel_id}/\{account_id}/\{message.to}"
          } else {
            "No pairing found for \{channel_id}/\{account_id}/\{message.to}"
          },
        ),
      )
    Some(Approve(token)) =>
      Some(
        self.channel_reply_message(
          channel_id,
          account_id,
          message,
          match
            self.security_runtime().approve_token(token, current_time_ms()) {
            Some(record) => @security.render_approval_confirmed(record)
            None => @security.render_approval_not_found(token)
          },
        ),
      )
    Some(Approvals) =>
      Some(
        self.channel_reply_message(
          channel_id,
          account_id,
          message,
          @security.render_approvals(
            self
            .security_runtime()
            .list_pending_approvals(
              self.security_scope_key(channel_id, account_id, message),
            ),
          ),
        ),
      )
    None => None
  }
}

///|
impl @channel.MessageHandler for Gateway with fn handle_message(
  self : Gateway,
  channel_id : String,
  account_id : String,
  message : @channel.Message,
) -> @channel.Message raise {
  self.remember_thread_attachments(channel_id, account_id, message)
  if self.handle_security_chat_command(channel_id, account_id, message)
    is Some(reply) {
    return reply
  }
  let dm_policy = self.configured_dm_policy(channel_id, account_id)
  if dm_policy == "pairing" &&
    !self.security_runtime().is_paired(channel_id, account_id, message.to) {
    return self.channel_reply_message(
      channel_id,
      account_id,
      message,
      @security.render_pairing_required(dm_policy),
    )
  }
  if self.handle_job_chat_command(channel_id, account_id, message)
    is Some(reply) {
    return reply
  }
  let session_key = message_session_key(
    channel_id,
    account_id,
    message,
    dm_scope=self.security_runtime().session_dm_scope(),
  )
  if self.handle_acp_chat_command(channel_id, account_id, message)
    is Some(reply) {
    return reply
  }
  let acp_sessions = self.routable_acp_sessions(session_key)
  if acp_sessions.length() == 1 {
    match self.run_bound_acp_session(acp_sessions[0], message.content) {
      Ok(reply_text) =>
        return self.channel_reply_message(
          channel_id, account_id, message, reply_text,
        )
      Err(error) =>
        return self.channel_reply_message(
          channel_id,
          account_id,
          message,
          @acp.render_acp_run_failed(error),
        )
    }
  }
  let session = self.sessions.get(session_key)
  let cwd = match session {
    Some(entry) => entry.cwd.unwrap_or(self.cwd)
    None => self.cwd
  }
  let configured_primary_model = self.configured_primary_model_for_cwd(cwd)
  let model_name = match session {
    Some(entry) =>
      resolve_channel_model_override(
        entry.model_override,
        entry.provider_override,
        configured_primary_model,
      )
    None => configured_primary_model
  }
  if message.content.trim().to_owned().is_blank() &&
    message.attachments.is_empty() {
    return self.channel_reply_message(
      channel_id, account_id, message, "I could not parse any text from that message. Please resend it as plain text.",
    )
  }
  if is_non_text_attachment_message(message) {
    return self.channel_reply_message(
      channel_id, account_id, message, "Files saved for this thread. They are not sent to normal chat automatically. Use `/plan ...`, `/plan-job ...`, or `/e2e ...` to start a job flow with them.",
    )
  }
  if message.content.trim().to_owned().is_blank() &&
    !message.attachments.is_empty() {
    return self.channel_reply_message(
      channel_id, account_id, message, "Files saved for this thread. They are not sent to normal chat automatically. Use `/plan ...`, `/plan-job ...`, or `/e2e ...` to start a job flow with them.",
    )
  }
  guard @model.load(home=self.home, cwd~, name?=model_name) is Some(model) else {
    fail("No model available for channel reply")
  }

  let mut reply_text = ""
  let moonclaw = self.resume_or_create_channel_agent(
    model,
    session,
    cwd,
    message.content,
  )
  self.register_active_channel_session(
    session_key,
    moonclaw.agent.external_events(),
  )
  defer self.clear_active_channel_session(session_key)
  let mut last_progress_text = ""
  let mut saw_text_delta = false
  moonclaw.agent.event_target.add_listener(event => {
    match event.desc {
      PreConversation if channel_id == "feishu" => {
        let progress = thinking_status_text()
        if last_progress_text != progress {
          last_progress_text = progress
          self.send_channel_progress_message(
            channel_id, account_id, message, progress,
          )
        }
      }
      PreToolCall(tool_call) if channel_id == "feishu" => {
        let progress = tool_status_text(tool_call.name)
        if last_progress_text != progress {
          last_progress_text = progress
          self.send_channel_progress_message(
            channel_id, account_id, message, progress,
          )
        }
      }
      AssistantMessageDelta(delta) if channel_id == "feishu" &&
        !delta.is_blank() &&
        !saw_text_delta => {
        saw_text_delta = true
        let progress = drafting_status_text()
        if last_progress_text != progress {
          last_progress_text = progress
          self.send_channel_progress_message(
            channel_id, account_id, message, progress,
          )
        }
      }
      AssistantMessageDelta(delta) if !delta.is_blank() =>
        reply_text = reply_text + delta
      AssistantMessage(content, ..) if !content.is_blank() =>
        reply_text = content
      _ => ()
    }
  })
  moonclaw.start() catch {
    error =>
      return self.channel_reply_message(
        channel_id,
        account_id,
        message,
        "Channel chat failed: \{error}\nModel: \{channel_model_debug_summary(model_name, model)}",
      )
  }

  let conversation_id = moonclaw.agent.id().to_string()
  self.store_channel_session(
    session_key, conversation_id, channel_id, cwd, model,
  )
  moonclaw.close()

  if reply_text.is_blank() {
    return self.channel_reply_message(
      channel_id, account_id, message, "Channel chat completed without a text reply.",
    )
  }

  {
    id: self.uuid.v4().to_string(),
    channel: channel_id,
    from: account_id,
    to: message.to,
    content: reply_text,
    content_type: "text",
    timestamp: current_time_ms(),
    thread_id: message.thread_id,
    reply_to: Some(message.id),
    attachments: [],
  }
}

///|
impl @channel.MessageHandler for Gateway with fn handle_event(
  self : Gateway,
  channel_id : String,
  account_id : String,
  event : @channel.ChannelEvent,
) -> Unit {
  match event.event_type {
    "cancel" => {
      let chat_id = match event.payload {
        { "chat_id": String(chat_id), .. } => chat_id
        _ => return
      }
      let thread_id = match event.payload {
        { "thread_id": String(thread_id), .. } => Some(thread_id)
        _ => None
      }
      let session_key = channel_session_key(
        channel_id,
        account_id,
        chat_id,
        thread_id,
        dm_scope=self.security_runtime().session_dm_scope(),
      )
      ignore(self.cancel_active_channel_session(session_key))
    }
    "force_cancel" => {
      let chat_id = match event.payload {
        { "chat_id": String(chat_id), .. } => chat_id
        _ => return
      }
      let thread_id = match event.payload {
        { "thread_id": String(thread_id), .. } => Some(thread_id)
        _ => None
      }
      let session_key = channel_session_key(
        channel_id,
        account_id,
        chat_id,
        thread_id,
        dm_scope=self.security_runtime().session_dm_scope(),
      )
      ignore(self.force_cancel_active_channel_session(session_key))
    }
    _ => ()
  }
}
