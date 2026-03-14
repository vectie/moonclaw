///|
fn chat_test_store(root : String) -> SystemStore {
  SystemStore::new(root~)
}

///|
async test "ChatService retrieves active artifacts and returns citations" {
  @fsx.with_temporary_directory("job-chat-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let store = chat_test_store(root)
    let artifacts = ArtifactStore::new(store~)
    ignore(
      artifacts.write(
        ArtifactWriteRequest::new(
          run_id="run-1",
          job_id="research.paper.analyze",
          artifact_type="paper.summary",
          logical_key=Some("paper:1"),
          scope=["research", "paper:1"],
          content="Diffusion transformers improve long-context planning for agents.",
        ),
        "artifact-1",
        100,
      ),
    )
    ignore(
      artifacts.write(
        ArtifactWriteRequest::new(
          run_id="run-2",
          job_id="research.paper.analyze",
          artifact_type="paper.summary",
          logical_key=Some("paper:2"),
          scope=["research", "paper:2"],
          content="Archived note about unrelated protein folding.",
        ),
        "artifact-2",
        200,
      ),
    )
    ignore(artifacts.archive("artifact-2", 300))
    store.save_memory(MemoryRecord::{
      id: "memory-1",
      kind: "note",
      title: Some("planning note"),
      content: "Agent planning should prefer long-context diffusion transformers.",
      metadata: {},
      tags: ["research"],
      scope: ["research"],
      workspace: None,
      agent_id: None,
      channel_id: None,
      account_id: None,
      recipient: None,
      thread_id: None,
      source_artifact_id: None,
      status: MemoryStatus::Active,
      created_at: 150,
      updated_at: 150,
      archived_at: None,
    })

    let chat = ChatService::new(store~)
    let result = match
      chat.ask(JobAskParams::{
        question: "What improves agent planning?",
        binding_id: None,
        artifact_query: None,
        max_hits: Some(3),
      }) {
      Ok(result) => result
      Err(error) => fail(error)
    }

    inspect(result.hits.length(), content="1")
    inspect(result.memory_hits.length(), content="1")
    inspect(result.citations[0].artifact_id, content="artifact-1")
    inspect(result.answer.contains("artifact(s)"), content="true")
    inspect(result.answer.contains("memory record(s)"), content="true")
    inspect(result.answer.contains("planning"), content="true")
  })
}

///|
async test "ChatService applies persisted chat bindings to artifact scope" {
  @fsx.with_temporary_directory("job-chat-binding-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let store = chat_test_store(root)
    let artifacts = ArtifactStore::new(store~)
    ignore(
      artifacts.write(
        ArtifactWriteRequest::new(
          run_id="run-1",
          job_id="research.paper.parse",
          artifact_type="paper.chunk",
          logical_key=Some("paper:1:intro"),
          scope=["research", "paper:1"],
          content="Paper one studies memory compression.",
        ),
        "artifact-1",
        100,
      ),
    )
    ignore(
      artifacts.write(
        ArtifactWriteRequest::new(
          run_id="run-2",
          job_id="research.paper.parse",
          artifact_type="paper.chunk",
          logical_key=Some("paper:2:intro"),
          scope=["research", "paper:2"],
          content="Paper two studies retrieval augmented agents.",
        ),
        "artifact-2",
        200,
      ),
    )
    store.save_chat_binding(ChatBinding::{
      id: "binding-paper-2",
      title: Some("paper 2"),
      artifact_query: ArtifactQuery::new(scope=Some("paper:2")),
      scope: ["research", "paper:2"],
      created_at: 10,
      updated_at: 10,
    })

    let reloaded = chat_test_store(root)
    reloaded.load()
    let chat = ChatService::new(store=reloaded)
    let result = match
      chat.ask(JobAskParams::{
        question: "Which paper studies retrieval agents?",
        binding_id: Some("binding-paper-2"),
        artifact_query: None,
        max_hits: Some(5),
      }) {
      Ok(result) => result
      Err(error) => fail(error)
    }

    inspect(result.binding_id.unwrap_or(""), content="binding-paper-2")
    inspect(result.hits.length(), content="1")
    inspect(result.hits[0].artifact_id, content="artifact-2")
    inspect(
      result.citations[0].logical_key.unwrap_or(""),
      content="paper:2:intro",
    )
  })
}
