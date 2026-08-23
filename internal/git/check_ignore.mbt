///|
pub async fn check_ignore(
  paths : Array[StringView],
  cwd? : StringView,
) -> Array[String] {
  if paths.is_empty() {
    return []
  }
  let root = cwd.map(fn(value) { value.to_owned() }).unwrap_or(".")
  let normalized : Array[String] = []
  for path in paths {
    let owned = path.to_owned()
    normalized.push(
      if @pathx.is_absolute(owned) {
        @pathx.relative(root, owned)
      } else {
        owned
      },
    )
  }
  let result = @trusted_host_process.run_git(root, CheckIgnore(normalized))
  if result.status() == 1 {
    return []
  }
  if result.status() != 0 {
    fail("trusted git check-ignore failed: \{result.stderr()}")
  }
  let output = result.stdout().trim()
  if output.is_empty() {
    return []
  }
  let ignored : Array[String] = []
  for line in output.split("\n") {
    let relative = line.to_owned()
    let mut restored = relative
    for index, normalized_path in normalized {
      if normalized_path == relative {
        restored = paths[index].to_owned()
        break
      }
    }
    ignored.push(restored)
  }
  ignored
}

///|
pub async fn is_ignored(path : StringView, cwd? : StringView) -> Bool {
  let ignored_paths = check_ignore([path], cwd?)
  return ignored_paths.contains(path.to_owned())
}
