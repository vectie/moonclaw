///|
test "Coordinator finalizes after all subtasks complete" {
  let uuid = @uuid.generator(@rand.chacha8())
  let coordinator = coordinator(uuid~)
  let task = coordinator.create(parent_agent="parent", subtasks=[
    sub_task(task_id="research", message="do research"),
    sub_task(task_id="write", message="write summary"),
  ])
  let _ = coordinator.start_task(task.coordination_id)
  let _ = coordinator.update_subtask_status(
    task.coordination_id,
    "research",
    Completed,
    result=Some({ "content": "research done" }),
  )
  let updated = coordinator.update_subtask_status(
    task.coordination_id,
    "write",
    Completed,
    result=Some({ "content": "summary done" }),
  )
  let updated = match updated {
    Some(updated) => updated
    None => fail("coordination should exist")
  }
  json_inspect(updated.status, content="Completed")
  json_inspect(updated.completed_count(), content=2)
  json_inspect(updated.failed_count(), content=0)
}

///|
test "Coordinator finalizes as failed when a subtask fails" {
  let uuid = @uuid.generator(@rand.chacha8())
  let coordinator = coordinator(uuid~)
  let task = coordinator.create(parent_agent="parent", subtasks=[
    sub_task(task_id="research", message="do research"),
    sub_task(task_id="write", message="write summary"),
  ])
  let _ = coordinator.start_task(task.coordination_id)
  let _ = coordinator.update_subtask_status(
    task.coordination_id,
    "research",
    Completed,
    result=Some({ "content": "research done" }),
  )
  let updated = coordinator.update_subtask_status(
    task.coordination_id,
    "write",
    Failed,
    error=Some("model crashed"),
  )
  let updated = match updated {
    Some(updated) => updated
    None => fail("coordination should exist")
  }
  json_inspect(updated.status, content="Failed")
  json_inspect(updated.completed_count(), content=1)
  json_inspect(updated.failed_count(), content=1)
}

///|
test "Pipeline resolves templated input from prior results" {
  let stage = pipeline_stage(
    name="write",
    message="fallback",
    input_template=Some("Summarize ${research}.output"),
  )
  let results : Map[String, Json] = {
    "research": { "content": "Use bullet points" },
  }
  json_inspect(
    stage.resolve_input(results),
    content="Summarize {\"content\":\"Use bullet points\"}",
  )
}

///|
test "Pipeline advance starts next stage and completes at the end" {
  let started = pipeline(pipeline_id="pipeline-1", name="demo", stages=[
    pipeline_stage(name="research", message="do research"),
    pipeline_stage(name="write", message="write summary"),
  ]).start()
  let advanced = started.advance_stage("research", {
    "content": "research done",
  })
  let current = match advanced.current_stage_info() {
    Some(stage) => stage
    None => fail("next stage should exist")
  }
  json_inspect(advanced.status, content="Running")
  json_inspect(current.name, content="write")
  json_inspect(current.status, content="Running")
  let completed = advanced.advance_stage("write", { "content": "summary done" })
  json_inspect(completed.status, content="Completed")
  json_inspect(completed.completed_stages(), content=2)
}
