///|
pub(all) struct AssistantMessage {
  mut text : String
  mut is_streaming : Bool
}

///|
pub fn AssistantMessage::new(text : String) -> AssistantMessage {
  AssistantMessage::{ text, is_streaming: false }
}

///|
pub fn AssistantMessage::set_text(
  self : AssistantMessage,
  text : String,
) -> Unit {
  self.text = text
}

///|
pub fn AssistantMessage::text(self : AssistantMessage) -> String {
  self.text
}

///|
pub fn AssistantMessage::set_streaming(
  self : AssistantMessage,
  streaming : Bool,
) -> Unit {
  self.is_streaming = streaming
}

///|
pub fn AssistantMessage::is_streaming(self : AssistantMessage) -> Bool {
  self.is_streaming
}

///|
pub fn AssistantMessage::get_preferred_height(
  self : AssistantMessage,
  width : Int,
) -> Int {
  let inner_width = width - 2
  let lines = wrap_text(self.text, inner_width.max(1))
  (lines.length() + 1).max(2)
}

///|
pub fn AssistantMessage::render(
  self : AssistantMessage,
  output : RenderOutput,
  x : Int,
  y : Int,
  width : Int,
  height : Int,
) -> Unit {
  let theme = Theme::default()
  output.write(cursor_to(x, y))
  output.write(ClearLineRight)
  output.write(theme.accent_style(" Assistant"))
  if self.is_streaming {
    output.write(theme.dim_style(" (streaming...)"))
  }
  let mut current_y = y + 1
  let inner_width = width - 2
  let max_lines = height - 1
  let mut line_idx = 0
  for line in wrap_text(self.text, inner_width.max(1)) {
    if line_idx >= max_lines {
      break
    }
    output.write(cursor_to(x + 1, current_y))
    output.write(ClearLineRight)
    output.write(theme.text_style(line))
    current_y += 1
    line_idx += 1
  }
}

///|
pub(all) struct SystemMessage {
  mut text : String
}

///|
pub fn SystemMessage::new(text : String) -> SystemMessage {
  SystemMessage::{ text, }
}

///|
pub fn SystemMessage::set_text(self : SystemMessage, text : String) -> Unit {
  self.text = text
}

///|
pub fn SystemMessage::text(self : SystemMessage) -> String {
  self.text
}

///|
pub fn SystemMessage::get_preferred_height(
  self : SystemMessage,
  _width : Int,
) -> Int {
  let lines = self.text.split("\n").collect()
  lines.length() + 2
}

///|
pub fn SystemMessage::render(
  self : SystemMessage,
  output : RenderOutput,
  x : Int,
  y : Int,
  width : Int,
  height : Int,
) -> Unit {
  let theme = Theme::default()
  output.write(cursor_to(x, y))
  output.write(ClearLineRight)
  output.write(theme.system(" System: "))
  output.write(theme.dim_style(self.text))
  let text_lines = self.text.split("\n").collect()
  let mut current_y = y + 1
  let max_lines = (height - 1).min(text_lines.length())
  for i in 1..<=max_lines {
    output.write(cursor_to(x, current_y))
    output.write(ClearLineRight)
    output.write(
      theme.dim_style(truncate_to_width(text_lines[i].to_string(), width)),
    )
    current_y += 1
  }
}
