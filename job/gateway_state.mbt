///|
pub struct GatewayJobState {
  runtime : RuntimeManager
  cancel_requests : Map[String, Bool]
  force_stop_requests : Map[String, Bool]
  status_last_sent_at : Map[String, Int]
  last_notified_event_count : Map[String, Int]
  long_running_warned : Map[String, Bool]
}

///|
pub fn GatewayJobState::new(root~ : String) -> GatewayJobState {
  GatewayJobState::{
    runtime: RuntimeManager::new(root~),
    cancel_requests: {},
    force_stop_requests: {},
    status_last_sent_at: {},
    last_notified_event_count: {},
    long_running_warned: {},
  }
}

///|
pub async fn GatewayJobState::load(self : GatewayJobState) -> Unit {
  self.runtime.load()
}

///|
pub fn GatewayJobState::runtime(self : GatewayJobState) -> RuntimeManager {
  self.runtime
}

///|
pub fn GatewayJobState::should_cancel(
  self : GatewayJobState,
  run_id : String,
) -> Bool {
  self.cancel_requests.get(run_id).unwrap_or(false)
}

///|
pub fn GatewayJobState::should_force_stop(
  self : GatewayJobState,
  run_id : String,
) -> Bool {
  self.force_stop_requests.get(run_id).unwrap_or(false)
}

///|
pub fn GatewayJobState::clear_control_requests(
  self : GatewayJobState,
  run_id : String,
) -> Unit {
  self.cancel_requests.remove(run_id) |> ignore()
  self.force_stop_requests.remove(run_id) |> ignore()
}

///|
pub fn GatewayJobState::request_stop(
  self : GatewayJobState,
  run_id : String,
  force? : Bool = false,
) -> Unit {
  self.cancel_requests.set(run_id, true)
  if force {
    self.force_stop_requests.set(run_id, true)
  }
}

///|
pub fn GatewayJobState::notification_runtime_state(
  self : GatewayJobState,
  run_id : String,
) -> JobNotificationRuntimeState {
  JobNotificationRuntimeState::{
    last_sent_at: self.status_last_sent_at.get(run_id).unwrap_or(0),
    last_notified_event_count: self.last_notified_event_count
    .get(run_id)
    .unwrap_or(0),
    long_running_warned: self.long_running_warned.get(run_id).unwrap_or(false),
  }
}

///|
pub fn GatewayJobState::set_notification_runtime_state(
  self : GatewayJobState,
  run_id : String,
  state : JobNotificationRuntimeState,
) -> Unit {
  self.status_last_sent_at.set(run_id, state.last_sent_at)
  self.last_notified_event_count.set(run_id, state.last_notified_event_count)
  self.long_running_warned.set(run_id, state.long_running_warned)
}

///|
pub fn GatewayJobState::clear_notification_runtime_state(
  self : GatewayJobState,
  run_id : String,
) -> Unit {
  self.status_last_sent_at.remove(run_id) |> ignore()
  self.last_notified_event_count.remove(run_id) |> ignore()
  self.long_running_warned.remove(run_id) |> ignore()
}
