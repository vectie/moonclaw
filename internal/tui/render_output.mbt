///|
pub(all) struct RenderOutput {
  buffer : @buffer.Buffer
}

///|
pub fn RenderOutput::new() -> RenderOutput {
  RenderOutput::{ buffer: @buffer.new() }
}

///|
pub fn RenderOutput::write(self : RenderOutput, text : String) -> Unit {
  self.buffer.write_bytes(@encoding/utf8.encode(text))
}

///|
pub fn RenderOutput::write_bytes(self : RenderOutput, bytes : Bytes) -> Unit {
  self.buffer.write_bytes(bytes)
}

///|
pub fn RenderOutput::to_bytes(self : RenderOutput) -> Bytes {
  self.buffer.to_bytes()
}
