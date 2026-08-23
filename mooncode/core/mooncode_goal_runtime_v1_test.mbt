///|
test "public goal runtime v1 API is constructible" {
  let policy : @core.GoalOperationPolicy = {
    max_output_bytes: 1024,
    timeout_milliseconds: 1000,
  }
  let operation : @core.GoalRuntimeOperation = {
    operation_id: "operation-1",
    kind: "shell",
    input: "{}",
    policy,
  }
  let phases : Array[@core.GoalRuntimePhase] = [
    Queued,
    Running,
    WaitingApproval,
    RetryBackoff,
    PausedNoProgress,
    PausedExternal,
  ]
  let mut state = @core.new_goal_runtime_state()
  state = @core.reduce_goal_runtime(
    state,
    PlannerDecision(
      "event-continue",
      Continue([operation], "progress", "reason"),
    ),
  )
  for i, phase in phases {
    state = @core.reduce_goal_runtime(
      state,
      PhaseChanged("event-phase-" + i.to_string(), phase),
    )
  }
  state = @core.reduce_goal_runtime(
    state,
    OperationAccepted("event-op", "operation-2"),
  )
  state = @core.reduce_goal_runtime(
    state,
    CheckpointAccepted("event-cp", "checkpoint-1"),
  )
  let evidence : Array[@core.GoalCriterionEvidence] = [
    { criterion: "criterion", evidence_refs: ["proof"] },
  ]
  ignore(
    @core.reduce_goal_runtime(
      state,
      PlannerDecision("event-achieved", Achieved("done", evidence)),
    ),
  )
  ignore(
    @core.reduce_goal_runtime(
      @core.new_goal_runtime_state(),
      PlannerDecision(
        "event-blocked",
        Blocked(
          { code: "external", detail: "waiting" },
          ["attempt"],
          Some("approval"),
        ),
      ),
    ),
  )
  ignore(
    @core.reduce_goal_runtime(
      @core.new_goal_runtime_state(),
      Cancelled("event-cancelled", "operator"),
    ),
  )
}
