///|
async test "confined reader rejects final parent and broken symlinks" {
  let root = @fs.realpath(@fs.tmpdir(prefix="book-resource-"))
  @fs.mkdir(root + "/safe")
  @fs.write_file(root + "/safe/value.json", "safe", create_mode=CreateNew)
  @fs.write_file(root + "/outside.json", "outside", create_mode=CreateNew)
  assert_eq(read_resource(root + "/safe/value.json"), Some("safe"))
  assert_eq(read_resource(root + "/safe/absent.json"), None)
  @fs.symlink(root + "/safe/link.json", target=root + "/outside.json")
  @fs.symlink(root + "/alias", target=root + "/safe")
  @fs.symlink(root + "/safe/broken.json", target=root + "/missing")
  for
    path in [
      root + "/safe/link.json",
      root + "/alias/value.json",
      root + "/safe/broken.json",
    ] {
    assert_true(
      (Ok(read_resource(path)) catch { error => Err(error) }) is Err(_),
    )
    assert_true(
      (Ok(storage_file(path, create=true)) catch { error => Err(error) })
      is Err(_),
    )
  }
}

///|
async test "confined resource reader rejects files exceeding its explicit 16 MiB bound" {
  let root = @fs.realpath(@fs.tmpdir(prefix="book-resource-bound-"))
  let file = storage_file(root + "/new/nested/oversized", create=true).unwrap()
  defer file.close()
  file.write_at(b"x", position=16_777_216L)
  file.sync()
  assert_true(
    (Ok(read_resource(root + "/new/nested/oversized")) catch {
      error => Err(error)
    })
    is Err(_),
  )
}

///|
async test "resource and storage descriptors remain pinned across pathname replacement" {
  let root = @fs.realpath(@fs.tmpdir(prefix="book-pinned-fd-"))
  @fs.write_file(root + "/original", "original", create_mode=CreateNew)
  @fs.write_file(root + "/outside", "outside", create_mode=CreateNew)
  let path = @utf8.encode(root + "/original")
  let fd = resource_open(path, path.length())
  assert_true(fd >= 0)
  defer resource_close(fd)
  @fs.rename(root + "/original", root + "/retained")
  @fs.symlink(root + "/original", target=root + "/outside")
  let status = Ref(0)
  assert_eq(@utf8.decode(resource_read(fd, status)), "original")
  assert_eq(status.val, 0)
  let file = storage_file(root + "/retained").unwrap()
  defer file.close()
  file.lock(Exclusive)
  defer file.unlock()
  @fs.rename(root + "/retained", root + "/retained-again")
  @fs.symlink(root + "/retained", target=root + "/outside")
  file.write_at(b"pinned!!", position=0L)
  file.sync()
  assert_eq(@fs.read_file(root + "/outside").text(), "outside")
  assert_eq(@fs.read_file(root + "/retained-again").text(), "pinned!!")
}
