///|
pub(all) enum RolePlanningLayer {
  Strategic
  Domain
  Execution
} derive(ToJson, FromJson, Show, Eq)

///|
pub(all) enum RoleRuntimeMode {
  PlannerOnly
  Executor
} derive(ToJson, FromJson, Show, Eq)

///|
pub(all) enum RoleToolAccess {
  Disabled
  Limited
  Full
} derive(ToJson, FromJson, Show, Eq)

///|
pub(all) enum RoleMemoryScope {
  Step
  Workspace
  Domain
  Global
} derive(ToJson, FromJson, Show, Eq)

///|
pub(all) struct RoleRuntimeContract {
  role_id : String
  planning_layer : RolePlanningLayer
  runtime_mode : RoleRuntimeMode
  tool_access : RoleToolAccess
  memory_scope : RoleMemoryScope
  allow_delegate : Bool
  allow_workspace_write : Bool
  allow_execution_tools : Bool
  output_contract : String?
  metadata : Json
} derive(ToJson, FromJson, Show)

///|
pub(all) enum RoleHandoffKind {
  StrategicToDomain
  DomainToExecution
  ExecutionToDomain
  DomainToStrategic
} derive(ToJson, FromJson, Show, Eq)

///|
pub(all) struct RoleHandoffPacket {
  kind : RoleHandoffKind
  objective : String
  scope_summary : String
  constraints : Array[String]
  output_contract : String?
  review_required : Bool
  metadata : Json
} derive(ToJson, FromJson, Show)

///|
pub fn RoleRuntimeContract::new(
  role_id~ : String,
  planning_layer? : RolePlanningLayer = Execution,
  runtime_mode? : RoleRuntimeMode = Executor,
  tool_access? : RoleToolAccess = Full,
  memory_scope? : RoleMemoryScope = Workspace,
  allow_delegate? : Bool = false,
  allow_workspace_write? : Bool = true,
  allow_execution_tools? : Bool = true,
  output_contract? : String? = None,
  metadata? : Json = {},
) -> RoleRuntimeContract {
  RoleRuntimeContract::{
    role_id,
    planning_layer,
    runtime_mode,
    tool_access,
    memory_scope,
    allow_delegate,
    allow_workspace_write,
    allow_execution_tools,
    output_contract,
    metadata,
  }
}

///|
pub fn RoleHandoffPacket::new(
  kind~ : RoleHandoffKind,
  objective~ : String,
  scope_summary~ : String,
  constraints? : Array[String] = [],
  output_contract? : String? = None,
  review_required? : Bool = false,
  metadata? : Json = {},
) -> RoleHandoffPacket {
  RoleHandoffPacket::{
    kind,
    objective,
    scope_summary,
    constraints,
    output_contract,
    review_required,
    metadata,
  }
}

///|
fn role_runtime_string(value : Json, key : String) -> String? {
  match value {
    Object(obj) =>
      match obj.get(key) {
        Some(String(text)) => Some(text.trim().to_string())
        _ => None
      }
    _ => None
  }
}

///|
fn role_runtime_bool(value : Json, key : String) -> Bool? {
  match value {
    Object(obj) =>
      match obj.get(key) {
        Some(True) => Some(true)
        Some(False) => Some(false)
        _ => None
      }
    _ => None
  }
}

///|
fn role_runtime_metadata(value : Json) -> Json? {
  match value {
    { "role_runtime": metadata, .. } => Some(metadata)
    { "step_metadata": nested, .. } => role_runtime_metadata(nested)
    { "metadata": nested, .. } => role_runtime_metadata(nested)
    _ => None
  }
}

///|
fn merged_role_runtime_metadata(
  profile_metadata : Json,
  step_metadata : Json,
) -> Json? {
  match
    (
      role_runtime_metadata(profile_metadata),
      role_runtime_metadata(step_metadata),
    ) {
    (None, None) => None
    (Some(profile), None) => Some(profile)
    (None, Some(step)) => Some(step)
    (Some(Object(profile)), Some(Object(step))) => {
      let merged : Map[String, Json] = {}
      for key, value in profile {
        merged.set(key, value)
      }
      for key, value in step {
        merged.set(key, value)
      }
      Some(Json::object(merged))
    }
    (_, Some(step)) => Some(step)
  }
}

