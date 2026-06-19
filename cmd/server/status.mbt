///|
pub(all) enum Status {
  Idle
  Busy
}

///|
pub impl ToJson for Status with fn to_json(self) {
  match self {
    Idle => "idle"
    Busy => "generating"
  }
}

///|
pub impl @json.FromJson for Status with fn from_json(json, path) {
  guard json is String(s) else {
    raise JsonDecodeError(
      (
        path, "@vectie/moonclaw/cmd/server.Status::from_json: expected string representation",
      ),
    )
  }
  match s.to_lower() {
    "idle" => Idle
    "generating" => Busy
    _ =>
      raise JsonDecodeError(
        (
          path,
          "@vectie/moonclaw/cmd/server.Status::from_json: unknown status '\{s}'",
        ),
      )
  }
}

///|
test "Status::ToJson" {
  json_inspect(Idle, content="idle")
  json_inspect(Busy, content="generating")
}

///|
test "Status::FromJson" {
  json_inspect(@json.from_json("idle") is Idle, content=true)
  json_inspect(@json.from_json("generating") is Busy, content=true)
}
