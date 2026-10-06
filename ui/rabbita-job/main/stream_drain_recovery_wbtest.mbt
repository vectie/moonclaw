///|
/// Observe command scheduling without executing HTTP or setting up timers.
priv struct StreamDrainTestScheduler {
  mut effects : Int
  hooks : @cmd.Hooks
}

///|
impl @cmd.Scheduler for StreamDrainTestScheduler with fn run_effect(
  self,
  _kind,
  _execute,
) {
  self.effects += 1
}

///|
impl @cmd.Scheduler for StreamDrainTestScheduler with fn queue_message(
  _self,
  _id : @common.Id,
  _send,
) {
  ()
}

///|
impl @cmd.Scheduler for StreamDrainTestScheduler with fn drain_message(_self) {
  ()
}

///|
impl @cmd.Scheduler for StreamDrainTestScheduler with fn hooks(self) {
  self.hooks
}

///|
fn stream_recovery_effect_count(command : Cmd) -> Int {
  let scheduler : StreamDrainTestScheduler = {
    effects: 0,
    hooks: { url_request: None, url_changed: None, },
  }
  let scheduler_ref : &@cmd.Scheduler = scheduler
  scheduler_ref.add(command)
  scheduler.effects
}

///|
test "job malformed terminal batch requests one bounded final snapshot recovery" {
  let payload : Json = {
    "entries": ["not-json"],
    "closed": true,
    "error": Json::null(),
  }
  let parsed = parse_stream_drain_payload(payload.stringify())
  assert_true(parsed is Err(_))
  let model = { ..init_model(), selected_run_id: Some("run-1"), }
  let dispatch = @cmd.Emit(_ => @rabbita.none)
  let (recovery, next) = update(dispatch, StreamDrained("run-1", parsed), model)
  assert_true(next.detail_error is Some(_))
  // Same snapshot + runs refresh as a valid terminal batch, without a timer.
  let (completed, _) = update(
    dispatch,
    StreamDrained("run-1", Ok(([], true))),
    model,
  )
  assert_eq(stream_recovery_effect_count(recovery), 2)
  assert_eq(stream_recovery_effect_count(completed), 2)
  let (stale, _) = update(dispatch, StreamDrained("other", parsed), model)
  assert_eq(stream_recovery_effect_count(stale), 0)
}

///|
test "acp malformed terminal batch requests one bounded final snapshot recovery" {
  let payload : Json = {
    "entries": ["not-json"],
    "closed": true,
    "error": Json::null(),
  }
  let parsed = parse_acp_stream_drain_payload(payload.stringify())
  assert_true(parsed is Err(_))
  let model = init_model()
  let dispatch = @cmd.Emit(_ => @rabbita.none)
  let (recovery, next) = update(dispatch, AcpStreamDrained(parsed), model)
  assert_true(next.acp_error is Some(_))
  let (completed, _) = update(dispatch, AcpStreamDrained(Ok(([], true))), model)
  assert_eq(stream_recovery_effect_count(recovery), 1)
  assert_eq(stream_recovery_effect_count(completed), 1)
}