///|
fn default_role_runtime_contract(
  role : String?,
  profile_metadata : Json,
) -> RoleRuntimeContract {
  let normalized_role = role.unwrap_or("worker").trim().to_string().to_lower()
  match normalized_role {
    "controller" =>
      RoleRuntimeContract::new(
        role_id="controller",
        planning_layer=Domain,
        runtime_mode=PlannerOnly,
        tool_access=Limited,
        memory_scope=Domain,
        allow_delegate=true,
        allow_workspace_write=false,
        allow_execution_tools=false,
        metadata=profile_metadata,
      )
    "mayor" =>
      RoleRuntimeContract::new(
        role_id="mayor",
        planning_layer=Strategic,
        runtime_mode=PlannerOnly,
        tool_access=Limited,
        memory_scope=Global,
        allow_delegate=true,
        allow_workspace_write=false,
        allow_execution_tools=false,
        metadata=profile_metadata,
      )
    "lead" =>
      RoleRuntimeContract::new(
        role_id="lead",
        planning_layer=Domain,
        runtime_mode=PlannerOnly,
        tool_access=Limited,
        memory_scope=Domain,
        allow_delegate=true,
        allow_workspace_write=false,
        allow_execution_tools=false,
        metadata=profile_metadata,
      )
    role_id =>
      RoleRuntimeContract::new(
        role_id~,
        planning_layer=Execution,
        runtime_mode=Executor,
        tool_access=Full,
        memory_scope=Workspace,
        allow_delegate=false,
        allow_workspace_write=true,
        allow_execution_tools=true,
        metadata=profile_metadata,
      )
  }
}

///|
fn override_planning_layer(
  base : RolePlanningLayer,
  metadata : Json?,
) -> RolePlanningLayer {
  match
    metadata.bind(fn(value) { role_runtime_string(value, "planning_layer") }) {
    Some("strategic") => Strategic
    Some("domain") => Domain
    Some("execution") => Execution
    _ => base
  }
}

///|
fn override_runtime_mode(
  base : RoleRuntimeMode,
  metadata : Json?,
) -> RoleRuntimeMode {
  match
    metadata.bind(fn(value) { role_runtime_string(value, "runtime_mode") }) {
    Some("planner_only") => PlannerOnly
    Some("executor") => Executor
    _ => base
  }
}

///|
fn override_tool_access(
  base : RoleToolAccess,
  metadata : Json?,
) -> RoleToolAccess {
  match metadata.bind(fn(value) { role_runtime_string(value, "tool_access") }) {
    Some("none") => Disabled
    Some("limited") => Limited
    Some("full") => Full
    _ => base
  }
}

///|
fn override_memory_scope(
  base : RoleMemoryScope,
  metadata : Json?,
) -> RoleMemoryScope {
  match
    metadata.bind(fn(value) { role_runtime_string(value, "memory_scope") }) {
    Some("step") => Step
    Some("workspace") => Workspace
    Some("domain") => Domain
    Some("global") => Global
    _ => base
  }
}

///|
pub fn resolve_role_runtime_contract(
  role : String?,
  profile_metadata : Json,
  step_metadata : Json,
) -> RoleRuntimeContract {
  let defaults = default_role_runtime_contract(role, profile_metadata)
  let resolved_metadata = merged_role_runtime_metadata(
    profile_metadata, step_metadata,
  )
  let output_contract = match
    resolved_metadata.bind(fn(value) {
      role_runtime_string(value, "output_contract")
    }) {
    Some(value) => Some(value)
    None => defaults.output_contract
  }
  RoleRuntimeContract::{
    role_id: resolved_metadata
    .bind(fn(value) { role_runtime_string(value, "role_id") })
    .unwrap_or(defaults.role_id),
    planning_layer: override_planning_layer(
      defaults.planning_layer,
      resolved_metadata,
    ),
    runtime_mode: override_runtime_mode(
      defaults.runtime_mode,
      resolved_metadata,
    ),
    tool_access: override_tool_access(defaults.tool_access, resolved_metadata),
    memory_scope: override_memory_scope(
      defaults.memory_scope,
      resolved_metadata,
    ),
    allow_delegate: resolved_metadata
    .bind(fn(value) { role_runtime_bool(value, "allow_delegate") })
    .unwrap_or(defaults.allow_delegate),
    allow_workspace_write: resolved_metadata
    .bind(fn(value) { role_runtime_bool(value, "allow_workspace_write") })
    .unwrap_or(defaults.allow_workspace_write),
    allow_execution_tools: resolved_metadata
    .bind(fn(value) { role_runtime_bool(value, "allow_execution_tools") })
    .unwrap_or(defaults.allow_execution_tools),
    output_contract,
    metadata: resolved_metadata.unwrap_or(defaults.metadata),
  }
}
