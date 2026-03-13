///|
pub type FeishuDomain = String

///|
pub type FeishuConnectionMode = String

///|
pub type FeishuDmPolicy = String

///|
pub type FeishuReactionNotifications = String

///|
pub struct FeishuAccountConfig {
  app_id : String
  app_secret : String
  domain : FeishuDomain
  connection_mode : FeishuConnectionMode
  dm_policy : FeishuDmPolicy
  reaction_notifications : FeishuReactionNotifications?
  bot_name : String?
  webhook_url : String?
  websocket_url : String?
  websocket_headers : Map[String, String]?
  verify_token : String?
  encryption_key : String?
  enabled : Bool
} derive(ToJson, FromJson, Show)

///|
pub struct FeishuMessage {
  message_id : String
  chat_type : String
  message_type : String
  content : String
  create_time : String
  chat_id : String
  msg_root_id : String?
  msg_parent_id : String?
  from_user_id : String?
  tenant_key : String?
} derive(ToJson, FromJson, Show)

///|
pub struct FeishuEvent {
  schema : String
  header : FeishuEventHeader
  event : Json
  token : String?
} derive(ToJson, FromJson, Show)

///|
pub struct FeishuEventHeader {
  event_id : String
  event_type : String
  create_time : String
  token : String?
  app_id : String
  tenant_key : String?
  resource_id : String?
  user_list : Array[String]?
} derive(ToJson, FromJson, Show)

///|
pub struct FeishuSendMessageRequest {
  receive_id : String
  msg_type : String
  content : String
} derive(ToJson, FromJson, Show)

///|
pub struct FeishuSendMessageResponse {
  code : Int
  msg : String
  data : FeishuMessageData?
} derive(ToJson, FromJson, Show)

///|
pub struct FeishuMessageData {
  message_id : String
} derive(ToJson, FromJson, Show)

///|
pub struct FeishuMessageLookupResponse {
  code : Int
  msg : String
  data : FeishuMessageLookupData?
} derive(ToJson, FromJson, Show)

///|
pub struct FeishuMessageLookupData {
  items : Array[FeishuMessageLookupItem]
} derive(ToJson, FromJson, Show)

///|
pub struct FeishuMessageLookupItem {
  message_id : String
  chat_id : String
  chat_type : String?
  create_time : String?
  thread_id : String?
  upper_message_id : String?
  msg_type : String?
  body : FeishuMessageLookupBody?
  sender : FeishuMessageLookupSender?
} derive(ToJson, FromJson, Show)

///|
pub struct FeishuMessageLookupBody {
  content : String?
} derive(ToJson, FromJson, Show)

///|
pub struct FeishuMessageLookupSender {
  id : String?
  sender_type : String?
} derive(ToJson, FromJson, Show)

///|
pub struct FeishuUserLookupResponse {
  code : Int
  msg : String
  data : FeishuUserLookupData?
} derive(ToJson, FromJson, Show)

///|
pub struct FeishuUserLookupData {
  user : FeishuUser?
} derive(ToJson, FromJson, Show)

///|
pub struct FeishuUserBatchLookupResponse {
  code : Int
  msg : String
  data : FeishuUserBatchLookupData?
} derive(ToJson, FromJson, Show)

///|
pub struct FeishuUserBatchLookupData {
  items : Array[FeishuUser]
} derive(ToJson, FromJson, Show)

///|
pub struct FeishuUser {
  open_id : String?
  name : String?
  display_name : String?
  nickname : String?
  en_name : String?
} derive(ToJson, FromJson, Show)

///|
pub struct FeishuAccessTokenResponse {
  code : Int
  msg : String
  tenant_access_token : String?
  app_access_token : String?
  expire : Int?
} derive(ToJson, FromJson, Show)

///|
pub struct FeishuWebSocketEndpointResponse {
  code : Int
  msg : String
  data : Json?
} derive(ToJson, FromJson, Show)

///|
pub struct FeishuWebSocketEndpointData {
  url : String
  client_config : FeishuWebSocketClientConfig?
} derive(ToJson, Show)

///|
pub struct FeishuWebSocketClientConfig {
  ping_interval : Int?
  reconnect_count : Int?
  reconnect_interval : Int?
  reconnect_nonce : Int?
} derive(ToJson, Show)
