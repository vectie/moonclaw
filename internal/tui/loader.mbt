///|
pub(all) struct Loader {
  frames : Array[String]
  mut current : Int
  mut message : String
  mut running : Bool
  style : TextStyle
}

///|
pub fn Loader::new() -> Loader {
  Loader::{
    frames: [
      "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏",
    ],
    current: 0,
    message: "",
    running: false,
    style: TextStyle::default(),
  }
}

///|
pub fn Loader::with_frames(frames : Array[String]) -> Loader {
  Loader::{
    frames,
    current: 0,
    message: "",
    running: false,
    style: TextStyle::default(),
  }
}

///|
pub fn Loader::with_message(message : String) -> Loader {
  Loader::{
    frames: [
      "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏",
    ],
    current: 0,
    message,
    running: false,
    style: TextStyle::default(),
  }
}

///|
pub fn Loader::set_message(self : Loader, message : String) -> Unit {
  self.message = message
}

///|
pub fn Loader::message(self : Loader) -> String {
  self.message
}

///|
pub fn Loader::start(self : Loader) -> Unit {
  self.running = true
}

///|
pub fn Loader::stop(self : Loader) -> Unit {
  self.running = false
}

///|
pub fn Loader::is_running(self : Loader) -> Bool {
  self.running
}

///|
pub fn Loader::tick(self : Loader) -> Unit {
  self.current = (self.current + 1) % self.frames.length()
}

///|
pub fn Loader::get_preferred_height(_self : Loader, _width : Int) -> Int {
  1
}

///|
pub fn Loader::render(
  self : Loader,
  output : RenderOutput,
  x : Int,
  y : Int,
  _width : Int,
  _height : Int,
) -> Unit {
  output.write(cursor_to(x, y))
  output.write(ClearLineRight)
  if self.running {
    let frame = self.frames[self.current]
    output.write(colorize(frame, Color::BrightCyan))
    output.write(" ")
    output.write(dim(self.message))
  } else {
    output.write(dim(self.message))
  }
  self.tick()
}

///|
pub fn Loader::handle_key(_self : Loader, _key : Key) -> Bool {
  false
}
