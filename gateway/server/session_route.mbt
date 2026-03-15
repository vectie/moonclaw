///|
fn direct_session_key(session_key : String?, run_id : String) -> String {
  match session_key {
    Some(key) => key
    None => run_id
  }
}

///|
fn channel_session_key(
  channel_id : String,
  account_id : String,
  chat_id : String,
  thread_id : String?,
  dm_scope? : String = "per-account-channel-peer",
) -> String {
  let thread = thread_id.unwrap_or("")
  let base = match dm_scope {
    "main" => "\{channel_id}:\{account_id}:main"
    "per-channel-peer" => "\{channel_id}:\{chat_id}"
    _ => "\{channel_id}:\{account_id}:\{chat_id}"
  }
  if thread.is_blank() || dm_scope == "main" {
    base
  } else {
    "\{base}:\{thread}"
  }
}

///|
fn message_session_key(
  channel_id : String,
  account_id : String,
  message : @channel.Message,
  dm_scope? : String = "per-account-channel-peer",
) -> String {
  channel_session_key(
    channel_id,
    account_id,
    message.to,
    message.thread_id,
    dm_scope~,
  )
}

///|
fn coordination_session_key(
  coordination_id : String,
  task_id : String,
) -> String {
  "coord:\{coordination_id}:\{task_id}"
}

///|
fn pipeline_stage_session_key(
  pipeline_id : String,
  stage_name : String,
) -> String {
  "pipeline:\{pipeline_id}:\{stage_name}"
}
