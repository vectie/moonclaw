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

///|
pub fn presentation_contract_version() -> String {
  "presentation_deck_spec.v1"
}

///|
pub fn presentation_deck_spec_schema_prompt() -> String {
  [
    "Return JSON only using the `\{presentation_contract_version()}` contract.",
    "Top-level shape:",
    "{\"title\":string,\"audience\":string?,\"objective\":string,\"source_report\":string?,\"requested_output_format\":string?,\"style_direction\":string?,\"vendor_notes\":string?,\"pages\":[{\"page_number\":number,\"page_type\":string,\"headline\":string,\"purpose\":string,\"key_message\":string,\"body_points\":string[],\"evidence\":string[],\"visual_type\":string,\"layout_instruction\":string,\"look_and_feel\":string,\"speaker_notes\":string?}],\"render_handoff\":{\"renderer_target\":string?,\"theme\":string?,\"delivery_notes\":string?,\"asset_requests\":string[]}?}",
    "Rules:",
    "- `pages` must contain the full deck in order.",
    "- Every page must describe both content and visual/layout intent.",
    "- `layout_instruction` must be specific enough for a downstream rendering vendor.",
    "- `visual_type` should identify the dominant visual form, such as title, KPI strip, two-column comparison, timeline, matrix, or recommendation slide.",
    "- Keep the deck presentation-ready rather than prose-heavy.",
  ].join("\n")
}

///|
pub fn parse_presentation_deck_spec_text(
  text : String,
) -> PresentationDeckSpec? {
  let trimmed = text.trim().to_string()
  if trimmed.is_blank() {
    return None
  }
  let first = match trimmed.find("{") {
    Some(index) => index
    None => return None
  }
  let mut end = trimmed.length()
  while end > first {
    let candidate = trimmed[first:end].to_string()
    if !candidate.has_suffix("}") {
      end = end - 1
      continue
    }
    let parsed_json = try? @json.parse(candidate)
    match parsed_json {
      Ok(json) => {
        let payload = try? @json.from_json(json)
        match payload {
          Ok(payload) => return Some(payload)
          Err(_) => ()
        }
      }
      Err(_) => ()
    }
    end = end - 1
  }
  None
}
