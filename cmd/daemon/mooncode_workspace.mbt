///|
/// Resolve new descendants through their nearest existing parent. A dangling
/// symlink is not a new file. Only ENOENT permits walking up the path.
async fn mooncode_workspace_canonical_path(path : String) -> String {
  @fsx.resolve(path) catch {
    @os_error.OSError(_) as error if error.is_ENOENT() => {
      let symlink = (@fs.kind(path, follow_symlink=false) is SymLink) catch {
        @os_error.OSError(_) as error if error.is_ENOENT() => false
        error => raise error
      }
      if symlink {
        fail("dangling workspace symlink: \{path}")
      }
      let parent = @pathx.dirname(path)
      guard parent != path else { raise error }
      mooncode_workspace_canonical_path(parent.to_owned()) +
      "/" +
      @pathx.basename(path).to_owned()
    }
    error => raise error
  }
}

///|
async fn mooncode_workspace_path(book_root : String, path : String) -> Json {
  let root = @fsx.resolve(book_root) catch {
    error =>
      return { "ok": false, "message": "invalid workspace root: \{error}" }
  }
  let raw = if @pathx.is_absolute(path) { path } else { book_root + "/" + path }
  let absolute = mooncode_workspace_canonical_path(raw) catch {
    error =>
      return { "ok": false, "message": "invalid workspace path: \{error}" }
  }
  mooncode_resolve_book_path(root, absolute)
}

///|
/// A stable lock file survives target replacement and is shared by sessions.
/// Only the touched resource waits; unrelated files do not serialize.
async fn mooncode_workspace_file_lock(
  root : String,
  absolute : String,
) -> @fs.File {
  let key = @crypto.bytes_to_hex_string(
    @crypto.sha256(@encoding/utf8.encode(absolute).to_fixedarray()),
  )
  let path = @moonsuite.product_artifact_for_workspace_root(
    root,
    "moonclaw",
    "mooncode/workspace-locks/\{key}.lock",
  )
  @fsx.make_directory(@pathx.dirname(path), recursive=true, exists_ok=true)
  let file = @fs.open(path, mode=ReadWrite, create_mode=OpenOrCreate)
  errdefer file.close()
  file.lock(Exclusive)
  file
}

///|
/// Compare at the final write boundary. Staging preserves the original file on
/// failed writes. The final comparison and rename do not yield to other tasks.
async fn mooncode_workspace_replace(
  root : String,
  absolute : String,
  expected : String?,
  content : String?,
) -> Unit {
  let root = @fsx.resolve(root)
  let lock = mooncode_workspace_file_lock(root, absolute)
  defer lock.close()
  defer lock.unlock()
  let resolved = mooncode_workspace_path(root, absolute)
  guard mooncode_json_bool(resolved, "ok", default=false) &&
    mooncode_json_string(resolved, "absolute_path", default="") == absolute else {
    fail("workspace resource identity changed: \{absolute}")
  }
  let current = @book_runtime.read_resource(absolute)
  guard current == expected else {
    fail("workspace file changed before write: \{absolute}")
  }
  if content == expected {
    return
  }
  guard content is Some(content) else {
    @fsx.remove(absolute)
    return
  }
  @fsx.make_directory(@pathx.dirname(absolute), recursive=true, exists_ok=true)
  let temporary = absolute +
    ".mooncode-" +
    @crypto.bytes_to_hex_string(@rand.bytes(16))
  defer (if @fsx.exists(temporary) { @fsx.remove(temporary) })
  let permission = if current is Some(_) {
    @moonclaw_fsx.stat(absolute).mode()
  } else {
    0o644
  }
  @fs.write_file(temporary, content, create_mode=CreateNew, permission~)
  @fs.chmod(temporary, permission)
  guard @book_runtime.read_resource(absolute) == expected else {
    fail("workspace file changed before commit: \{absolute}")
  }
  @fsx.atomic_rename(temporary, absolute)
}
