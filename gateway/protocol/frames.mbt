///|
pub(all) enum Frame {
  Req(Request)
  Res(Response)
  Event(EventFrame)
} derive(ToJson, FromJson, Debug)

///|
pub(all) struct Request {
  id : String
  rpc_method : String
  params : Json?
} derive(ToJson, FromJson, Debug)

///|
pub(all) struct Response {
  id : String
  ok : Bool
  payload : Json?
  error : ErrorShape?
} derive(ToJson, FromJson, Debug)

///|
pub(all) struct EventFrame {
  event : String
  payload : Json?
  seq : Int32?
  state_version : StateVersion?
} derive(ToJson, FromJson, Debug)

///|
pub(all) struct ErrorShape {
  code : String
  message : String
  details : Json?
  retryable : Bool?
  retry_after_ms : Int32?
} derive(ToJson, FromJson, Debug)

///|
pub struct StateVersion {
  presence : Int32?
  health : Int32?
} derive(ToJson, FromJson, Debug)
