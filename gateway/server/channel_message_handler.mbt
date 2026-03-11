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
impl @channel.MessageHandler for Gateway with handle_message(
  self : Gateway,
  channel_id : String,
  account_id : String,
  message : @channel.Message,
) -> @channel.Message raise {
  let session_key = message_session_key(channel_id, account_id, message)
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

}
