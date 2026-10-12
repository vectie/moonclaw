///|
async test "public artifact byte API is read only and run bound" {
  @fsx.with_temporary_directory("artifact-public-read-XXXXXX", root => {
    let store = @job.SystemStore::new(root~)
    let artifacts = @job.ArtifactStore::new(store~)
    let record = artifacts.write(
      @job.ArtifactWriteRequest::new(
        run_id="public-run",
        job_id="public-job",
        artifact_type="text",
        content="hello\u0000世界",
      ),
      "public-artifact",
      1,
    )
    assert_eq(
      artifacts.read_bytes("public-run", record.id),
      Some(@encoding/utf8.encode("hello\u0000世界")),
    )
    assert_eq(artifacts.read_bytes("other-run", record.id), None)
    assert_eq(artifacts.list().length(), 1)
  })
}
