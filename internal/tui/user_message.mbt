///|
pub(all) struct UserMessage {
  mut text : String
  mut lines : Array[String]
}

///|
pub fn UserMessage::new(text : String) -> UserMessage {
  UserMessage::{ text, lines: wrap_text(text, 80) }
}

///|
pub fn UserMessage::set_text(self : UserMessage, text : String) -> Unit {
  self.text = text
  self.lines = wrap_text(text, 80)
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
  let mut height = 2
  let inner_width = width - 4
  for line in self.lines {
    let line_width = @unicode/width.string(line)
    let wrapped = if inner_width > 0 {
      (line_width + inner_width - 1) / inner_width
    } else {
      1
    }
    height += wrapped.max(1)
  }
  height
}

///|
pub async fn UserMessage::render(
  self : UserMessage,
  output : @stdio.Output,
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
  for line in self.lines {
    if line_idx >= max_lines {
      break
    }
    output.write(cursor_to(x + 2, current_y))
    output.write(ClearLineRight)
    let wrapped_lines = wrap_text(line, inner_width.max(1))
    for wrapped_line in wrapped_lines {
      if line_idx >= max_lines {
        break
      }
      output.write(theme.text_style(wrapped_line))
      current_y += 1
      line_idx += 1
    }
  }
  output.write(cursor_to(x, y + height - 1))
  output.write(ClearLineRight)
}
