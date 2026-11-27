///|
pub type WeixinOriginalId = String

///|
#derive(ToJson, FromJson, Debug)
pub struct WeixinAccountConfig {
  app_id : String
  app_secret : String
  token : String
  original_id : WeixinOriginalId?
  api_base_url : String?
  enabled : Bool
}

///|
#derive(ToJson, FromJson, Debug)
pub struct WeixinAccessTokenResponse {
  access_token : String?
  expires_in : Int32?
  errcode : Int32?
  errmsg : String?
}
