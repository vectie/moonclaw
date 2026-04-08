///|
test "resolve_role_runtime_contract defaults controller to planner-only domain role" {
  let contract = resolve_role_runtime_contract(
    Some("controller"),
    { "domain": "research" },
    {},
  )
  inspect(contract.role_id, content="controller")
  inspect(contract.planning_layer.to_json().stringify(), content="\"Domain\"")
  inspect(
    contract.runtime_mode.to_json().stringify(),
    content="\"PlannerOnly\"",
  )
  inspect(contract.tool_access.to_json().stringify(), content="\"Limited\"")
  inspect(contract.memory_scope.to_json().stringify(), content="\"Domain\"")
  inspect(contract.allow_delegate, content="true")
  inspect(contract.allow_workspace_write, content="false")
  inspect(contract.allow_execution_tools, content="false")
}

///|
test "resolve_role_runtime_contract applies role_runtime overrides from profile and step metadata" {
  let contract = resolve_role_runtime_contract(
    Some("lead"),
    {
      "role_runtime": {
        "tool_access": "limited",
        "output_contract": "lead.plan.packet.v1",
      },
    },
    {
      "role_runtime": {
        "allow_workspace_write": true,
        "memory_scope": "workspace",
      },
    },
  )
  inspect(contract.role_id, content="lead")
  inspect(contract.output_contract.unwrap_or(""), content="lead.plan.packet.v1")
  inspect(contract.tool_access.to_json().stringify(), content="\"Limited\"")
  inspect(contract.memory_scope.to_json().stringify(), content="\"Workspace\"")
  inspect(contract.allow_workspace_write, content="true")
}

///|
test "constrain_tool_contract_for_role removes execution tools for planner-only roles" {
  let contract = AnalysisToolContract::new(
    runtime_context=true,
    list_worktrees=true,
    delegate_run=true,
    web_fetch=true,
    web_search=true,
  )
  let constrained = constrain_tool_contract_for_role(
    contract,
    Some(
      RoleRuntimeContract::new(
        role_id="lead",
        planning_layer=Domain,
        runtime_mode=PlannerOnly,
        tool_access=Limited,
        memory_scope=Domain,
        allow_delegate=true,
        allow_workspace_write=false,
        allow_execution_tools=false,
      ),
    ),
  )
  inspect(constrained.shell, content="false")
  inspect(constrained.delegate_run, content="true")
  inspect(constrained.runtime_context, content="true")
  inspect(constrained.list_worktrees, content="false")
  inspect(constrained.file_write, content="false")
  inspect(constrained.patch_edit, content="false")
  inspect(constrained.web_fetch, content="false")
  inspect(constrained.web_search, content="false")
}
