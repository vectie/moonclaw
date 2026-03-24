///|
pub type WeixinOriginalId = String

///|
pub struct WeixinAccountConfig {
  app_id : String
  app_secret : String
  token : String
  original_id : WeixinOriginalId?
  api_base_url : String?
  enabled : Bool
} derive(ToJson, FromJson, Show)

///|
pub struct WeixinAccessTokenResponse {
  access_token : String?
  expires_in : Int?
  errcode : Int?
  errmsg : String?
} derive(ToJson, FromJson, Show)
