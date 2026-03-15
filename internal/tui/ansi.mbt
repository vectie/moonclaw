///|
pub(all) enum Color {
  Black
  Red
  Green
  Yellow
  Blue
  Magenta
  Cyan
  White
  BrightBlack
  BrightRed
  BrightGreen
  BrightYellow
  BrightBlue
  BrightMagenta
  BrightCyan
  BrightWhite
  Rgb(Int, Int, Int)
}

///|
pub fn Color::fg(self : Color) -> String {
  match self {
    Black => "\u001b[30m"
    Red => "\u001b[31m"
    Green => "\u001b[32m"
    Yellow => "\u001b[33m"
    Blue => "\u001b[34m"
    Magenta => "\u001b[35m"
    Cyan => "\u001b[36m"
    White => "\u001b[37m"
    BrightBlack => "\u001b[90m"
    BrightRed => "\u001b[91m"
    BrightGreen => "\u001b[92m"
    BrightYellow => "\u001b[93m"
    BrightBlue => "\u001b[94m"
    BrightMagenta => "\u001b[95m"
    BrightCyan => "\u001b[96m"
    BrightWhite => "\u001b[97m"
    Rgb(r, g, b) => "\u001b[38;2;\{r};\{g};\{b}m"
  }
}

///|
pub fn Color::bg(self : Color) -> String {
  match self {
    Black => "\u001b[40m"
    Red => "\u001b[41m"
    Green => "\u001b[42m"
    Yellow => "\u001b[43m"
    Blue => "\u001b[44m"
    Magenta => "\u001b[45m"
    Cyan => "\u001b[46m"
    White => "\u001b[47m"
    BrightBlack => "\u001b[100m"
    BrightRed => "\u001b[101m"
    BrightGreen => "\u001b[102m"
    BrightYellow => "\u001b[103m"
    BrightBlue => "\u001b[104m"
    BrightMagenta => "\u001b[105m"
    BrightCyan => "\u001b[106m"
    BrightWhite => "\u001b[107m"
    Rgb(r, g, b) => "\u001b[48;2;\{r};\{g};\{b}m"
  }
}

///|
pub enum StyleCode {
  StyleBold
}

///|
pub fn StyleCode::code(self : StyleCode) -> String {
  match self {
    StyleBold => "\u001b[1m"
  }
}

///|
pub const Reset : String = "\u001b[0m"

///|
pub const Bold : String = "\u001b[1m"

///|
pub const Dim : String = "\u001b[2m"

///|
pub const Italic : String = "\u001b[3m"

///|
pub const Underline : String = "\u001b[4m"

///|
pub const Blink : String = "\u001b[5m"

///|
pub const Reverse : String = "\u001b[7m"

///|
pub const Hidden : String = "\u001b[8m"

///|
pub const Strikethrough : String = "\u001b[9m"

///|
pub const CursorHome : String = "\u001b[H"

///|
pub const CursorUp : String = "\u001b[A"

///|
pub const CursorDown : String = "\u001b[B"

///|
pub const CursorRight : String = "\u001b[C"

///|
pub const CursorLeft : String = "\u001b[D"

///|
pub const CursorSave : String = "\u001b[s"

///|
pub const CursorRestore : String = "\u001b[u"

///|
pub const CursorHide : String = "\u001b[?25l"

///|
pub const CursorShow : String = "\u001b[?25h"

///|
pub const ClearScreen : String = "\u001b[2J"

///|
pub const ClearScreenDown : String = "\u001b[J"

///|
pub const ClearScreenUp : String = "\u001b[1J"

///|
pub const ClearLine : String = "\u001b[2K"

///|
pub const ClearLineRight : String = "\u001b[K"

///|
pub const ClearLineLeft : String = "\u001b[1K"

///|
pub const AltScreen : String = "\u001b[?1049h"

///|
pub const MainScreen : String = "\u001b[?1049l"

///|
pub const EnableMouse : String = "\u001b[?1000h"

///|
pub const DisableMouse : String = "\u001b[?1000l"

