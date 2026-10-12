///|
async test "artifact byte reads preserve NUL non UTF8 empty files and restart ownership" {
  @fsx.with_temporary_directory("artifact-byte-read-XXXXXX", root => {
    let store = SystemStore::new(root~)
    let artifact = ArtifactStore::new(store~).write(
      recovery_request("placeholder"),
      "exact-a",
      100,
    )
    let bytes = b"\x00\xff\x80\xc0\x00\n"
    @fs.write_file(artifact.path, bytes)
    let reopened = SystemStore::new(root~)
    reopened.load()
    let reader = ArtifactStore::new(store=reopened)
    assert_eq(reader.read_bytes("run-1", artifact.id), Some(bytes))
    assert_eq(reader.read_bytes("wrong-run", artifact.id), None)
    assert_eq(reader.read_bytes("run-1", "wrong-id"), None)
    @fs.write_file(artifact.path, b"")
    assert_eq(reader.read_bytes("run-1", artifact.id), Some(b""))
    @fs.remove(artifact.path)
    assert_eq(reader.read_bytes("run-1", artifact.id), None)
    assert_eq(reader.get(artifact.id).unwrap().path, artifact.path)
    // Sparse large fixture proves the limit without allocating a large buffer.
    let large = @fs.create(artifact.path)
    large.write_at(b"x", position=67108864L)
    large.close()
    try reader.read_bytes("run-1", artifact.id) catch {
      error => assert_true(error.to_string().contains("64 MiB"))
    } noraise {
      _ => fail("Oversize download must be refused")
    }
  })
}
