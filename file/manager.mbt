///|
pub struct Manager {
  cwd : String
  access : Map[String, Int64]
}

///|
pub fn manager(cwd~ : String) -> Manager {
  { cwd: @pathx.normalize(cwd), access: {} }
}

///|
pub fn Manager::resolve_scoped(self : Manager, path : String) -> String? {
  let candidate = @pathx.normalize(
    if @pathx.is_absolute(path) {
      path
    } else {
      @pathx.join(self.cwd, path)
    },
  )
  if candidate == self.cwd || candidate.has_prefix(self.cwd + "/") {
    Some(candidate)
  } else {
    None
  }
}