///|
pub const EnableMouseDrag : String = "\u001b[?1002h"

///|
pub const DisableMouseDrag : String = "\u001b[?1002l"

///|
pub const EnableMouseMove : String = "\u001b[?1003h"

///|
pub const DisableMouseMove : String = "\u001b[?1003l"

///|
pub const EnableBracketedPaste : String = "\u001b[?2004h"

///|
pub const DisableBracketedPaste : String = "\u001b[?2004l"

///|
pub fn cursor_to(col : Int, row : Int) -> String {
  "\u001b[\{row + 1};\{col + 1}H"
}

///|
pub fn cursor_to_col(col : Int) -> String {
  "\u001b[\{col + 1}G"
}

///|
pub fn cursor_up(n : Int) -> String {
  if n <= 0 {
    ""
  } else {
    "\u001b[\{n}A"
  }
}

///|
pub fn cursor_down(n : Int) -> String {
  if n <= 0 {
    ""
  } else {
    "\u001b[\{n}B"
  }
}

///|
pub fn cursor_right(n : Int) -> String {
  if n <= 0 {
    ""
  } else {
    "\u001b[\{n}C"
  }
}

///|
pub fn cursor_left(n : Int) -> String {
  if n <= 0 {
    ""
  } else {
    "\u001b[\{n}D"
  }
}

///|
pub fn scroll_up(n : Int) -> String {
  if n <= 0 {
    ""
  } else {
    "\u001b[\{n}S"
  }
}

///|
pub fn scroll_down(n : Int) -> String {
  if n <= 0 {
    ""
  } else {
    "\u001b[\{n}T"
  }
}

///|
pub fn erase_lines(n : Int) -> String {
  let mut result = ""
  for _ in 0..<n {
    result = "\{result}\{ClearLine}\n"
  }
  "\{result}\{cursor_up(n)}"
}

///|
pub fn styled(
  text : String,
  fg? : Color,
  bg? : Color,
  styles? : Array[StyleCode],
) -> String {
  let mut result = ""
  if fg is Some(c) {
    result = "\{result}\{c.fg()}"
  }
  if bg is Some(c) {
    result = "\{result}\{c.bg()}"
  }
  if styles is Some(s) {
    for style in s {
      result = "\{result}\{style.code()}"
    }
  }
  "\{result}\{text}\{Reset}"
}

///|
pub fn colorize(text : String, color : Color) -> String {
  "\{color.fg()}\{text}\{Reset}"
}

///|
pub fn bold(text : String) -> String {
  "\{Bold}\{text}\{Reset}"
}

///|
pub fn dim(text : String) -> String {
  "\{Dim}\{text}\{Reset}"
}

///|
pub fn italic(text : String) -> String {
  "\{Italic}\{text}\{Reset}"
}

///|
pub fn underline(text : String) -> String {
  "\{Underline}\{text}\{Reset}"
}

///|
pub fn visible_width(text : String) -> Int {
  let mut width = 0
  let mut in_escape = false
  for c in text {
    if in_escape {
      let code = c.to_int()
      if code >= 0x40 && code <= 0x7E {
        in_escape = false
      }
      continue
    }
    if c == '\u{1b}' {
      in_escape = true
      continue
    }
    width += @unicode/width.char(c).unwrap_or(1)
  }
  width
}

///|
pub fn truncate_styled(text : String, max_width : Int) -> String {
  if max_width <= 0 {
    return ""
  }
  let mut width = 0
  let mut in_escape = false
  let mut result = ""
  for c in text {
    if in_escape {
      result = "\{result}\{c}"
      let code = c.to_int()
      if code >= 0x40 && code <= 0x7E {
        in_escape = false
      }
      continue
    }
    if c == '\u{1b}' {
      in_escape = true
      result = "\{result}\{c}"
      continue
    }
    let c_width = @unicode/width.char(c).unwrap_or(1)
    if width + c_width > max_width {
      break
    }
    result = "\{result}\{c}"
    width += c_width
  }
  "\{result}\{Reset}"
}
