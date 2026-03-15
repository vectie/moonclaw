///|
async test "capture_successful_run_memories stores run summary and report artifacts" {
  @fsx.with_temporary_directory("job-memory-capture-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let store = SystemStore::new(root~)
    let definition = JobDefinition::{
      id: "job.proposal.1",
      kind: "job.proposal.research",
      enabled: true,
      config: {
        "workspace": dir,
        "family": "research",
        "template": "research.topic_watch",
        "notify": {
          "channel": "feishu",
          "account_id": "default",
          "to": "oc_chat_123",
          "thread_id": "om_thread_1",
        },
      },
      schedule: None,
      retry_policy: None,
      workflow_id: Some("workflow-1"),
      created_at: 10,
      updated_at: 10,
      tags: ["research", "watch"],
    }
    let run = JobRun::{
      id: "run-1",
      job_id: definition.id,
      trigger: TriggerSource::Manual,
      parent_run_id: None,
      parent_step_id: None,
      depth: 0,
      workspace_dir: Some(dir),
      status: RunStatus::Succeeded,
      attempt: 1,
      retry_of: None,
      started_at: Some(20),
      completed_at: Some(30),
      summary: Some("Captured daily VLA review summary."),
      error: None,
    }
    store.save_definition(definition)
    store.save_run(run)
    let artifacts = ArtifactStore::new(store~)
    let report = artifacts.write(
      ArtifactWriteRequest::new(
        run_id=run.id,
        job_id=definition.id,
        artifact_type="research.topic.report",
        content="The strongest paper improves action-conditioned evaluation and benchmark coverage.",
        content_type="text/plain",
        file_name=Some("report.txt"),
        scope=["jobs", "proposal:1", "research"],
      ),
      "artifact-1",
      40,
    )

    let saved = capture_successful_run_memories(store, definition, run, 50)

    inspect(saved.length(), content="2")
    inspect(saved[0].workspace.unwrap_or(""), content=dir)
    inspect(saved[0].channel_id.unwrap_or(""), content="feishu")
    inspect(saved[1].source_artifact_id.unwrap_or(""), content=report.id)
    inspect(saved[1].scope.contains("research"), content="true")
    inspect(
      store
      .get_memory("memory.run.run-1.summary")
      .map(fn(memory) {
        memory.content.contains("Captured daily VLA review summary.")
      })
      .unwrap_or(false),
      content="true",
    )
    inspect(
      store
      .get_memory("memory.run.run-1.artifact.artifact-1")
      .map(fn(memory) {
        memory.content.contains("action-conditioned evaluation")
      })
      .unwrap_or(false),
      content="true",
    )
  })
}
