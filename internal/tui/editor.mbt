///|
pub(all) struct Editor {
  mut text : String
  mut cursor : Int
  history : Array[String]
  mut history_index : Int
  mut placeholder : String
  multiline : Bool
  mut on_submit : ((String) -> Unit)?
  mut on_change : ((String) -> Unit)?
  mut on_escape : (() -> Unit)?
  mut on_ctrl_c : (() -> Unit)?
  mut on_ctrl_d : (() -> Unit)?
  mut prompt : String
  style : TextStyle
}

///|
pub fn Editor::new() -> Editor {
  Editor::{
    text: "",
    cursor: 0,
    history: [],
    history_index: -1,
    placeholder: "",
    multiline: false,
    on_submit: None,
    on_change: None,
    on_escape: None,
    on_ctrl_c: None,
    on_ctrl_d: None,
    prompt: "> ",
    style: TextStyle::default(),
  }
}

///|
pub fn Editor::with_prompt(prompt : String) -> Editor {
  Editor::{
    text: "",
    cursor: 0,
    history: [],
    history_index: -1,
    placeholder: "",
    multiline: false,
    on_submit: None,
    on_change: None,
    on_escape: None,
    on_ctrl_c: None,
    on_ctrl_d: None,
    prompt,
    style: TextStyle::default(),
  }
}

///|
pub fn Editor::with_placeholder(placeholder : String) -> Editor {
  Editor::{
    text: "",
    cursor: 0,
    history: [],
    history_index: -1,
    placeholder,
    multiline: false,
    on_submit: None,
    on_change: None,
    on_escape: None,
    on_ctrl_c: None,
    on_ctrl_d: None,
    prompt: "> ",
    style: TextStyle::default(),
  }
}

///|
pub fn Editor::set_text(self : Editor, text : String) -> Unit {
  self.text = text
  self.cursor = text.length()
  if self.on_change is Some(cb) {
    cb(text)
  }
}

///|
pub fn Editor::text(self : Editor) -> String {
  self.text
}

///|
pub fn Editor::cursor(self : Editor) -> Int {
  self.cursor
}

///|
pub fn Editor::prompt_text(self : Editor) -> String {
  self.prompt
}

///|
pub fn Editor::placeholder_text(self : Editor) -> String {
  self.placeholder
}

///|
pub fn Editor::clear(self : Editor) -> Unit {
  self.text = ""
  self.cursor = 0
}

///|
pub fn Editor::set_on_submit(
  self : Editor,
  callback : (String) -> Unit,
) -> Unit {
  self.on_submit = Some(callback)
}

///|
pub fn Editor::set_on_change(
  self : Editor,
  callback : (String) -> Unit,
) -> Unit {
  self.on_change = Some(callback)
}

///|
pub fn Editor::set_on_escape(self : Editor, callback : () -> Unit) -> Unit {
  self.on_escape = Some(callback)
}

///|
pub fn Editor::set_on_ctrl_c(self : Editor, callback : () -> Unit) -> Unit {
  self.on_ctrl_c = Some(callback)
}

///|
pub fn Editor::set_on_ctrl_d(self : Editor, callback : () -> Unit) -> Unit {
  self.on_ctrl_d = Some(callback)
}

///|
pub fn Editor::add_to_history(self : Editor, text : String) -> Unit {
  if text.trim().length() > 0 {
    if self.history.length() == 0 ||
      self.history[self.history.length() - 1] != text {
      self.history.push(text)
      if self.history.length() > 1000 {
        ignore(self.history.remove(0))
      }
    }
  }
  self.history_index = self.history.length()
}

///|
pub fn Editor::get_preferred_height(self : Editor, _width : Int) -> Int {
  if self.multiline {
    let lines = self.text.split("\n").collect()
    lines.length() + 1
  } else {
    1
  }
}

///|
pub fn Editor::render(
  self : Editor,
  output : RenderOutput,
  x : Int,
  y : Int,
  width : Int,
  _height : Int,
) -> Unit {
  output.write(cursor_to(x, y))
  output.write(ClearLineRight)
  output.write(colorize(self.prompt, Color::BrightGreen))
  let display_text = if self.text.length() == 0 {
    dim(self.placeholder)
  } else {
    self.text
  }
  let prompt_width = @unicode/width.string(self.prompt)
  let available_width = width - prompt_width
  let truncated = truncate_to_width(display_text, available_width)
  output.write(truncated)
  let cursor_col = x +
    prompt_width +
    @unicode/width.string(self.text[:self.cursor])
  output.write(cursor_to(cursor_col, y))
  output.write(CursorShow)
}

