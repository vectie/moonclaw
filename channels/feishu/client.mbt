///|
pub struct FeishuClient {
  config : FeishuAccountConfig
}

///|
pub fn FeishuClient::new(config : FeishuAccountConfig) -> FeishuClient {
  FeishuClient::{ config, }
}

///|
pub fn FeishuClient::send_text_message(
  self : FeishuClient,
  receive_id : String,
  text : String,
) -> Result[@channel.SendResult, @channel.ChannelError] {
  Ok(@channel.SendResult::{
    channel: "feishu",
    message_id: "msg_" + receive_id,
    timestamp: 0,
    status: "queued",
  })
}
