///|
#borrow(path)
extern "c" fn private_control_path(
  path : Bytes,
  length : Int32,
  directory : Int32,
) -> Bool = "moonclaw_private_control_path"

///|
fn check_private_control_path(path : String, directory : Bool) -> Bool {
  let bytes = @utf8.encode(path)
  private_control_path(bytes, bytes.length(), if directory { 1 } else { 0 })
}
