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
      queue.send(@event.Cancelled)
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
async fn Gateway::store_channel_session(
  self : Gateway,
  session_key : String,
  conversation_id : String,
  channel_id : String,
  cwd : String,
  model_name : String,
) -> Unit {
  self.sessions.save_entry(session_key, SessionEntry::{
    session_id: conversation_id,
    updated_at: current_time_ms(),
    channel: Some(channel_id),
    model_override: Some(model_name),
    provider_override: None,
    cwd: Some(cwd),
  })
}

///|
async fn Gateway::resume_or_create_channel_agent(
  self : Gateway,
  model : @model.Model,
  session : SessionEntry?,
  cwd : String,
  user_message : String,
  command_approval_scope : String,
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
            command_approval_scope~,
          )
      }
      @moonclaw.Moonclaw::resume_(
        logger=self.logger,
        model~,
        home=self.home,
        id,
        user_message~,
        command_approval_scope~,
      )
    }
    None =>
      @moonclaw.Moonclaw::new(
        logger=self.logger,
        model~,
        home=self.home,
        cwd~,
        user_message~,
        command_approval_scope~,
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
  @channel.Message::{
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
    Some(@acp.AcpChatAction::Targets) =>
      Some(
        self.channel_reply_message(
          channel_id,
          account_id,
          message,
          @acp.render_acp_targets(self.acp_runtime().list_targets()),
        ),
      )
    Some(@acp.AcpChatAction::Status) =>
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
    Some(@acp.AcpChatAction::Attach(args)) => {
      let target_id = args.trim().to_string()
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
    Some(@acp.AcpChatAction::Detach(args)) => {
      let sessions = self.acp_runtime().list_sessions_for_key(session_key)
      let trimmed = args.trim().to_string()
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
    Some(@acp.AcpChatAction::Run(args)) => {
      let content = args.trim().to_string()
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
    Some(@security.SecurityChatAction::Pair) => {
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
    Some(@security.SecurityChatAction::PairStatus) =>
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
    Some(@security.SecurityChatAction::RevokePair) =>
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
    Some(@security.SecurityChatAction::Approve(token)) =>
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
    Some(@security.SecurityChatAction::Approvals) =>
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
impl @channel.MessageHandler for Gateway with handle_message(
  self : Gateway,
  channel_id : String,
  account_id : String,
  message : @channel.Message,
) -> @channel.Message raise {
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
  let model_name = match session {
    Some(entry) => entry.model_override
    None => None
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
    self.security_scope_key(channel_id, account_id, message),
  )
  self.register_active_channel_session(
    session_key,
    moonclaw.agent.external_events(),
  )
  defer self.clear_active_channel_session(session_key)
  moonclaw.agent.event_target.add_listener(event => {
    match event.desc {
      AssistantMessage(content, ..) if !content.is_blank() =>
        reply_text = content
      _ => ()
    }
  })
  moonclaw.start()

  let conversation_id = moonclaw.agent.id().to_string()
  self.store_channel_session(
    session_key,
    conversation_id,
    channel_id,
    cwd,
    model.name,
  )
  moonclaw.close()

  if reply_text.is_blank() {
    fail("Agent completed without producing a channel response")
  }

  @channel.Message::{
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
impl @channel.MessageHandler for Gateway with handle_event(
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
