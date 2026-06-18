///|
test "windows_size" {
  json_inspect(
    try @tty.window_size() catch {
      _ => true
    } noraise {
      _ => false
    },
    content=true,
  )
}
