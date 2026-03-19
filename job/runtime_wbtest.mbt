///|
fn runtime_definition(
  schedule? : SchedulePolicy? = Some(SchedulePolicy::{
    kind: "interval",
    interval_minutes: Some(60),
    timezone: Some("Asia/Shanghai"),
  }),
  retry_policy? : RetryPolicy? = Some(RetryPolicy::{
    max_attempts: 2,
    backoff_ms: Some(100),
  }),
) -> JobDefinition {
  JobDefinition::{
    id: "job-1",
    kind: "research.topic.sync",
    enabled: true,
    config: { "query": "agents" },
    schedule,
    retry_policy,
    workflow_id: None,
    created_at: 1,
    updated_at: 1,
    tags: ["research"],
  }
}

///|
async test "RuntimeManager persists checkpoints and prevents duplicate active runs" {
  @fsx.with_temporary_directory("job-runtime-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let manager = RuntimeManager::new(root~)
    manager.register_definition(runtime_definition())

    let run = match
      manager.create_run("run-1", "job-1", TriggerSource::Manual, 100) {
      Ok(run) => run
      Err(error) => fail(error)
    }
    inspect(run.status.to_json().stringify(), content="\"Pending\"")
    inspect(run.attempt, content="1")
    ignore(manager.mark_run_started("run-1", 120))
    inspect(manager.is_job_active("job-1"), content="true")
    inspect(
      manager.create_run("run-2", "job-1", TriggerSource::Manual, 130) is Err(_),
      content="true",
    )
    ignore(manager.mark_run_succeeded("run-1", 200, summary=Some("done")))
    inspect(manager.is_job_active("job-1"), content="false")

    let reloaded = RuntimeManager::new(root~)
    reloaded.load()
    let checkpoint = match reloaded.checkpoints().get("job-1") {
      Some(checkpoint) => checkpoint
      None => fail("expected checkpoint after reload")
    }
    inspect(checkpoint.last_triggered_at.unwrap_or(0), content="100")
    inspect(checkpoint.last_started_at.unwrap_or(0), content="120")
    inspect(checkpoint.last_completed_at.unwrap_or(0), content="200")
    inspect(checkpoint.last_success_at.unwrap_or(0), content="200")
    inspect(checkpoint.last_run_id.unwrap_or(""), content="run-1")
    inspect(
      @fsx.exists(
        root |> @pathx.join("checkpoints") |> @pathx.join("job-1.json"),
      ),
      content="true",
    )
  })
}

///|
async test "RuntimeManager returns due scheduled definitions from checkpoints" {
  @fsx.with_temporary_directory("job-runtime-due-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let manager = RuntimeManager::new(root~)
    manager.register_definition(runtime_definition())
    manager.register_definition(JobDefinition::{
      ..runtime_definition(
        schedule=Some(SchedulePolicy::{
          kind: "interval",
          interval_minutes: Some(10),
          timezone: None,
        }),
      ),
      id: "job-2",
      kind: "research.paper.fetch",
    })

    let due_initial = manager.due_definitions(1_000)
    inspect(due_initial.length(), content="2")

    ignore(
      manager.create_run("run-1", "job-1", TriggerSource::Scheduled, 1_000),
    )
    ignore(manager.mark_run_started("run-1", 1_100))
    ignore(manager.mark_run_succeeded("run-1", 1_200))
    let due_after_short_interval = manager.due_definitions(1_500)
    inspect(
      due_after_short_interval.map(fn(job) { job.id }).join(","),
      content="job-2",
    )

    let due_after_hour = manager.due_definitions(1_000 + 60 * 60 * 1000 + 1)
    inspect(
      due_after_hour.map(fn(job) { job.id }).join(","),
      content="job-1,job-2",
    )
  })
}

///|
async test "RuntimeManager triggers due runs and exposes active and recent status" {
  @fsx.with_temporary_directory("job-runtime-schedule-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let manager = RuntimeManager::new(root~)
    manager.register_definition(runtime_definition())
    manager.register_definition(JobDefinition::{
      ..runtime_definition(schedule=None),
      id: "job-2",
      kind: "research.paper.ask",
    })

    let scheduled = manager.trigger_due_definitions(60 * 60 * 1000 + 1, fn() {
      "run-scheduled-1"
    })
    inspect(
      scheduled.map(fn(run) { run.id }).join(","),
      content="run-scheduled-1",
    )
    inspect(scheduled.map(fn(run) { run.job_id }).join(","), content="job-1")

    ignore(manager.mark_run_started("run-scheduled-1", 60 * 60 * 1000 + 2))
    inspect(
      manager.list_active_runs().map(fn(run) { run.id }).join(","),
      content="run-scheduled-1",
    )

    ignore(
      manager.mark_run_succeeded(
        "run-scheduled-1",
        60 * 60 * 1000 + 3,
        summary=Some("scheduled"),
      ),
    )
    inspect(manager.list_active_runs().length(), content="0")
    inspect(
      manager
      .list_recent_runs(limit=1)
      .map(fn(run) { "\{run.id}:\{run.status.to_json().stringify()}" })
      .join(","),
      content="run-scheduled-1:\"Succeeded\"",
    )
  })
}

