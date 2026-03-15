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
    ['\r' | '\n', ..] => return Enter
    ['\b' | 0x7f, ..] => return Backspace
    ['\t', ..] => return Tab
    [0x1b, .. rest] =>
      match rest {
        ['[', 'A', ..] => return Up
        ['[', 'B', ..] => return Down
        ['[', 'C', ..] => return Right
        ['[', 'D', ..] => return Left
        ['[', '3', '~', ..] => return Delete
        ['[', 'H', ..] => return Home
        ['[', 'F', ..] => return End
        ['[', '5', '~', ..] => return PageUp
        ['[', '6', '~', ..] => return PageDown
        ['[', 'Z', ..] => return ShiftTab
        ['[', '1', '1', '~', ..] => return F1
        ['[', '1', '2', '~', ..] => return F2
        ['[', '1', '3', '~', ..] => return F3
        ['[', '1', '4', '~', ..] => return F4
        ['[', '1', '5', '~', ..] => return F5
        ['[', '1', '7', '~', ..] => return F6
        ['[', '1', '8', '~', ..] => return F7
        ['[', '1', '9', '~', ..] => return F8
        ['[', '2', '0', '~', ..] => return F9
        ['[', '2', '1', '~', ..] => return F10
        ['[', '2', '3', '~', ..] => return F11
        ['[', '2', '4', '~', ..] => return F12
        ['[', '2', '0', '0', '~', ..] => return PasteStart
        ['[', '2', '0', '1', '~', ..] => return PasteEnd
        ['O', 'P', ..] => return F1
        ['O', 'Q', ..] => return F2
        ['O', 'R', ..] => return F3
        ['O', 'S', ..] => return F4
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
