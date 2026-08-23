///|
pub async fn list_files(cwd? : StringView) -> Array[String] {
  let root = cwd.map(fn(value) { value.to_owned() }).unwrap_or(".")
  let result = @trusted_host_process.run_git(root, ListFiles)
  if result.status() != 0 {
    fail("trusted git ls-files failed: \{result.stderr()}")
  }
  let output = result.stdout().trim()
  if output.is_empty() {
    return []
  }
  output.split("\n").map(line => line.to_owned()).collect()
}