///|
async test "RuntimeManager schedules retry runs with backoff and resets retry state on success" {
  @fsx.with_temporary_directory("job-runtime-retry-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let manager = RuntimeManager::new(root~)
    manager.register_definition(runtime_definition())

    ignore(manager.create_run("run-1", "job-1", TriggerSource::Manual, 100))
    ignore(manager.mark_run_started("run-1", 110))
    ignore(manager.mark_run_failed("run-1", 200, "tool failed"))

    let checkpoint_after_failure = match manager.checkpoints().get("job-1") {
      Some(checkpoint) => checkpoint
      None => fail("expected retry checkpoint")
    }
    inspect(checkpoint_after_failure.retry_attempts, content="1")
    inspect(checkpoint_after_failure.next_retry_at.unwrap_or(0), content="300")
    inspect(
      checkpoint_after_failure.retry_source_run_id.unwrap_or(""),
      content="run-1",
    )

    let before_due = manager.trigger_due_definitions(299, fn() { "run-2" })
    inspect(before_due.length(), content="0")

    let retries = manager.trigger_due_definitions(300, fn() { "run-2" })
    inspect(retries.length(), content="1")
    inspect(retries[0].trigger.to_json().stringify(), content="\"Recovery\"")
    inspect(retries[0].attempt, content="2")
    inspect(retries[0].retry_of.unwrap_or(""), content="run-1")

    ignore(manager.mark_run_started("run-2", 310))
    ignore(manager.mark_run_succeeded("run-2", 320, summary=Some("recovered")))

    let checkpoint_after_success = match manager.checkpoints().get("job-1") {
      Some(checkpoint) => checkpoint
      None => fail("expected checkpoint after success")
    }
    inspect(checkpoint_after_success.retry_attempts, content="0")
    inspect(checkpoint_after_success.next_retry_at is None, content="true")
    inspect(
      checkpoint_after_success.retry_source_run_id is None,
      content="true",
    )
  })
}

///|
async test "RuntimeManager initializes controller state for controller jobs" {
  @fsx.with_temporary_directory("job-runtime-controller-XXXXXX", dir => {
    let root = @pathx.join(dir, "jobs")
    let manager = RuntimeManager::new(root~)
    manager.register_definition(JobDefinition::{
      id: "job-controller-1",
      kind: "job.controller",
      enabled: true,
      config: {
        "proposal_id": "proposal-controller-1",
        "family": "research_controller",
        "profile_id": "research_controller",
        "role": "controller",
        "profile_metadata": { "domain": "research" },
      },
      schedule: None,
      retry_policy: None,
      workflow_id: None,
      created_at: 1,
      updated_at: 1,
      tags: ["controller"],
    })
    manager
    .store()
    .save_job_proposal(JobProposal::{
      ..draft_job_proposal("proposal-controller-1", "Research VLA papers.", 1),
      suggested_family: Some("research_controller"),
      profile_id: Some("research_controller"),
      profile_role: Some("controller"),
      profile_metadata: { "domain": "research" },
    })
    let run = match
      manager.create_run(
        "run-controller-1",
        "job-controller-1",
        TriggerSource::Manual,
        100,
      ) {
      Ok(run) => run
      Err(error) => fail(error)
    }
    let state = match manager.store().get_controller_state(run.id) {
      Some(state) => state
      None => fail("expected controller state")
    }
    inspect(state.family, content="research_controller")
    inspect(state.profile_id.unwrap_or(""), content="research_controller")
    inspect(
      state.active_iteration_ids.join(","),
      content="run-controller-1:iter:root",
    )
    let iteration = match
      manager.store().get_controller_iteration("run-controller-1:iter:root") {
      Some(iteration) => iteration
      None => fail("expected root iteration")
    }
    inspect(iteration.status, content="active")
    inspect(iteration.hypothesis, content="Research VLA papers.")
  })
}
