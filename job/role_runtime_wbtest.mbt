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
test "resolve_role_runtime_contract reads nested compiled step metadata role runtime" {
  let contract = resolve_role_runtime_contract(
    Some("controller"),
    {
      "role_runtime": {
        "planning_layer": "domain",
        "runtime_mode": "planner_only",
        "tool_access": "limited",
        "memory_scope": "domain",
        "allow_delegate": true,
        "allow_workspace_write": false,
        "allow_execution_tools": false,
      },
    },
    {
      "metadata": {
        "step_metadata": {
          "role_runtime": {
            "planning_layer": "execution",
            "runtime_mode": "executor",
            "tool_access": "full",
            "memory_scope": "workspace",
            "allow_delegate": false,
            "allow_workspace_write": true,
            "allow_execution_tools": true,
            "output_contract": "wiki.gather.result.v1",
          },
        },
      },
    },
  )
  inspect(
    contract.planning_layer.to_json().stringify(),
    content="\"Execution\"",
  )
  inspect(contract.runtime_mode.to_json().stringify(), content="\"Executor\"")
  inspect(contract.tool_access.to_json().stringify(), content="\"Full\"")
  inspect(contract.memory_scope.to_json().stringify(), content="\"Workspace\"")
  inspect(contract.allow_delegate, content="false")
  inspect(contract.allow_workspace_write, content="true")
  inspect(contract.allow_execution_tools, content="true")
  inspect(
    contract.output_contract.unwrap_or(""),
    content="wiki.gather.result.v1",
  )
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
