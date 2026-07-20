///|
fn mooncode_capability_command_string(
  command : Json,
  key : String,
  default~ : String,
) -> String {
  let payload = mooncode_json_object_field_or_empty(command, "payload")
  mooncode_json_string(
    command,
    key,
    default=mooncode_json_string(payload, key, default~),
  )
}

///|
fn mooncode_capability_safe_scope(scope_id : String) -> Bool {
  !scope_id.is_blank() &&
  !scope_id.contains("/") &&
  !scope_id.contains("\\") &&
  !scope_id.contains("..")
}

///|
fn mooncode_capability_participant_selected(
  projection : Json,
  participant_id : String,
) -> Bool {
  mooncode_json_array_items(projection, "challenger_participant_ids").any(fn(
    value,
  ) {
    value is String(id) && id == participant_id
  })
}

///|
fn mooncode_capability_unavailable(
  scope_id : String,
  participant_id : String,
  reason : String,
) -> Json {
  {
    "contract_version": "moonclaw.capability_resolution.v1",
    "scope_id": scope_id,
    "participant_id": participant_id,
    "assignment": "unavailable",
    "status": "unavailable",
    "reason": reason,
  }
}

///|
/// Resolve MoonFlow's book-local projection for one already claimed command.
/// This is a reader inside the existing MoonClaw runtime, not another runtime.
async fn mooncode_runtime_turn_attach_active_capability(
  book_root : String,
  session_id : String,
  command : Json,
) -> Json {
  let scope_id = mooncode_capability_command_string(
    command,
    "capability_scope_id",
    default="",
  )
  if scope_id == "" {
    return command
  }
  let participant_id = mooncode_capability_command_string(
    command,
    "capability_participant_id",
    default=session_id,
  )
  if !mooncode_capability_safe_scope(scope_id) {
    return mooncode_json_object_with_field(
      command,
      "active_capability",
      mooncode_capability_unavailable(
        scope_id, participant_id, "unsafe capability scope identifier",
      ),
    )
  }
  let relative = ".moonsuite/products/moonflow/capabilities/\{scope_id}.json"
  let path = @pathx.join(book_root, relative)
  if !(@fsx.exists(path) catch { _ => false }) {
    return mooncode_json_object_with_field(
      command,
      "active_capability",
      mooncode_capability_unavailable(
        scope_id, participant_id, "MoonFlow activation projection is missing",
      ),
    )
  }
  let projection = @json.parse(@fsx.read_file(path)) catch {
    _ =>
      return mooncode_json_object_with_field(
        command,
        "active_capability",
        mooncode_capability_unavailable(
          scope_id, participant_id, "MoonFlow activation projection is invalid JSON",
        ),
      )
  }
  let contract_version = mooncode_json_string(
    projection,
    "contract_version",
    default="",
  )
  let projected_scope = mooncode_json_string(projection, "scope_id", default="")
  let status = mooncode_json_string(projection, "status", default="")
  let rollout_mode = mooncode_json_string(
    projection,
    "rollout_mode",
    default="",
  )
  let old_capability = mooncode_json_object_field_or_empty(
    projection, "old_capability",
  )
  let new_capability = mooncode_json_object_field_or_empty(
    projection, "new_capability",
  )
  let old_id = mooncode_json_string(old_capability, "record_id", default="")
  let new_id = mooncode_json_string(new_capability, "record_id", default="")
  if contract_version != "moonflow.capability_loop.v1" ||
    projected_scope != scope_id ||
    (status != "active" && status != "promoted" && status != "rolled_back") ||
    old_id == "" ||
    new_id == "" {
    return mooncode_json_object_with_field(
      command,
      "active_capability",
      mooncode_capability_unavailable(
        scope_id, participant_id, "MoonFlow activation projection failed contract validation",
      ),
    )
  }
  let challenger = if status == "promoted" {
    true
  } else if status == "rolled_back" {
    false
  } else if rollout_mode == "canary" {
    mooncode_capability_participant_selected(projection, participant_id)
  } else {
    false
  }
  let resolution : Json = {
    "contract_version": "moonclaw.capability_resolution.v1",
    "scope_id": scope_id,
    "participant_id": participant_id,
    "assignment": if challenger {
      "challenger"
    } else {
      "baseline"
    },
    "selected_capability": if challenger {
      new_capability
    } else {
      old_capability
    },
    "shadow_capability": if status == "active" && rollout_mode == "shadow" {
      new_capability
    } else {
      null
    },
    "activation_id": mooncode_json_string(
      projection,
      "activation_id",
      default="",
    ),
    "experiment": mooncode_json_object_field_or_empty(projection, "experiment"),
    "status": status,
    "rollout_mode": rollout_mode,
    "projection_path": relative,
  }
  mooncode_json_object_with_field(command, "active_capability", resolution)
}
