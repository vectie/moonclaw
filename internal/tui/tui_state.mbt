///|
pub(all) struct TuiState {
  mut connection_status : String
  mut activity_status : String
  mut busy : Bool
  mut model : String
  mut agent_id : String
  mut session_key : String
  mut tools_expanded : Bool
  mut show_thinking : Bool
  mut last_ctrl_c_at : Int
}

///|
pub fn TuiState::new() -> TuiState {
  TuiState::{
    connection_status: "connecting",
    activity_status: "idle",
    busy: false,
    model: "unknown",
    agent_id: "default",
    session_key: "default",
    tools_expanded: false,
    show_thinking: false,
    last_ctrl_c_at: 0,
  }
}

///|
pub fn TuiState::set_connection_status(
  self : TuiState,
  status : String,
) -> Unit {
  self.connection_status = status
}

///|
pub fn TuiState::set_activity_status(self : TuiState, status : String) -> Unit {
  self.activity_status = status
}

///|
pub fn TuiState::set_busy(self : TuiState, busy : Bool) -> Unit {
  self.busy = busy
}

///|
pub fn TuiState::set_model(self : TuiState, model : String) -> Unit {
  self.model = model
}

///|
pub fn TuiState::set_agent_id(self : TuiState, id : String) -> Unit {
  self.agent_id = id
}

///|
pub fn TuiState::set_session_key(self : TuiState, key : String) -> Unit {
  self.session_key = key
}

///|
pub fn TuiState::toggle_tools_expanded(self : TuiState) -> Bool {
  self.tools_expanded = !self.tools_expanded
  self.tools_expanded
}

///|
pub fn TuiState::toggle_show_thinking(self : TuiState) -> Bool {
  self.show_thinking = !self.show_thinking
  self.show_thinking
}

///|
pub fn TuiState::connection_status(self : TuiState) -> String {
  self.connection_status
}

///|
pub fn TuiState::activity_status(self : TuiState) -> String {
  self.activity_status
}

///|
pub fn TuiState::is_busy(self : TuiState) -> Bool {
  self.busy
}

///|
pub fn TuiState::model(self : TuiState) -> String {
  self.model
}

///|
pub fn TuiState::agent_id(self : TuiState) -> String {
  self.agent_id
}

///|
pub fn TuiState::session_key(self : TuiState) -> String {
  self.session_key
}

///|
pub fn TuiState::tools_expanded(self : TuiState) -> Bool {
  self.tools_expanded
}

///|
pub fn TuiState::show_thinking(self : TuiState) -> Bool {
  self.show_thinking
}

///|
pub fn TuiState::update_last_ctrl_c(self : TuiState, time : Int) -> Unit {
  self.last_ctrl_c_at = time
}

///|
pub fn TuiState::last_ctrl_c_at(self : TuiState) -> Int {
  self.last_ctrl_c_at
}
