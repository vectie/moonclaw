///|
/// Read one retained artifact as bytes only when it belongs to the exact run.
/// Missing records, wrong owners and absent content return None. This does not
/// resolve logical keys, workspace paths, synthetic previews or Fort output refs.
pub async fn ArtifactStore::read_bytes(
  self : ArtifactStore,
  run_id : String,
  artifact_id : String,
) -> Bytes? {
  match self.store.get_artifact(artifact_id) {
    Some(artifact) if artifact.run_id == run_id => {
      if !@fsx.exists_as_file(artifact.path) {
        return None
      }
      let file = @fs.open(artifact.path, mode=ReadOnly)
      defer file.close()
      guard file.kind() is Regular else { return None }
      // Read the same open file descriptor that was sized, bounded before
      // allocation, and refuse a file that changes length during the read.
      let size = file.size()
      if size > 67108864L {
        fail("Artifact exceeds the 64 MiB download limit")
      }
      let bytes = file.read_exactly_at(size.to_int(), position=0L)
      if file.size() != size {
        fail("Artifact changed while downloading")
      }
      Some(bytes)
    }
    _ => None
  }
}
