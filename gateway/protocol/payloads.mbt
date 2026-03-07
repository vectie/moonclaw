///|
pub(all) struct ChallengePayload {
  nonce : String
  ts : Int
} derive(ToJson, FromJson, Show)

///|
pub(all) struct AgentParams {
  message : String
  session_key : String?
  cwd : String?
  model : String?
  provider : String?
  run_id : String?
  idempotency_key : String?
} derive(ToJson, FromJson, Show)

///|
pub(all) struct AgentAcceptedPayload {
  run_id : String
  status : String
  accepted_at : Int
} derive(ToJson, FromJson, Show)

///|
pub(all) struct AgentResultPayload {
  run_id : String
  status : String
  result : Json?
  error : ErrorShape?
} derive(ToJson, FromJson, Show)

///|
pub(all) struct AgentEventPayload {
  run_id : String
  kind : String
  delta : String?
  content : String?
  usage : Json?
} derive(ToJson, FromJson, Show)

///|
pub(all) struct SessionsListPayload {
  sessions : Array[SessionInfo]
} derive(ToJson, FromJson, Show)

///|
pub(all) struct SessionInfo {
  session_id : String
  updated_at : Int
  channel : String?
  model_override : String?
  provider_override : String?
} derive(ToJson, FromJson, Show)

///|
pub(all) struct HealthPayload {
  status : String
  uptime_ms : Int
  active_sessions : Int
  pending_requests : Int
} derive(ToJson, FromJson, Show)

///|
pub(all) struct ConfigGetPayload {
  config : Json
} derive(ToJson, FromJson, Show)

///|
pub(all) struct ConfigSetParams {
  config : Json
} derive(ToJson, FromJson, Show)
