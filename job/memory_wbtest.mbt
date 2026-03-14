///|
fn memory_test_store(root : String) -> SystemStore {
  SystemStore::new(root~)
}

///|
async test "MemoryService persists and reloads scoped memory records" {
  @fsx.with_temporary_directory("job-memory-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let store = memory_test_store(root)
    let service = MemoryService::new(store~)
    let memory = service.remember(
      MemoryWriteRequest::new(
        kind="note",
        title=Some("weekly plan"),
        content="Remember to watch VLA papers every weekday morning.",
        tags=["research", "watch"],
        scope=["workspace:main", "research"],
        workspace=Some("/tmp/workspace"),
        agent_id=Some("main"),
        channel_id=Some("feishu"),
        account_id=Some("default"),
        recipient=Some("chat-1"),
      ),
      "memory-1",
      100,
    )
    inspect(memory.kind, content="note")

    let reloaded = memory_test_store(root)
    reloaded.load()
    let loaded = match reloaded.get_memory("memory-1") {
      Some(memory) => memory
      None => fail("expected persisted memory")
    }
    inspect(loaded.workspace.unwrap_or(""), content="/tmp/workspace")
    inspect(loaded.scope.join(","), content="workspace:main,research")
  })
}

///|
async test "MemoryService search filters by scope and ignores archived records" {
  @fsx.with_temporary_directory("job-memory-search-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let store = memory_test_store(root)
    let service = MemoryService::new(store~)
    ignore(
      service.remember(
        MemoryWriteRequest::new(
          kind="bookmark",
          content="Arxiv VLA digest should include robot manipulation benchmarks.",
          tags=["research", "vla"],
          scope=["research", "workspace:main"],
        ),
        "memory-1",
        100,
      ),
    )
    ignore(
      service.remember(
        MemoryWriteRequest::new(
          kind="note",
          content="Unrelated grocery reminder.",
          tags=["personal"],
          scope=["workspace:main"],
        ),
        "memory-2",
        110,
      ),
    )
    ignore(service.archive("memory-2", 120))

    let hits = service.search(
      "robot benchmarks",
      query=MemoryQuery::new(scope=Some("research")),
      max_hits=3,
    )

    inspect(hits.length(), content="1")
    inspect(hits[0].memory_id, content="memory-1")
    inspect(hits[0].snippet.contains("benchmarks"), content="true")
  })
}
