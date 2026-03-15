///|
pub(all) struct Text {
  mut content : String
  mut lines : Array[String]
  mut style : TextStyle
}

///|
pub struct TextStyle {
  fg : Color?
  bg : Color?
  bold : Bool
  dim : Bool
  italic : Bool
  underline : Bool
}

///|
pub fn TextStyle::default() -> TextStyle {
  TextStyle::{
    fg: None,
    bg: None,
    bold: false,
    dim: false,
    italic: false,
    underline: false,
  }
}

///|
pub fn TextStyle::with_fg(style : TextStyle, color : Color) -> TextStyle {
  { ..style, fg: Some(color) }
}

///|
pub fn TextStyle::with_bg(style : TextStyle, color : Color) -> TextStyle {
  { ..style, bg: Some(color) }
}

///|
pub fn TextStyle::bold(style : TextStyle) -> TextStyle {
  { ..style, bold: true }
}

///|
pub fn TextStyle::dim(style : TextStyle) -> TextStyle {
  { ..style, dim: true }
}

///|
pub fn TextStyle::italic(style : TextStyle) -> TextStyle {
  { ..style, italic: true }
}

///|
pub fn TextStyle::underline(style : TextStyle) -> TextStyle {
  { ..style, underline: true }
}

///|
pub fn Text::new(content : String) -> Text {
  Text::{
    content,
    lines: content.split("\n").map(fn(v) { v.to_string() }).collect(),
    style: TextStyle::default(),
  }
}

///|
pub fn Text::with_style(content : String, style : TextStyle) -> Text {
  Text::{
    content,
    lines: content.split("\n").map(fn(v) { v.to_string() }).collect(),
    style,
  }
}

///|
pub fn Text::set_text(self : Text, content : String) -> Unit {
  self.content = content
  self.lines = content.split("\n").map(fn(v) { v.to_string() }).collect()
}

///|
pub fn Text::text(self : Text) -> String {
  self.content
}

///|
pub fn Text::set_style(self : Text, style : TextStyle) -> Unit {
  self.style = style
}

///|
pub fn Text::line_count(self : Text) -> Int {
  self.lines.length()
}

///|
pub fn Text::get_preferred_height(self : Text, _width : Int) -> Int {
  self.lines.length().max(1)
}

///|
pub fn Text::render(
  self : Text,
  output : RenderOutput,
  x : Int,
  y : Int,
  width : Int,
  height : Int,
) -> Unit {
  let mut current_y = y
  let max_lines = height.min(self.lines.length())
  for i in 0..<max_lines {
    let line = self.lines[i]
    let styled_line = self.apply_style(line)
    let truncated = truncate_to_width(styled_line, width)
    output.write(cursor_to(x, current_y))
    output.write(ClearLineRight)
    output.write(truncated)
    current_y += 1
  }
}

///|
pub fn Text::apply_style(self : Text, text : String) -> String {
  let mut result = ""
  if self.style.bold {
    result = "\{result}\{Bold}"
  }
  if self.style.dim {
    result = "\{result}\{Dim}"
  }
  if self.style.italic {
    result = "\{result}\{Italic}"
  }
  if self.style.underline {
    result = "\{result}\{Underline}"
  }
  if self.style.fg is Some(c) {
    result = "\{result}\{c.fg()}"
  }
  if self.style.bg is Some(c) {
    result = "\{result}\{c.bg()}"
  }
  "\{result}\{text}\{Reset}"
}

///|
fn truncate_to_width(text : String, max_width : Int) -> String {
  let mut width = 0
  let mut result = ""
  for c in text {
    let c_width = @unicode/width.char(c).unwrap_or(1)
    if width + c_width > max_width {
      break
    }
    result = "\{result}\{c}"
    width += c_width
  }
  result
}

