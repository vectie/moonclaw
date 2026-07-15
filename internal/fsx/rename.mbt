///|
#borrow(source, destination)
extern "c" fn fs_rename(source : Bytes, destination : Bytes) -> Int = "moonbit_moonclaw_fs_rename"

///|
/// Atomically rename a file-system entry when source and destination share a
/// file system. On failure this raises the platform errno.
pub fn rename(source : StringView, destination : StringView) -> Unit raise {
  let result = fs_rename(
    @encoding/utf8.encode(source),
    @encoding/utf8.encode(destination),
  )
  if result != 0 {
    raise @errno.Errno(result)
  }
}
