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
    Black => "\x1b[30m"
    Red => "\x1b[31m"
    Green => "\x1b[32m"
    Yellow => "\x1b[33m"
    Blue => "\x1b[34m"
    Magenta => "\x1b[35m"
    Cyan => "\x1b[36m"
    White => "\x1b[37m"
    BrightBlack => "\x1b[90m"
    BrightRed => "\x1b[91m"
    BrightGreen => "\x1b[92m"
    BrightYellow => "\x1b[93m"
    BrightBlue => "\x1b[94m"
    BrightMagenta => "\x1b[95m"
    BrightCyan => "\x1b[96m"
    BrightWhite => "\x1b[97m"
    Rgb(r, g, b) => "\x1b[38;2;\{r};\{g};\{b}m"
  }
}

///|
pub fn Color::bg(self : Color) -> String {
  match self {
    Black => "\x1b[40m"
    Red => "\x1b[41m"
    Green => "\x1b[42m"
    Yellow => "\x1b[43m"
    Blue => "\x1b[44m"
    Magenta => "\x1b[45m"
    Cyan => "\x1b[46m"
    White => "\x1b[47m"
    BrightBlack => "\x1b[100m"
    BrightRed => "\x1b[101m"
    BrightGreen => "\x1b[102m"
    BrightYellow => "\x1b[103m"
    BrightBlue => "\x1b[104m"
    BrightMagenta => "\x1b[105m"
    BrightCyan => "\x1b[106m"
    BrightWhite => "\x1b[107m"
    Rgb(r, g, b) => "\x1b[48;2;\{r};\{g};\{b}m"
  }
}

///|
pub enum StyleCode {
  StyleReset
  StyleBold
  StyleDim
  StyleItalic
  StyleUnderline
  StyleBlink
  StyleReverse
  StyleHidden
  StyleStrikethrough
}

///|
pub fn StyleCode::code(self : StyleCode) -> String {
  match self {
    StyleReset => "\x1b[0m"
    StyleBold => "\x1b[1m"
    StyleDim => "\x1b[2m"
    StyleItalic => "\x1b[3m"
    StyleUnderline => "\x1b[4m"
    StyleBlink => "\x1b[5m"
    StyleReverse => "\x1b[7m"
    StyleHidden => "\x1b[8m"
    StyleStrikethrough => "\x1b[9m"
  }
}

///|
pub const Reset : String = "\x1b[0m"

///|
pub const Bold : String = "\x1b[1m"

///|
pub const Dim : String = "\x1b[2m"

///|
pub const Italic : String = "\x1b[3m"

///|
pub const Underline : String = "\x1b[4m"

///|
pub const Blink : String = "\x1b[5m"

///|
pub const Reverse : String = "\x1b[7m"

///|
pub const Hidden : String = "\x1b[8m"

///|
pub const Strikethrough : String = "\x1b[9m"

///|
pub const CursorHome : String = "\x1b[H"

///|
pub const CursorUp : String = "\x1b[A"

///|
pub const CursorDown : String = "\x1b[B"

///|
pub const CursorRight : String = "\x1b[C"

///|
pub const CursorLeft : String = "\x1b[D"

///|
pub const CursorSave : String = "\x1b[s"

///|
pub const CursorRestore : String = "\x1b[u"

///|
pub const CursorHide : String = "\x1b[?25l"

///|
pub const CursorShow : String = "\x1b[?25h"

///|
pub const ClearScreen : String = "\x1b[2J"

///|
pub const ClearScreenDown : String = "\x1b[J"

///|
pub const ClearScreenUp : String = "\x1b[1J"

///|
pub const ClearLine : String = "\x1b[2K"

///|
pub const ClearLineRight : String = "\x1b[K"

///|
pub const ClearLineLeft : String = "\x1b[1K"

///|
pub const AltScreen : String = "\x1b[?1049h"

///|
pub const MainScreen : String = "\x1b[?1049l"

///|
pub const EnableMouse : String = "\x1b[?1000h"

///|
pub const DisableMouse : String = "\x1b[?1000l"

///|
pub const EnableMouseDrag : String = "\x1b[?1002h"

///|
pub const DisableMouseDrag : String = "\x1b[?1002l"

///|
pub const EnableMouseMove : String = "\x1b[?1003h"

///|
pub const DisableMouseMove : String = "\x1b[?1003l"

///|
pub const EnableBracketedPaste : String = "\x1b[?2004h"

///|
pub const DisableBracketedPaste : String = "\x1b[?2004l"

///|
pub fn cursor_to(col : Int, row : Int) -> String {
  "\x1b[\{row + 1};\{col + 1}H"
}

///|
pub fn cursor_to_col(col : Int) -> String {
  "\x1b[\{col + 1}G"
}

///|
pub fn cursor_up(n : Int) -> String {
  if n <= 0 {
    ""
  } else {
    "\x1b[\{n}A"
  }
}

///|
pub fn cursor_down(n : Int) -> String {
  if n <= 0 {
    ""
  } else {
    "\x1b[\{n}B"
  }
}

///|
pub fn cursor_right(n : Int) -> String {
  if n <= 0 {
    ""
  } else {
    "\x1b[\{n}C"
  }
}

///|
pub fn cursor_left(n : Int) -> String {
  if n <= 0 {
    ""
  } else {
    "\x1b[\{n}D"
  }
}

///|
pub fn scroll_up(n : Int) -> String {
  if n <= 0 {
    ""
  } else {
    "\x1b[\{n}S"
  }
}

///|
pub fn scroll_down(n : Int) -> String {
  if n <= 0 {
    ""
  } else {
    "\x1b[\{n}T"
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
