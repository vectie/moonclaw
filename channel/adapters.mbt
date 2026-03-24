///|
pub(all) struct OutboundAdapter {
  text_chunk_limit : Int
  delivery_mode : String
  chunker_mode : String
} derive(ToJson, FromJson, Show)

///|
pub fn OutboundAdapter::new(
  text_chunk_limit? : Int = 4000,
  delivery_mode? : String = "default",
  chunker_mode? : String = "sentence",
) -> OutboundAdapter {
  OutboundAdapter::{ text_chunk_limit, delivery_mode, chunker_mode }
}

///|
pub(all) struct ThreadingAdapter {
  reply_to_mode : String
  supports_threads : Bool
  thread_id_key : String?
} derive(ToJson, FromJson, Show)

///|
pub fn ThreadingAdapter::new(
  reply_to_mode? : String = "off",
  supports_threads? : Bool = false,
  thread_id_key? : String? = None,
) -> ThreadingAdapter {
  ThreadingAdapter::{ reply_to_mode, supports_threads, thread_id_key }
}

///|
pub(all) struct MentionAdapter {
  strip_patterns : Array[String]
  mention_prefix : String?
  mention_suffix : String?
} derive(ToJson, FromJson, Show)

///|
pub fn MentionAdapter::new(
  strip_patterns? : Array[String] = [],
  mention_prefix? : String? = None,
  mention_suffix? : String? = None,
) -> MentionAdapter {
  MentionAdapter::{ strip_patterns, mention_prefix, mention_suffix }
}

///|
pub(all) struct StreamingAdapter {
  enabled : Bool
  chunk_size : Int
  chunk_delay_ms : Int
  min_chars : Int?
  idle_ms : Int?
} derive(ToJson, FromJson, Show)

///|
pub fn StreamingAdapter::new(
  enabled? : Bool = false,
  chunk_size? : Int = 100,
  chunk_delay_ms? : Int = 50,
  min_chars? : Int? = None,
  idle_ms? : Int? = None,
) -> StreamingAdapter {
  StreamingAdapter::{ enabled, chunk_size, chunk_delay_ms, min_chars, idle_ms }
}

///|
pub(all) struct SecurityAdapter {
  dm_policy : String
  allow_from : Array[String]
  require_mention_in_groups : Bool
} derive(ToJson, FromJson, Show)

///|
pub fn SecurityAdapter::new(
  dm_policy? : String = "pairing",
  allow_from? : Array[String] = [],
  require_mention_in_groups? : Bool = true,
) -> SecurityAdapter {
  SecurityAdapter::{ dm_policy, allow_from, require_mention_in_groups }
}

///|
pub(all) struct ChannelDockConfig {
  outbound : OutboundAdapter?
  threading : ThreadingAdapter?
  mentions : MentionAdapter?
  streaming : StreamingAdapter?
  security : SecurityAdapter?
} derive(ToJson, FromJson, Show)

///|
pub fn ChannelDockConfig::new(
  outbound? : OutboundAdapter? = None,
  threading? : ThreadingAdapter? = None,
  mentions? : MentionAdapter? = None,
  streaming? : StreamingAdapter? = None,
  security? : SecurityAdapter? = None,
) -> ChannelDockConfig {
  ChannelDockConfig::{ outbound, threading, mentions, streaming, security }
}

///|
pub fn ChannelDockConfig::default_for_channel(
  channel_id : String,
) -> ChannelDockConfig {
  match channel_id {
    "feishu" =>
      ChannelDockConfig::new(
        outbound=Some(OutboundAdapter::new(text_chunk_limit=4000)),
        threading=Some(
          ThreadingAdapter::new(reply_to_mode="off", supports_threads=true),
        ),
        mentions=Some(
          MentionAdapter::new(strip_patterns=["<at user_id=\"\\d+\">.*?</at>"]),
        ),
        streaming=Some(StreamingAdapter::new(enabled=false)),
        security=Some(SecurityAdapter::new(dm_policy="pairing")),
      )
    "slack" =>
      ChannelDockConfig::new(
        outbound=Some(OutboundAdapter::new(text_chunk_limit=4000)),
        threading=Some(
          ThreadingAdapter::new(reply_to_mode="off", supports_threads=true),
        ),
        mentions=Some(MentionAdapter::new(strip_patterns=["<@[^>]+>"])),
        streaming=Some(
          StreamingAdapter::new(
            enabled=true,
            min_chars=Some(1500),
            idle_ms=Some(1000),
          ),
        ),
        security=Some(SecurityAdapter::new(dm_policy="allow_from")),
      )
    "telegram" =>
      ChannelDockConfig::new(
        outbound=Some(OutboundAdapter::new(text_chunk_limit=4000)),
        threading=Some(
          ThreadingAdapter::new(reply_to_mode="off", supports_threads=true),
        ),
        streaming=Some(StreamingAdapter::new(enabled=true)),
        security=Some(SecurityAdapter::new(dm_policy="pairing")),
      )
    "discord" =>
      ChannelDockConfig::new(
        outbound=Some(OutboundAdapter::new(text_chunk_limit=2000)),
        threading=Some(
          ThreadingAdapter::new(reply_to_mode="off", supports_threads=true),
        ),
        mentions=Some(MentionAdapter::new(strip_patterns=["<@!?\\d+>"])),
        streaming=Some(
          StreamingAdapter::new(
            enabled=true,
            min_chars=Some(1500),
            idle_ms=Some(1000),
          ),
        ),
        security=Some(SecurityAdapter::new(dm_policy="allow_from")),
      )
    "weixin" =>
      ChannelDockConfig::new(
        outbound=Some(OutboundAdapter::new(text_chunk_limit=4000)),
        threading=Some(
          ThreadingAdapter::new(reply_to_mode="off", supports_threads=false),
        ),
        streaming=Some(StreamingAdapter::new(enabled=false)),
        security=Some(SecurityAdapter::new(dm_policy="pairing")),
      )
    _ => ChannelDockConfig::new()
  }
}
