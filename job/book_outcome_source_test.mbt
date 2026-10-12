///|
async test "public Book source API refuses incomplete run without modifying retained output" {
  @fsx.with_temporary_directory("claw-book-public-XXXXXX", root => {
    let store = @job.SystemStore::new(root~)
    let artifacts = @job.ArtifactStore::new(store~)
    let record = artifacts.write(
      @job.ArtifactWriteRequest::new(
        run_id="unrecorded-run",
        job_id="job",
        artifact_type="text",
        content="original text",
      ),
      "artifact",
      1,
    )
    try
      artifacts.freeze_book_outcome_source("unrecorded-run", [record.id])
    catch {
      error => assert_true(error.to_string().contains("run is unavailable"))
    } noraise {
      _ => fail("No completion should be invented")
    }
    assert_eq(artifacts.read_text(record.id), Some("original text"))
    assert_eq(store.list_runs().length(), 0)
    assert_eq(store.list_artifacts().length(), 1)
  })
}
