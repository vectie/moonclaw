///|
pub async fn clone(
  url : String,
  to~ : StringView,
  cwd? : StringView,
  depth? : Int,
) -> Unit {
  if depth is Some(d) {
    guard d > 0 else { fail("depth must be a positive integer") }
  }
  ignore(url)
  ignore(to)
  ignore(cwd)
  fail("ExecutionSandbox grant required: direct git clone is disabled")
}

///|
pub async fn init_(path : String) -> Unit {
  let result = @trusted_host_process.run_git(path, Init)
  if result.status() != 0 {
    fail("trusted git init failed: \{result.stderr()}")
  }
}

///|
pub async fn commit(
  message : StringView,
  files : Array[StringView],
  cwd? : StringView,
) -> Unit {
  let root = cwd.map(fn(value) { value.to_owned() }).unwrap_or(".")
  let owned_files = files.map(fn(value) { value.to_owned() })
  let add_result = @trusted_host_process.run_git(root, AddFiles(owned_files))
  if add_result.status() != 0 {
    fail("trusted git add failed: \{add_result.stderr()}")
  }
  let commit_result = @trusted_host_process.run_git(
    root,
    Commit(message.to_owned()),
  )
  if commit_result.status() != 0 {
    fail("trusted git commit failed: \{commit_result.stderr()}")
  }
}

///|
pub async fn generate_git_diff(
  original~ : String,
  modified~ : String,
  line_number? : Bool = false,
) -> String {
  @fsx.with_temporary_directory("moonclaw-git-diff-XXXXXXX", tmpdir => {
    let original_path = @pathx.join(tmpdir, "original")
    @fsx.write_to_file(original_path, original)
    let modified_path = @pathx.join(tmpdir, "modified")
    @fsx.write_to_file(modified_path, modified)
    let result = @trusted_host_process.run_git(
      tmpdir,
      DiffNoIndex(original="original", modified="modified"),
    )
    if result.status() != 0 && result.status() != 1 {
      fail("trusted git diff failed: \{result.stderr()}")
    }
    let output = result.stdout().trim().to_owned()
    if line_number {
      add_line_number_to_diff(output)
    } else {
      output
    }
  })
}
