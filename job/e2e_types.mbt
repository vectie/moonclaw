///|
pub struct E2EStarterAttachment {
  id : String
  mime_type : String
  url : String
  filename : String?
  size : Int?
} derive(ToJson, FromJson, Show)

///|
pub fn E2EStarterAttachment::new(
  id~ : String,
  mime_type~ : String,
  url~ : String,
  filename? : String? = None,
  size? : Int? = None,
) -> E2EStarterAttachment {
  { id, mime_type, url, filename, size }
}

///|
pub struct E2EJobIntake {
  request_text : String
  requested_output_format : String?
  starter_attachments : Array[E2EStarterAttachment]
  message_id : String?
  thread_id : String?
  content_type : String?
} derive(ToJson, FromJson, Show)

///|
pub fn E2EJobIntake::new(
  request_text~ : String,
  requested_output_format? : String? = None,
  starter_attachments? : Array[E2EStarterAttachment] = [],
  message_id? : String? = None,
  thread_id? : String? = None,
  content_type? : String? = None,
) -> E2EJobIntake {
  {
    request_text,
    requested_output_format,
    starter_attachments,
    message_id,
    thread_id,
    content_type,
  }
}
