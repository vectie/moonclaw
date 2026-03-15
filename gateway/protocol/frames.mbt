///|
pub(all) enum Frame {
  Req(Request)
  Res(Response)
  Event(EventFrame)
} derive(ToJson, FromJson, Show)

///|
pub(all) struct Request {
  id : String
  rpc_method : String
  params : Json?
} derive(ToJson, FromJson, Show)

///|
pub(all) struct Response {
  id : String
  ok : Bool
  payload : Json?
  error : ErrorShape?
} derive(ToJson, FromJson, Show)

///|
pub(all) struct EventFrame {
  event : String
  payload : Json?
  seq : Int?
  state_version : StateVersion?
} derive(ToJson, FromJson, Show)

///|
pub(all) struct ErrorShape {
  code : String
  message : String
  details : Json?
  retryable : Bool?
  retry_after_ms : Int?
} derive(ToJson, FromJson, Show)

///|
pub struct StateVersion {
  presence : Int?
  health : Int?
} derive(ToJson, FromJson, Show)