///|
pub fn wrap_text(text : String, max_width : Int) -> Array[String] {
  let lines : Array[String] = []
  let max_width = max_width.max(1) // Ensure max_width is at least 1
  for line in text.split("\n") {
    let line = line.to_string()
    if @unicode/width.string(line) <= max_width {
      lines.push(line)
    } else {
      let mut current = ""
      let mut current_width = 0
      for c in line {
        let c_width = @unicode/width.char(c).unwrap_or(1)
        if current_width > 0 && current_width + c_width > max_width {
          lines.push(current)
          current = c.to_string()
          current_width = c_width
        } else {
          current = "\{current}\{c}"
          current_width += c_width
        }
      }
      if current.length() > 0 {
        lines.push(current)
      }
    }
  }
  lines
}

///|
pub(all) struct Spacer {
  height : Int
}

///|
pub fn Spacer::new(height? : Int = 1) -> Spacer {
  Spacer::{ height, }
}

///|
pub fn Spacer::get_preferred_height(self : Spacer, _width : Int) -> Int {
  self.height
}

///|
pub fn Spacer::render(
  self : Spacer,
  output : RenderOutput,
  x : Int,
  y : Int,
  _width : Int,
  height : Int,
) -> Unit {
  for i in 0..<height.min(self.height) {
    output.write(cursor_to(x, y + i))
    output.write(ClearLineRight)
  }
}

///|
pub(all) struct Box {
  title : String
  mut content : String
  border_style : TextStyle
  content_style : TextStyle
  mut expanded : Bool
}

///|
pub fn Box::new(title : String, content : String) -> Box {
  Box::{
    title,
    content,
    border_style: TextStyle::default(),
    content_style: TextStyle::default(),
    expanded: false,
  }
}

///|
pub fn Box::set_expanded(self : Box, expanded : Bool) -> Unit {
  self.expanded = expanded
}

///|
pub fn Box::set_content(self : Box, content : String) -> Unit {
  self.content = content
}

///|
pub fn Box::get_preferred_height(self : Box, width : Int) -> Int {
  let content_lines : Array[String] = self.content
    .split("\n")
    .map(fn(v) { v.to_string() })
    .collect()
  let inner_width = width - 2
  let mut height = 2
  if self.expanded {
    for line in content_lines {
      let line_wraps = (@unicode/width.string(line) + inner_width - 1) /
        inner_width.max(1)
      height += line_wraps.max(1)
    }
  } else {
    height += 1
  }
  height
}

///|
pub fn Box::render(
  self : Box,
  output : RenderOutput,
  x : Int,
  y : Int,
  width : Int,
  height : Int,
) -> Unit {
  output.write(cursor_to(x, y))
  output.write(ClearLineRight)
  output.write("┌ ")
  output.write(self.title)
  output.write(" ")
  let title_width = @unicode/width.string(self.title) + 3
  for _ in title_width..<(width - 1) {
    output.write("─")
  }
  output.write("┐")
  let content_lines : Array[String] = self.content
    .split("\n")
    .map(fn(v) { v.to_string() })
    .collect()
  let mut current_y = y + 1
  let max_content_height = height - 2
  if self.expanded {
    for i in 0..<content_lines.length().min(max_content_height) {
      let line = content_lines[i]
      output.write(cursor_to(x, current_y))
      output.write(ClearLineRight)
      output.write("│ ")
      output.write(truncate_to_width(line, width - 4))
      current_y += 1
    }
    while current_y < y + height - 1 {
      output.write(cursor_to(x, current_y))
      output.write(ClearLineRight)
      output.write("│")
      current_y += 1
    }
  } else {
    output.write(cursor_to(x, current_y))
    output.write(ClearLineRight)
    output.write("│ ")
    if content_lines.length() > 0 {
      output.write(truncate_to_width(content_lines[0], width - 4))
    }
    current_y += 1
  }
  output.write(cursor_to(x, y + height - 1))
  output.write(ClearLineRight)
  output.write("└")
  for _ in 1..<(width - 1) {
    output.write("─")
  }
  output.write("┘")
}
