///|
#borrow(path)
extern "c" fn resource_open(path : Bytes, length : Int32) -> Int32 = "moonclaw_book_resource_open"

///|
#borrow(status)
extern "c" fn resource_read(fd : Int32, status : Ref[Int32]) -> Bytes = "moonclaw_book_resource_read"

///|
extern "c" fn resource_close(fd : Int32) -> Unit = "moonclaw_book_resource_close"

///|
#borrow(path)
extern "c" fn storage_open(
  path : Bytes,
  length : Int32,
  create : Bool,
) -> Int32 = "moonclaw_book_storage_open"

///|
extern "c" fn same_file(left : Int32, right : Int32) -> Bool = "moonclaw_book_same_file"

///|
/// Duplicate our owned pinned descriptor through the supported native file API.
pub async fn storage_file(path : String, create~ : Bool = false) -> @fs.File? {
  let bytes = @utf8.encode(path)
  let fd = storage_open(bytes, bytes.length(), create)
  if fd == -1 {
    return None
  }
  if fd < 0 {
    fail("Book session storage is not canonical")
  }
  defer resource_close(fd)
  let file = @fs.open("/dev/fd/" + fd.to_string(), mode=ReadWrite)
  guard same_file(fd, file.fd()) else {
    file.close()
    fail("Book session descriptor identity changed")
  }
  Some(file)
}

///|
/// Only fixed owner-derived Book-local/suite paths are supplied by callers.
/// Native open walks every component without symlink following; reads pin that fd.
pub fn read_resource(path : String) -> String? raise {
  let bytes = @utf8.encode(path)
  let fd = resource_open(bytes, bytes.length())
  if fd == -1 {
    return None
  }
  if fd < 0 {
    fail("Book resource path is unavailable or not canonical")
  }
  defer resource_close(fd)
  let status = Ref(0)
  let content = resource_read(fd, status)
  if status.val != 0 {
    fail("Book resource is invalid, changed, or exceeds 16 MiB")
  }
  Some(@utf8.decode(content))
}