///|
pub fn Editor::handle_key(self : Editor, key : Key) -> Bool {
  match key {
    Char(c) => {
      self.insert_char(c)
      true
    }
    Enter => {
      self.submit()
      true
    }
    Backspace => {
      self.delete_left()
      true
    }
    Delete => {
      self.delete_right()
      true
    }
    Left => {
      self.move_left()
      true
    }
    Right => {
      self.move_right()
      true
    }
    Home => {
      self.cursor = 0
      true
    }
    End => {
      self.cursor = self.text.length()
      true
    }
    Up => {
      self.history_prev()
      true
    }
    Down => {
      self.history_next()
      true
    }
    Escape => {
      if self.on_escape is Some(cb) {
        cb()
      }
      true
    }
    Ctrl('c') => {
      if self.on_ctrl_c is Some(cb) {
        cb()
      } else if self.text.length() > 0 {
        self.clear()
      }
      true
    }
    Ctrl('d') => {
      if self.text.length() == 0 && self.on_ctrl_d is Some(cb) {
        cb()
      }
      true
    }
    Ctrl('a') => {
      self.cursor = 0
      true
    }
    Ctrl('e') => {
      self.cursor = self.text.length()
      true
    }
    Ctrl('k') => {
      self.text = self.text[:self.cursor].to_string()
      true
    }
    Ctrl('u') => {
      self.text = self.text[self.cursor:].to_string()
      self.cursor = 0
      true
    }
    Ctrl('w') => {
      self.delete_word_left()
      true
    }
    _ => false
  }
}

///|
fn Editor::insert_char(self : Editor, c : Char) -> Unit {
  let before = self.text[:self.cursor]
  let after = self.text[self.cursor:]
  self.text = "\{before}\{c}\{after}"
  self.cursor += 1
  if self.on_change is Some(cb) {
    cb(self.text)
  }
}

///|
fn Editor::delete_left(self : Editor) -> Unit {
  if self.cursor > 0 {
    let before = self.text[:self.cursor - 1]
    let after = self.text[self.cursor:]
    self.text = "\{before}\{after}"
    self.cursor -= 1
    if self.on_change is Some(cb) {
      cb(self.text)
    }
  }
}

///|
fn Editor::delete_right(self : Editor) -> Unit {
  if self.cursor < self.text.length() {
    let before = self.text[:self.cursor]
    let after = self.text[self.cursor + 1:]
    self.text = "\{before}\{after}"
    if self.on_change is Some(cb) {
      cb(self.text)
    }
  }
}

///|
fn Editor::move_left(self : Editor) -> Unit {
  if self.cursor > 0 {
    self.cursor -= 1
  }
}

///|
fn Editor::move_right(self : Editor) -> Unit {
  if self.cursor < self.text.length() {
    self.cursor += 1
  }
}

///|
fn Editor::delete_word_left(self : Editor) -> Unit {
  let mut new_cursor = self.cursor
  while new_cursor > 0 {
    match self.text.get_char(new_cursor - 1) {
      Some(c) => if c.is_whitespace() { new_cursor -= 1 } else { break }
      None => break
    }
  }
  while new_cursor > 0 {
    match self.text.get_char(new_cursor - 1) {
      Some(c) => if !c.is_whitespace() { new_cursor -= 1 } else { break }
      None => break
    }
  }
  self.text = "\{self.text[:new_cursor]}\{self.text[self.cursor:]}"
  self.cursor = new_cursor
  if self.on_change is Some(cb) {
    cb(self.text)
  }
}

///|
fn Editor::submit(self : Editor) -> Unit {
  if self.on_submit is Some(cb) {
    cb(self.text)
  }
  self.add_to_history(self.text)
  self.clear()
}

///|
fn Editor::history_prev(self : Editor) -> Unit {
  if self.history_index > 0 {
    self.history_index -= 1
    self.text = self.history[self.history_index]
    self.cursor = self.text.length()
    if self.on_change is Some(cb) {
      cb(self.text)
    }
  }
}

///|
fn Editor::history_next(self : Editor) -> Unit {
  if self.history_index < self.history.length() - 1 {
    self.history_index += 1
    self.text = self.history[self.history_index]
    self.cursor = self.text.length()
    if self.on_change is Some(cb) {
      cb(self.text)
    }
  } else if self.history_index == self.history.length() - 1 {
    self.history_index = self.history.length()
    self.text = ""
    self.cursor = 0
    if self.on_change is Some(cb) {
      cb(self.text)
    }
  }
}
