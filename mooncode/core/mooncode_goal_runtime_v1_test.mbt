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
    @core.Queued,
    @core.Running,
    @core.WaitingApproval,
    @core.RetryBackoff,
    @core.PausedNoProgress,
    @core.PausedExternal,
  ]
  let mut state = @core.new_goal_runtime_state()
  state = @core.reduce_goal_runtime(
    state,
    @core.PlannerDecision(
      "event-continue",
      @core.Continue([operation], "progress", "reason"),
    ),
  )
  for i, phase in phases {
    state = @core.reduce_goal_runtime(
      state,
      @core.PhaseChanged("event-phase-" + i.to_string(), phase),
    )
  }
  state = @core.reduce_goal_runtime(
    state,
    @core.OperationAccepted("event-op", "operation-2"),
  )
  state = @core.reduce_goal_runtime(
    state,
    @core.CheckpointAccepted("event-cp", "checkpoint-1"),
  )
  let evidence : Array[@core.GoalCriterionEvidence] = [
    { criterion: "criterion", evidence_refs: ["proof"] },
  ]
  ignore(
    @core.reduce_goal_runtime(
      state,
      @core.PlannerDecision("event-achieved", @core.Achieved("done", evidence)),
    ),
  )
  ignore(
    @core.reduce_goal_runtime(
      @core.new_goal_runtime_state(),
      @core.PlannerDecision(
        "event-blocked",
        @core.Blocked(
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
      @core.Cancelled("event-cancelled", "operator"),
    ),
  )
}
