///|
fn Gateway::job_notification_target(
  self : Gateway,
  definition : @job.JobDefinition,
) -> @job.JobNotifyTarget? {
  @job.resolve_job_notify_target(self.job_runtime().store(), definition)
}

///|
fn Gateway::job_reply_message(
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
async fn Gateway::save_job_notification_preference(
  self : Gateway,
  channel_id : String,
  account_id : String,
  recipient : String,
  thread_id : String?,
  verbosity : @job.NotificationVerbosity,
  heartbeat_interval_ms? : Int? = None,
  warn_after_ms? : Int? = None,
) -> Unit {
  @job.save_job_notification_preference(
    self.job_runtime().store(),
    channel_id,
    account_id,
    recipient,
    thread_id,
    verbosity,
    current_time_ms(),
    heartbeat_interval_ms~,
    warn_after_ms~,
  )
}

///|
async fn Gateway::save_presented_job_proposal(
  self : Gateway,
  proposal : @job.JobProposal,
  reply : @channel.Message,
) -> Unit {
  @job.save_presented_job_proposal(
    self.job_runtime().store(),
    proposal,
    reply.id,
  )
}

///|
async fn Gateway::send_job_notification(
  self : Gateway,
  target : @job.JobNotifyTarget,
  content : String,
) -> Unit {
  let message = @channel.Message::{
    id: self.uuid.v4().to_string(),
    channel: target.channel_id,
    from: target.account_id,
    to: target.recipient,
    content,
    content_type: "text",
    timestamp: current_time_ms(),
    thread_id: target.thread_id,
    reply_to: None,
    attachments: [],
  }
  let result = try? self.channel_manager.send_message(
    target.channel_id,
    target.recipient,
    message,
    Some(target.account_id),
  )
  match result {
    Ok(_) => ()
    Err(error) => self.logger.warn("Failed to send job notification: \{error}")
  }
}

///|
fn Gateway::handle_jobs_command(
  self : Gateway,
  channel_id : String,
  account_id : String,
  message : @channel.Message,
) -> @channel.Message {
  self.job_reply_message(
    channel_id,
    account_id,
    message,
    @job.render_jobs_command_reply(
      self.job_runtime().store(),
      self.active_job_runs(),
    ),
  )
}

///|
fn channel_memory_query(
  channel_id : String,
  account_id : String,
  recipient : String,
  thread_id : String?,
) -> @job.MemoryQuery {
  @job.MemoryQuery::new(
    channel_id=Some(channel_id),
    account_id=Some(account_id),
    recipient=Some(recipient),
    thread_id~,
    status=Some(@job.MemoryStatus::Active),
  )
}

///|
async fn Gateway::handle_job_stop_command(
  self : Gateway,
  channel_id : String,
  account_id : String,
  message : @channel.Message,
  args : String,
  force? : Bool = false,
) -> @channel.Message {
  let trimmed = args.trim().to_string()
  guard !trimmed.is_blank() else {
    return self.job_reply_message(
      channel_id,
      account_id,
      message,
      @job.render_job_stop_usage(force),
    )
  }
  if force {
    let scope_key = @security.approval_scope_key(
      channel_id,
      account_id,
      message.to,
      message.thread_id,
    )
    let approved = self
      .security_runtime()
      .consume_approval("job.force_stop", trimmed, scope_key)
    if !approved {
      let pending = self
        .security_runtime()
        .matching_pending_approval("job.force_stop", trimmed, scope_key)
      let record = match pending {
        Some(record) => record
        None =>
          self
          .security_runtime()
          .request_approval(
            self.uuid.v4().to_string(),
            "job.force_stop",
            trimmed,
            scope_key,
            current_time_ms(),
          )
      }
      return self.job_reply_message(
        channel_id,
        account_id,
        message,
        @security.render_pending_approval(record),
      )
    }
  }
  match
    @job.request_job_stop(
      self.job_runtime().store(),
      trimmed,
      async fn(job_id, force) { self.cancel_job_definition_run(job_id, force~) },
      force~,
      active_run_id=self.job_runtime().active_run_id(trimmed),
    ) {
    Ok(content) =>
      self.job_reply_message(channel_id, account_id, message, content)
    Err(error) => self.job_reply_message(channel_id, account_id, message, error)
  }
}

///|
async fn Gateway::handle_remember_command(
  self : Gateway,
  channel_id : String,
  account_id : String,
  message : @channel.Message,
  args : String,
) -> @channel.Message {
  let content = args.trim().to_string()
  guard !content.is_blank() else {
    return self.job_reply_message(
      channel_id,
      account_id,
      message,
      @job.render_remember_usage(),
    )
  }
  let preview_len = if content.length() < 48 { content.length() } else { 48 }
  let memory = @job.MemoryService::new(store=self.job_runtime().store()).remember(
    @job.MemoryWriteRequest::new(
      kind="note",
      content~,
      title=Some(content[:preview_len].trim().to_string()),
      tags=["chat", "remember"],
      scope=[
        "channel:\{channel_id}",
        "channel:\{channel_id}:account:\{account_id}",
        "recipient:\{message.to}",
      ],
      workspace=Some(self.cwd),
      channel_id=Some(channel_id),
      account_id=Some(account_id),
      recipient=Some(message.to),
      thread_id=message.thread_id,
    ),
    self.uuid.v4().to_string(),
    current_time_ms(),
  )
  self.job_reply_message(
    channel_id,
    account_id,
    message,
    @job.render_memory_saved_reply(memory),
  )
}

///|
fn Gateway::handle_memories_command(
  self : Gateway,
  channel_id : String,
  account_id : String,
  message : @channel.Message,
) -> @channel.Message {
  let memories = @job.MemoryService::new(store=self.job_runtime().store()).list(
    query=channel_memory_query(
      channel_id,
      account_id,
      message.to,
      message.thread_id,
    ),
  )
  self.job_reply_message(
    channel_id,
    account_id,
    message,
    @job.render_memories_reply(memories),
  )
}

///|
fn Gateway::handle_memory_search_command(
  self : Gateway,
  channel_id : String,
  account_id : String,
  message : @channel.Message,
  args : String,
) -> @channel.Message {
  let question = args.trim().to_string()
  guard !question.is_blank() else {
    return self.job_reply_message(
      channel_id,
      account_id,
      message,
      @job.render_memory_search_usage(),
    )
  }
  let hits = @job.MemoryService::new(store=self.job_runtime().store()).search(
    question,
    query=channel_memory_query(
      channel_id,
      account_id,
      message.to,
      message.thread_id,
    ),
    max_hits=5,
  )
  self.job_reply_message(
    channel_id,
    account_id,
    message,
    @job.render_memory_search_reply(question, hits),
  )
}

///|
async fn Gateway::maybe_notify_active_jobs(self : Gateway) -> Unit {
  let now_ms = current_time_ms()
  for run in self.active_job_runs() {
    let definition = match
      self.job_runtime().store().get_definition(run.job_id) {
      Some(definition) => definition
      None => continue
    }
    let target = match self.job_notification_target(definition) {
      Some(target) => target
      None => continue
    }
    if target.verbosity is @job.NotificationVerbosity::Off {
      continue
    }
    let events = self.job_runtime().store().list_run_events(run.id)
    let decision = @job.decide_active_job_notifications(
      definition.id,
      run,
      events,
      target,
      self.job_app.state().notification_runtime_state(run.id),
      now_ms,
    )
    for content in decision.messages {
      if content == "Job is still running" || content == "Job heartbeat" {
        self.send_job_notification(
          target,
          @job.render_status_text(
            self.job_runtime().store(),
            definition,
            run,
            content,
            now_ms,
          ),
        )
      } else {
        self.send_job_notification(target, content)
      }
    }
    self.job_app
    .state()
    .set_notification_runtime_state(run.id, decision.next_state)
  }
}

///|
async fn Gateway::handle_plan_job_command(
  self : Gateway,
  channel_id : String,
  account_id : String,
  message : @channel.Message,
  request_text : String,
) -> @channel.Message {
  guard !request_text.is_blank() else {
    return self.job_reply_message(
      channel_id, account_id, message, "Usage: /plan-job <job description>",
    )
  }
  let proposal = self.job_app.plan_proposal(
    request_text,
    channel_id=Some(channel_id),
    account_id=Some(account_id),
    recipient=Some(message.to),
    thread_id=message.thread_id,
  )
  self.save_job_notification_preference(
    channel_id,
    account_id,
    message.to,
    message.thread_id,
    @job.NotificationVerbosity::Normal,
  )
  let reply = self.job_reply_message(
    channel_id,
    account_id,
    message,
    @job.render_job_proposal_for_chat(proposal),
  )
  self.save_presented_job_proposal(proposal, reply)
  reply
}

///|
fn Gateway::resolve_target_proposal(
  self : Gateway,
  message : @channel.Message,
  proposal_id : String,
) -> @job.JobProposal? {
  @job.resolve_target_proposal(
    self.job_runtime().store(),
    proposal_id,
    message.reply_to,
  )
}

///|
async fn Gateway::handle_confirm_job_command(
  self : Gateway,
  channel_id : String,
  account_id : String,
  message : @channel.Message,
  proposal_id : String,
) -> @channel.Message {
  let proposal = match self.resolve_target_proposal(message, proposal_id) {
    Some(proposal) => proposal
    None =>
      return self.job_reply_message(
        channel_id,
        account_id,
        message,
        @job.render_unknown_proposal_message("confirm"),
      )
  }
  let confirmed = match
    self.job_app.confirm_proposal(proposal, proposal_id, async fn(job_id) {
      self.trigger_job_definition(job_id)
    }) {
    Ok(confirmed) => confirmed
    Err(error) =>
      return self.job_reply_message(
        channel_id,
        account_id,
        message,
        if error.has_prefix("Proposal ") {
          error
        } else {
          @job.render_confirm_proposal_failure(proposal_id, error)
        },
      )
  }
  self.job_reply_message(
    channel_id,
    account_id,
    message,
    @job.render_confirmed_job_reply(
      proposal_id,
      @job.definition_display_title(confirmed.compilation.definition),
      @job.format_job_timestamp(confirmed.compilation.definition.created_at),
      confirmed.compilation.definition.id,
      confirmed.run.id,
      confirmed.compilation.family,
    ),
  )
}

///|
async fn Gateway::handle_reject_job_command(
  self : Gateway,
  channel_id : String,
  account_id : String,
  message : @channel.Message,
  proposal_id : String,
) -> @channel.Message {
  let proposal = match self.resolve_target_proposal(message, proposal_id) {
    Some(proposal) => proposal
    None =>
      return self.job_reply_message(
        channel_id,
        account_id,
        message,
        @job.render_unknown_proposal_message("reject"),
      )
  }
  self.job_app.reject_proposal(proposal)
  self.job_reply_message(
    channel_id,
    account_id,
    message,
    @job.render_rejected_job_reply(proposal_id),
  )
}

///|
async fn Gateway::handle_revise_job_command(
  self : Gateway,
  channel_id : String,
  account_id : String,
  message : @channel.Message,
  args : String,
) -> @channel.Message {
  let (proposal_id, guidance) = match @job.parse_revise_args(args) {
    Some(parts) => parts
    None =>
      if message.reply_to is Some(_) && !args.trim().to_string().is_blank() {
        ("", args.trim().to_string())
      } else {
        return self.job_reply_message(
          channel_id,
          account_id,
          message,
          @job.render_revise_usage(message.reply_to is Some(_)),
        )
      }
  }
  let proposal = match self.resolve_target_proposal(message, proposal_id) {
    Some(proposal) => proposal
    None =>
      return self.job_reply_message(
        channel_id,
        account_id,
        message,
        @job.render_unknown_proposal_message("revise"),
      )
  }
  let revised = match
    self.job_app.revise_draft_proposal(proposal, proposal_id, guidance) {
    Ok(revised) => revised
    Err(error) =>
      return self.job_reply_message(channel_id, account_id, message, error)
  }
  let reply = self.job_reply_message(
    channel_id,
    account_id,
    message,
    @job.render_job_proposal_for_chat(revised),
  )
  self.save_presented_job_proposal(revised, reply)
  reply
}

///|
async fn Gateway::handle_job_status_command(
  self : Gateway,
  channel_id : String,
  account_id : String,
  message : @channel.Message,
  job_or_run_id : String,
) -> @channel.Message {
  let trimmed = job_or_run_id.trim().to_string()
  let content = @job.render_job_status_command_reply(
    self.job_runtime().store(),
    trimmed,
    current_time_ms(),
    "Current job status",
    active_run_id=self.job_runtime().active_run_id(trimmed),
  )
  self.job_reply_message(
    channel_id,
    account_id,
    message,
    content.unwrap_or(@job.render_unknown_job_or_run_message(trimmed)),
  )
}

///|
async fn Gateway::handle_job_workspace_command(
  self : Gateway,
  channel_id : String,
  account_id : String,
  message : @channel.Message,
  job_or_run_id : String,
) -> @channel.Message {
  let trimmed = job_or_run_id.trim().to_string()
  guard !trimmed.is_blank() else {
    return self.job_reply_message(
      channel_id,
      account_id,
      message,
      @job.render_job_workspace_usage(),
    )
  }
  let content = @job.render_job_workspace_command_reply(
    self.job_runtime().store(),
    trimmed,
    active_run_id=self.job_runtime().active_run_id(trimmed),
  )
  self.job_reply_message(
    channel_id,
    account_id,
    message,
    content.unwrap_or(@job.render_unknown_job_or_run_message(trimmed)),
  )
}

///|
async fn Gateway::handle_job_notify_command(
  self : Gateway,
  channel_id : String,
  account_id : String,
  message : @channel.Message,
  args : String,
) -> @channel.Message {
  let verbosity = match @job.parse_notification_verbosity(args) {
    Some(verbosity) => verbosity
    None =>
      return self.job_reply_message(
        channel_id,
        account_id,
        message,
        @job.render_job_notify_usage(),
      )
  }
  self.save_job_notification_preference(
    channel_id,
    account_id,
    message.to,
    message.thread_id,
    verbosity,
  )
  self.job_reply_message(
    channel_id,
    account_id,
    message,
    @job.render_job_notify_updated(verbosity),
  )
}

///|
async fn Gateway::handle_job_chat_command(
  self : Gateway,
  channel_id : String,
  account_id : String,
  message : @channel.Message,
) -> @channel.Message? {
  let trimmed = message.content.trim().to_string()
  let action = @job.parse_job_chat_action(trimmed, message.reply_to is Some(_))
  if action is Some(_) && !self.security_runtime().allows_native_commands(true) {
    return Some(
      self.job_reply_message(
        channel_id,
        account_id,
        message,
        @security.render_native_commands_disabled(),
      ),
    )
  }
  @job.dispatch_job_chat_action(
    action,
    async fn(args) {
      self.handle_plan_job_command(channel_id, account_id, message, args)
    },
    async fn(args) {
      self.handle_confirm_job_command(channel_id, account_id, message, args)
    },
    async fn(args) {
      self.handle_reject_job_command(channel_id, account_id, message, args)
    },
    async fn(args) {
      self.handle_revise_job_command(channel_id, account_id, message, args)
    },
    async fn(args) {
      self.handle_job_status_command(channel_id, account_id, message, args)
    },
    async fn(args) {
      self.handle_job_workspace_command(channel_id, account_id, message, args)
    },
    fn() { self.handle_jobs_command(channel_id, account_id, message) },
    async fn(args, force) {
      self.handle_job_stop_command(
        channel_id,
        account_id,
        message,
        args,
        force~,
      )
    },
    async fn(args) {
      self.handle_job_notify_command(channel_id, account_id, message, args)
    },
    async fn(args) {
      self.handle_remember_command(channel_id, account_id, message, args)
    },
    fn() { self.handle_memories_command(channel_id, account_id, message) },
    fn(args) {
      self.handle_memory_search_command(channel_id, account_id, message, args)
    },
  )
}
