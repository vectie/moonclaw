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
) -> String {
  let thread = thread_id.unwrap_or("")
  if thread.is_blank() {
    "\{channel_id}:\{account_id}:\{chat_id}"
  } else {
    "\{channel_id}:\{account_id}:\{chat_id}:\{thread}"
  }
}

///|
fn message_session_key(
  channel_id : String,
  account_id : String,
  message : @channel.Message,
) -> String {
  channel_session_key(channel_id, account_id, message.to, message.thread_id)
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
