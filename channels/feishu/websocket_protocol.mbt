///|
priv struct FeishuWebSocketHeader {
  key : String
  value : String
}

///|
priv struct FeishuWebSocketFrame {
  seq_id : UInt64
  log_id : UInt64
  service : Int
  method_id : Int
  headers : Array[FeishuWebSocketHeader]
  payload_encoding : String?
  payload_type : String?
  payload : Bytes?
  log_id_new : String?
}

///|
priv struct FeishuWebSocketChunkState {
  chunks : Map[Int, Bytes]
}

///|
let feishu_ws_control_frame : Int = 0

///|
let feishu_ws_data_frame : Int = 1

///|
let feishu_ws_header_type : String = "type"

///|
let feishu_ws_header_message_id : String = "message_id"

///|
let feishu_ws_header_sum : String = "sum"

///|
let feishu_ws_header_seq : String = "seq"

///|
let feishu_ws_header_trace_id : String = "trace_id"

///|
let feishu_ws_header_biz_rt : String = "biz_rt"

///|
let feishu_ws_type_event : String = "event"

///|
let feishu_ws_type_ping : String = "ping"

///|
let feishu_ws_type_pong : String = "pong"

///|
fn write_varint(buffer : @buffer.Buffer, value : UInt64) -> Unit {
  let mut value = value
  while value >= 0x80 {
    buffer.write_byte(((value & 0x7f) | 0x80).to_byte())
    value = value >> 7
  }
  buffer.write_byte(value.to_byte())
}

///|
fn encode_field_key(field_number : Int, wire_type : Int) -> UInt64 {
  ((field_number << 3) | wire_type).to_uint64()
}

///|
fn write_length_delimited_field(
  buffer : @buffer.Buffer,
  field_number : Int,
  bytes : Bytes,
) -> Unit {
  write_varint(buffer, encode_field_key(field_number, 2))
  write_varint(buffer, bytes.length().to_uint64())
  buffer.write_bytes(bytes)
}

///|
fn encode_header_message(header : FeishuWebSocketHeader) -> Bytes {
  let buffer = @buffer.new()
  write_length_delimited_field(buffer, 1, @encoding/utf8.encode(header.key))
  write_length_delimited_field(buffer, 2, @encoding/utf8.encode(header.value))
  buffer.to_bytes()
}

///|
fn encode_feishu_websocket_frame(frame : FeishuWebSocketFrame) -> Bytes {
  let buffer = @buffer.new()
  write_varint(buffer, encode_field_key(1, 0))
  write_varint(buffer, frame.seq_id)
  write_varint(buffer, encode_field_key(2, 0))
  write_varint(buffer, frame.log_id)
  write_varint(buffer, encode_field_key(3, 0))
  write_varint(buffer, frame.service.to_uint64())
  write_varint(buffer, encode_field_key(4, 0))
  write_varint(buffer, frame.method_id.to_uint64())
  for header in frame.headers {
    write_length_delimited_field(buffer, 5, encode_header_message(header))
  }
  match frame.payload_encoding {
    Some(value) =>
      write_length_delimited_field(buffer, 6, @encoding/utf8.encode(value))
    None => ()
  }
  match frame.payload_type {
    Some(value) =>
      write_length_delimited_field(buffer, 7, @encoding/utf8.encode(value))
    None => ()
  }
  match frame.payload {
    Some(value) => write_length_delimited_field(buffer, 8, value)
    None => ()
  }
  match frame.log_id_new {
    Some(value) =>
      write_length_delimited_field(buffer, 9, @encoding/utf8.encode(value))
    None => ()
  }
  buffer.to_bytes()
}

///|
fn read_varint(bytes : BytesView, start : Int) -> (UInt64, Int)? {
  let mut value : UInt64 = 0
  let mut shift = 0
  let mut index = start
  while index < bytes.length() {
    let byte = bytes[index].to_uint64()
    value = value | ((byte & 0x7f) << shift)
    index = index + 1
    if (byte & 0x80) == 0 {
      return Some((value, index))
    }
    shift = shift + 7
    if shift >= 64 {
      return None
    }
  }
  None
}

///|
fn read_length_delimited(bytes : BytesView, start : Int) -> (Bytes, Int)? {
  let (length, next_index) = match read_varint(bytes, start) {
    Some(result) => result
    None => return None
  }
  let end = next_index + length.to_int()
  if end > bytes.length() {
    return None
  }
  Some((bytes[next_index:end].to_bytes(), end))
}

