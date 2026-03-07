///|
pub(all) enum ClientMode {
  Cli
  Backend
  Webchat
  Probe
} derive(ToJson, FromJson, Show, Eq)

///|
pub(all) struct ClientInfo {
  id : String
  display_name : String?
  version : String?
  platform : String?
  mode : ClientMode
} derive(ToJson, FromJson, Show)

///|
pub(all) struct AuthCredentials {
  token : String?
  password : String?
} derive(ToJson, FromJson, Show)

///|
pub(all) enum ClientRole {
  Operator
  Node
} derive(ToJson, FromJson, Show, Eq)

///|
pub(all) struct ConnectParams {
  min_protocol : Int
  max_protocol : Int
  client : ClientInfo
  auth : AuthCredentials
  role : ClientRole
  scopes : Array[String]?
} derive(ToJson, FromJson, Show)

///|
pub(all) struct HelloOk {
  protocol : Int
  server : ServerInfo
  features : Features
  snapshot : Snapshot
  policy : Policy
} derive(ToJson, FromJson, Show)

///|
pub(all) struct ServerInfo {
  version : String
  commit : String?
  host : String?
  conn_id : String
} derive(ToJson, FromJson, Show)

///|
pub(all) struct Features {
  methods : Array[String]
  events : Array[String]
} derive(ToJson, FromJson, Show)

///|
pub(all) struct Snapshot {
  presence : Json?
  health : Json?
  state_version : StateVersion?
} derive(ToJson, FromJson, Show)

///|
pub(all) struct Policy {
  max_payload : Int
  max_buffered_bytes : Int
  tick_interval_ms : Int
} derive(ToJson, FromJson, Show)
