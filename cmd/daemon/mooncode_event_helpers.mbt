///|
fn mooncode_event(
  session_id~ : String,
  command_id~ : String,
  lane~ : String,
  kind~ : String,
  title~ : String,
  status~ : String,
  detail~ : String,
  now~ : @clock.Timestamp,
) -> Json {
  {
    "id": "moonclaw-\{session_id}-\{command_id}-\{kind}-\{now}",
    "protocol": mooncode_protocol_version(),
    "session_id": session_id,
    "command_id": command_id,
    "lane": lane,
    "kind": kind,
    "title": title,
    "status": status,
    "detail": detail,
    "created_at": now,
    "source": "moonclaw-native-mooncode",
  }
}
