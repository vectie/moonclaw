///|
/// Attempts to acquire an exclusive lock on the given `path`. On success returns
/// the opened lock file. On failure returns the `DaemonInfo` of the currently
/// running daemon that holds the lock.
async fn acquire_lock(path : String) -> Result[@fs.File, DaemonInfo] {
  let file = @fs.open(
    path,
    mode=WriteOnly,
    create_mode=OpenOrCreate,
    permission=0o644,
  )
  @fsx.lock_file(file) catch {
    @errno.Errno(errno) if errno == @errno.eacces || errno == @errno.eagain => {
      file.close()
      let file = @fs.open(path, mode=ReadOnly)
      let pid = @fsx.get_lock_owner(file) catch {
        error => {
          file.close()
          raise error
        }
      }
      guard pid is Some(_) else {
        file.close()
        // Lock file is not locked by any process; lock again
        let file = @fs.open(path, mode=WriteOnly)
        @fsx.lock_file(file)
        return Ok(file)
      }
      defer file.close()
      let mut json : Json? = None
      while json is None {
        try {
          json = Some(file.read_all().text() |> @json.parse())
        } catch {
          error =>
            if @async.is_being_cancelled() {
              raise error
            } else {
              @async.sleep(500)
              continue
            }
        }
      }
      let json = match json {
        Some(json) => json
        None => fail("unreachable")
      }
      let info : DaemonInfo = @json.from_json(json)
      return Err(info)
    }
    error => {
      file.close()
      raise error
    }
  }
  Ok(file)
}
