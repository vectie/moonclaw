///|
pub fn conversation_watch_contract_id() -> String {
  @conversation.watch_contract_id()
}

///|
pub fn conversation_watch_kind() -> String {
  @conversation.watch_kind()
}

///|
pub fn conversation_watch_contract_json() -> Json {
  @conversation.watch_contract_json()
}

///|
pub fn conversation_watch_response(
  session_id~ : String,
  revision~ : Int,
  next_sequence~ : Int,
  changed~ : Bool,
  heartbeat~ : Bool,
  terminal~ : Bool,
  retry_after_ms~ : Int,
  snapshot~ : Json,
) -> Json {
  @conversation.watch_response(
    session_id~,
    revision~,
    next_sequence~,
    changed~,
    heartbeat~,
    terminal~,
    retry_after_ms~,
    snapshot~,
  )
}
