///|
pub struct PresentationRenderHandoff {
  renderer_target : String?
  theme : String?
  delivery_notes : String?
  asset_requests : Array[String]
} derive(ToJson, FromJson, Show)

///|
pub struct PresentationPageSpec {
  page_number : Int
  page_type : String
  headline : String
  purpose : String
  key_message : String
  body_points : Array[String]
  evidence : Array[String]
  visual_type : String
  layout_instruction : String
  look_and_feel : String
  speaker_notes : String?
} derive(ToJson, FromJson, Show)

///|
pub struct PresentationDeckSpec {
  title : String
  audience : String?
  objective : String
  source_report : String?
  requested_output_format : String?
  style_direction : String?
  vendor_notes : String?
  pages : Array[PresentationPageSpec]
  render_handoff : PresentationRenderHandoff?
} derive(ToJson, FromJson, Show)