///|
fn decode_header_message(
  bytes : Bytes,
) -> Result[FeishuWebSocketHeader, String] {
  let mut index = 0
  let view = bytes[:]
  let mut key = ""
  let mut value = ""
  while index < view.length() {
    let (tag, next_index) = match read_varint(view, index) {
      Some(result) => result
      None => return Err("invalid header tag")
    }
    index = next_index
    let field_number = (tag >> 3).to_int()
    let wire_type = (tag & 0x7).to_int()
    match (field_number, wire_type) {
      (1, 2) => {
        let (raw, end) = match read_length_delimited(view, index) {
          Some(result) => result
          None => return Err("invalid header key")
        }
        key = @encoding/utf8.decode(raw) catch { _ => "" }
        index = end
      }
      (2, 2) => {
        let (raw, end) = match read_length_delimited(view, index) {
          Some(result) => result
          None => return Err("invalid header value")
        }
        value = @encoding/utf8.decode(raw) catch { _ => "" }
        index = end
      }
      (_, 0) =>
        match read_varint(view, index) {
          Some((_, end)) => index = end
          None => return Err("invalid header varint")
        }
      (_, 2) =>
        match read_length_delimited(view, index) {
          Some((_, end)) => index = end
          None => return Err("invalid header field")
        }
      _ => return Err("unsupported header wire type")
    }
  }
  Ok(FeishuWebSocketHeader::{ key, value })
}

///|
fn decode_feishu_websocket_frame(
  bytes : Bytes,
) -> Result[FeishuWebSocketFrame, String] {
  let mut index = 0
  let view = bytes[:]
  let mut seq_id : UInt64 = 0
  let mut log_id : UInt64 = 0
  let mut service = 0
  let mut method_id = 0
  let headers : Array[FeishuWebSocketHeader] = []
  let mut payload_encoding = None
  let mut payload_type = None
  let mut payload = None
  let mut log_id_new = None
  while index < view.length() {
    let (tag, next_index) = match read_varint(view, index) {
      Some(result) => result
      None => return Err("invalid frame tag")
    }
    index = next_index
    let field_number = (tag >> 3).to_int()
    let wire_type = (tag & 0x7).to_int()
    match (field_number, wire_type) {
      (1, 0) =>
        match read_varint(view, index) {
          Some((value, end)) => {
            seq_id = value
            index = end
          }
          None => return Err("invalid seq_id")
        }
      (2, 0) =>
        match read_varint(view, index) {
          Some((value, end)) => {
            log_id = value
            index = end
          }
          None => return Err("invalid log_id")
        }
      (3, 0) =>
        match read_varint(view, index) {
          Some((value, end)) => {
            service = value.to_int()
            index = end
          }
          None => return Err("invalid service")
        }
      (4, 0) =>
        match read_varint(view, index) {
          Some((value, end)) => {
            method_id = value.to_int()
            index = end
          }
          None => return Err("invalid method")
        }
      (5, 2) => {
        let (raw, end) = match read_length_delimited(view, index) {
          Some(result) => result
          None => return Err("invalid header field")
        }
        let header = match decode_header_message(raw) {
          Ok(header) => header
          Err(error) => return Err(error)
        }
        headers.push(header)
        index = end
      }
      (6, 2) => {
        let (raw, end) = match read_length_delimited(view, index) {
          Some(result) => result
          None => return Err("invalid payload_encoding")
        }
        payload_encoding = Some(@encoding/utf8.decode(raw) catch { _ => "" })
        index = end
      }
      (7, 2) => {
        let (raw, end) = match read_length_delimited(view, index) {
          Some(result) => result
          None => return Err("invalid payload_type")
        }
        payload_type = Some(@encoding/utf8.decode(raw) catch { _ => "" })
        index = end
      }
      (8, 2) => {
        let (raw, end) = match read_length_delimited(view, index) {
          Some(result) => result
          None => return Err("invalid payload")
        }
        payload = Some(raw)
        index = end
      }
      (9, 2) => {
        let (raw, end) = match read_length_delimited(view, index) {
          Some(result) => result
          None => return Err("invalid log_id_new")
        }
        log_id_new = Some(@encoding/utf8.decode(raw) catch { _ => "" })
        index = end
      }
      (_, 0) =>
        match read_varint(view, index) {
          Some((_, end)) => index = end
          None => return Err("invalid varint field")
        }
      (_, 2) =>
        match read_length_delimited(view, index) {
          Some((_, end)) => index = end
          None => return Err("invalid length-delimited field")
        }
      _ => return Err("unsupported frame wire type")
    }
  }
  Ok(FeishuWebSocketFrame::{
    seq_id,
    log_id,
    service,
    method_id,
    headers,
    payload_encoding,
    payload_type,
    payload,
    log_id_new,
  })
}

///|
fn feishu_ws_header(frame : FeishuWebSocketFrame, key : String) -> String? {
  for header in frame.headers {
    if header.key == key {
      return Some(header.value)
    }
  }
  None
}
