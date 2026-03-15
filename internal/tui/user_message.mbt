///|
pub(all) struct UserMessage {
  mut text : String
}

///|
pub fn UserMessage::new(text : String) -> UserMessage {
  UserMessage::{ text, }
}

///|
pub fn UserMessage::set_text(self : UserMessage, text : String) -> Unit {
  self.text = text
}

///|
pub fn UserMessage::text(self : UserMessage) -> String {
  self.text
}

///|
pub fn UserMessage::get_preferred_height(
  self : UserMessage,
  width : Int,
) -> Int {
  let inner_width = width - 4
  wrap_text(self.text, inner_width.max(1)).length() + 2
}

///|
pub fn UserMessage::render(
  self : UserMessage,
  output : RenderOutput,
  x : Int,
  y : Int,
  width : Int,
  height : Int,
) -> Unit {
  let theme = Theme::default()
  output.write(cursor_to(x, y))
  output.write(ClearLineRight)
  output.write(theme.user_style(" You "))
  let mut current_y = y + 1
  let inner_width = width - 4
  let max_lines = height - 2
  let mut line_idx = 0
  for line in wrap_text(self.text, inner_width.max(1)) {
    if line_idx >= max_lines {
      break
    }
    output.write(cursor_to(x + 2, current_y))
    output.write(ClearLineRight)
    output.write(theme.text_style(line))
    current_y += 1
    line_idx += 1
  }
  output.write(cursor_to(x, y + height - 1))
  output.write(ClearLineRight)
}
