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
