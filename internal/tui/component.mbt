///|
pub enum Key {
  Char(Char)
  Enter
  Backspace
  Delete
  Up
  Down
  Left
  Right
  Home
  End
  PageUp
  PageDown
  Tab
  ShiftTab
  Escape
  F1
  F2
  F3
  F4
  F5
  F6
  F7
  F8
  F9
  F10
  F11
  F12
  Ctrl(Char)
  Alt(Char)
  PasteStart
  PasteEnd
  Unknown
}

///|
pub fn Key::is_printable(self : Key) -> Bool {
  match self {
    Char(_) => true
    _ => false
  }
}

///|
pub fn Key::is_navigation(self : Key) -> Bool {
  match self {
    Up | Down | Left | Right | Home | End | PageUp | PageDown => true
    _ => false
  }
}

///|
pub fn Key::is_ctrl(self : Key) -> Bool {
  match self {
    Ctrl(_) => true
    _ => false
  }
}

///|
pub fn Key::is_alt(self : Key) -> Bool {
  match self {
    Alt(_) => true
    _ => false
  }
}

///|
pub fn Key::to_char(self : Key) -> Char? {
  match self {
    Char(c) => Some(c)
    Ctrl(c) => Some(c)
    Alt(c) => Some(c)
    _ => None
  }
}

///|
pub fn parse_key(bytes : BytesView) -> Key {
  match bytes {
    [b'\r' | b'\n', ..] => return Enter
    [b'\b' | 0x7f, ..] => return Backspace
    [b'\t', ..] => return Tab
    [0x1b, .. rest] =>
      match rest {
        [b'[', b'A', ..] => return Up
        [b'[', b'B', ..] => return Down
        [b'[', b'C', ..] => return Right
        [b'[', b'D', ..] => return Left
        [b'[', b'3', b'~', ..] => return Delete
        [b'[', b'H', ..] => return Home
        [b'[', b'F', ..] => return End
        [b'[', b'5', b'~', ..] => return PageUp
        [b'[', b'6', b'~', ..] => return PageDown
        [b'[', b'Z', ..] => return ShiftTab
        [b'[', b'1', b'1', b'~', ..] => return F1
        [b'[', b'1', b'2', b'~', ..] => return F2
        [b'[', b'1', b'3', b'~', ..] => return F3
        [b'[', b'1', b'4', b'~', ..] => return F4
        [b'[', b'1', b'5', b'~', ..] => return F5
        [b'[', b'1', b'7', b'~', ..] => return F6
        [b'[', b'1', b'8', b'~', ..] => return F7
        [b'[', b'1', b'9', b'~', ..] => return F8
        [b'[', b'2', b'0', b'~', ..] => return F9
        [b'[', b'2', b'1', b'~', ..] => return F10
        [b'[', b'2', b'3', b'~', ..] => return F11
        [b'[', b'2', b'4', b'~', ..] => return F12
        [b'[', b'2', b'0', b'0', b'~', ..] => return PasteStart
        [b'[', b'2', b'0', b'1', b'~', ..] => return PasteEnd
        [b'O', b'P', ..] => return F1
        [b'O', b'Q', ..] => return F2
        [b'O', b'R', ..] => return F3
        [b'O', b'S', ..] => return F4
        [c, ..] if c.to_int() >= 'a'.to_int() && c.to_int() <= 'z'.to_int() => {
          let ch = c.to_char()
          return Alt(ch)
        }
        [c, ..] if c.to_int() >= 'A'.to_int() && c.to_int() <= 'Z'.to_int() => {
          let ch = c.to_char()
          let lower = (ch.to_int() + 32).unsafe_to_char()
          return Alt(lower)
        }
        [] => return Escape
        _ => return Unknown
      }
    [c, ..] if c.to_int() >= 0x01 && c.to_int() <= 0x1a => {
      let ch = (c.to_int() + 96).unsafe_to_char()
      return Ctrl(ch)
    }
    [c, ..] if c.to_int() >= 0x20 && c.to_int() <= 0x7e =>
      return Char(c.to_char())
    [_, ..] => return Unknown
    [] => return Unknown
  }
}

///|
pub fn key_to_string(key : Key) -> String {
  match key {
    Char(c) => c.to_string()
    Enter => "Enter"
    Backspace => "Backspace"
    Delete => "Delete"
    Up => "Up"
    Down => "Down"
    Left => "Left"
    Right => "Right"
    Home => "Home"
    End => "End"
    PageUp => "PageUp"
    PageDown => "PageDown"
    Tab => "Tab"
    ShiftTab => "ShiftTab"
    Escape => "Escape"
    F1 => "F1"
    F2 => "F2"
    F3 => "F3"
    F4 => "F4"
    F5 => "F5"
    F6 => "F6"
    F7 => "F7"
    F8 => "F8"
    F9 => "F9"
    F10 => "F10"
    F11 => "F11"
    F12 => "F12"
    Ctrl(c) => "Ctrl+\{c}"
    Alt(c) => "Alt+\{c}"
    PasteStart => "PasteStart"
    PasteEnd => "PasteEnd"
    Unknown => "Unknown"
  }
}
