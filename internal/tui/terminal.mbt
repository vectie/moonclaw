///|
pub(all) struct Terminal {
  input : @stdio.Input
  output : @stdio.Output
  mut width : Int
  mut height : Int
  mut cursor_x : Int
  mut cursor_y : Int
  mut running : Bool
  mut in_alt_screen : Bool
}

///|
pub fn Terminal::new() -> Terminal raise {
  let size = @tty.window_size()
  Terminal::{
    input: @stdio.stdin,
    output: @stdio.stdout,
    width: size.col,
    height: size.row,
    cursor_x: 0,
    cursor_y: 0,
    running: false,
    in_alt_screen: false,
  }
}

///|
pub fn Terminal::with_io(
  input~ : @stdio.Input,
  output~ : @stdio.Output,
) -> Terminal raise {
  let size = @tty.window_size()
  Terminal::{
    input,
    output,
    width: size.col,
    height: size.row,
    cursor_x: 0,
    cursor_y: 0,
    running: false,
    in_alt_screen: false,
  }
}

///|
pub async fn Terminal::start(self : Terminal) -> Unit {
  @tty.set_raw_mode(self.input.fd())
  self.running = true
  self.enter_alt_screen()
  self.hide_cursor()
  self.clear_screen()
}

///|
pub async fn Terminal::stop(self : Terminal) -> Unit {
  self.show_cursor()
  self.exit_alt_screen()
  self.running = false
}

///|
pub async fn Terminal::enter_alt_screen(self : Terminal) -> Unit {
  self.output.write(AltScreen)
  self.in_alt_screen = true
}

///|
pub async fn Terminal::exit_alt_screen(self : Terminal) -> Unit {
  self.output.write(MainScreen)
  self.in_alt_screen = false
}

///|
pub async fn Terminal::clear_screen(self : Terminal) -> Unit {
  self.output.write(ClearScreen)
  self.output.write(CursorHome)
  self.cursor_x = 0
  self.cursor_y = 0
}

///|
pub async fn Terminal::clear_line(self : Terminal) -> Unit {
  self.output.write(ClearLine)
}

///|
pub async fn Terminal::hide_cursor(self : Terminal) -> Unit {
  self.output.write(CursorHide)
}

///|
pub async fn Terminal::show_cursor(self : Terminal) -> Unit {
  self.output.write(CursorShow)
}

///|
pub async fn Terminal::move_to(self : Terminal, col : Int, row : Int) -> Unit {
  self.output.write(cursor_to(col, row))
  self.cursor_x = col
  self.cursor_y = row
}

///|
pub async fn Terminal::move_to_col(self : Terminal, col : Int) -> Unit {
  self.output.write(cursor_to_col(col))
  self.cursor_x = col
}

///|
pub async fn Terminal::move_up(self : Terminal, n : Int) -> Unit {
  self.output.write(cursor_up(n))
  self.cursor_y = self.cursor_y - n
}

///|
pub async fn Terminal::move_down(self : Terminal, n : Int) -> Unit {
  self.output.write(cursor_down(n))
  self.cursor_y = self.cursor_y + n
}

///|
pub async fn Terminal::move_left(self : Terminal, n : Int) -> Unit {
  self.output.write(cursor_left(n))
  self.cursor_x = self.cursor_x - n
}

///|
pub async fn Terminal::move_right(self : Terminal, n : Int) -> Unit {
  self.output.write(cursor_right(n))
  self.cursor_x = self.cursor_x + n
}

///|
pub async fn Terminal::write(self : Terminal, text : String) -> Unit {
  self.output.write(text)
}

///|
pub async fn Terminal::write_bytes(self : Terminal, bytes : Bytes) -> Unit {
  self.output.write(bytes)
}

///|
pub async fn Terminal::write_line(self : Terminal, text : String) -> Unit {
  self.output.write("\{text}\n")
  self.cursor_y += 1
  self.cursor_x = 0
}

///|
pub async fn Terminal::write_at(
  self : Terminal,
  col : Int,
  row : Int,
  text : String,
) -> Unit {
  self.move_to(col, row)
  self.write(text)
}

///|
pub async fn Terminal::flush(self : Terminal) -> Unit {
  self.output.write("")
}

///|
pub fn Terminal::size(self : Terminal) -> (Int, Int) {
  (self.width, self.height)
}

///|
pub fn Terminal::update_size(self : Terminal) -> Unit raise {
  let size = @tty.window_size()
  self.width = size.col
  self.height = size.row
}

///|
pub fn Terminal::width(self : Terminal) -> Int {
  self.width
}

///|
pub fn Terminal::height(self : Terminal) -> Int {
  self.height
}

///|
pub fn Terminal::is_running(self : Terminal) -> Bool {
  self.running
}

///|
pub async fn Terminal::enable_bracketed_paste(self : Terminal) -> Unit {
  self.output.write(EnableBracketedPaste)
}

///|
pub async fn Terminal::disable_bracketed_paste(self : Terminal) -> Unit {
  self.output.write(DisableBracketedPaste)
}

///|
pub async fn Terminal::save_cursor(self : Terminal) -> Unit {
  self.output.write(CursorSave)
}

///|
pub async fn Terminal::restore_cursor(self : Terminal) -> Unit {
  self.output.write(CursorRestore)
}

///|
pub async fn Terminal::clear_screen_down(self : Terminal) -> Unit {
  self.output.write(ClearScreenDown)
}
