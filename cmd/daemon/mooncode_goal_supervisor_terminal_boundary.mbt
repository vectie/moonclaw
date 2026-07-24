///|
priv struct MooncodeGoalSupervisorClaim {
  mut resolved : Bool
}

///|
fn mooncode_goal_supervisor_terminal_boundary_matches(
  records : Array[Json],
  session_id : String,
  last_command_id : String?,
  last_claim_id : String?,
  last_receipt_record_id : String?,
) -> Bool {
  let commands : Map[String, Bool] = {}
  let claims : Map[String, MooncodeGoalSupervisorClaim] = {}
  let mut invalid = false
  let mut latest_command_id : String? = None
  let mut latest_claim_id : String? = None
  let mut latest_record_id : String? = None
  for record in records {
    let kind = mooncode_json_string(record, "record_kind", default="")
    let wrapper_session_id = mooncode_json_string(
      record,
      "session_id",
      default="",
    )
    let wrapper_record_id = mooncode_json_string(
      record,
      "record_id",
      default="",
    )
    let payload = mooncode_json_object_field_or_empty(record, "payload")
    if kind == mooncode_journal_command() {
      let payload_session_id = mooncode_json_string(
        payload,
        "session_id",
        default="",
      )
      let payload_kind = mooncode_json_string(payload, "kind", default="")
      let payload_protocol = mooncode_json_string(
        payload,
        "protocol",
        default="",
      )
      let wrapper_command_id = mooncode_json_string(
        record,
        "command_id",
        default="",
      )
      let payload_command_id = mooncode_json_string(
        payload,
        "command_id",
        default="",
      )
      if wrapper_session_id != session_id ||
        payload_session_id != session_id ||
        payload_kind != "mooncode-command" ||
        payload_protocol != mooncode_protocol_version() ||
        wrapper_command_id == "" ||
        wrapper_command_id != payload_command_id ||
        wrapper_record_id != "command:\{wrapper_command_id}" ||
        commands.contains(wrapper_command_id) {
        invalid = true
      } else {
        commands[wrapper_command_id] = true
      }
    } else if kind == mooncode_journal_runtime_receipt() {
      let payload_session_id = mooncode_json_string(
        payload,
        "session_id",
        default="",
      )
      let payload_kind = mooncode_json_string(payload, "kind", default="")
      let payload_protocol = mooncode_json_string(
        payload,
        "protocol",
        default="",
      )
      let payload_owner = mooncode_json_string(payload, "owner", default="")
      let wrapper_command_id = mooncode_json_string(
        record,
        "command_id",
        default="",
      )
      let payload_command_id = mooncode_json_string(
        payload,
        "command_id",
        default="",
      )
      let status = mooncode_json_string(payload, "status", default="")
      let claim_id = mooncode_json_string(payload, "claim_id", default="")
      let mode = mooncode_json_string(payload, "runtime_mode", default="")
      let expected_record_id = "runtime-receipt:\{payload_command_id}:\{status}:\{claim_id}"
      let malformed = wrapper_session_id != session_id ||
        payload_session_id != session_id ||
        payload_kind != mooncode_kind_runtime_receipt() ||
        payload_protocol != mooncode_protocol_version() ||
        payload_owner != "moonclaw" ||
        wrapper_command_id == "" ||
        wrapper_command_id != payload_command_id ||
        wrapper_record_id != expected_record_id
      let key = "\{payload_command_id}\u{0}\{claim_id}"
      if malformed {
        invalid = true
      } else if status == "runtime-claimed" &&
        mode == "moonclaw-native-runtime-claim" {
        if claim_id == "" ||
          !commands.contains(payload_command_id) ||
          claims.contains(key) {
          invalid = true
        } else {
          claims[key] = { resolved: false }
        }
      } else {
        let terminal = (
            (status == "runtime-completed" || status == "runtime-failed") &&
            mode == "moonclaw-native-runtime-turn"
          ) ||
          (
            status == "runtime-cancelled" &&
            mode == "moonclaw-native-runtime-control"
          )
        if terminal {
          match claims.get(key) {
            Some(claim) =>
              if claim.resolved {
                invalid = true
              } else {
                claim.resolved = true
                latest_command_id = Some(payload_command_id)
                latest_claim_id = Some(claim_id)
                latest_record_id = Some(wrapper_record_id)
              }
            None => invalid = true
          }
        } else if !(status == "runtime-completed" &&
          mode == "moonclaw-native-runtime-control" &&
          !claims.contains(key)) {
          invalid = true
        }
      }
    }
  }
  for claim in claims.values() {
    if !claim.resolved {
      invalid = true
    }
  }
  if invalid {
    return false
  }
  match (last_command_id, last_claim_id, last_receipt_record_id) {
    (None, None, None) => latest_record_id is None
    (Some(command_id), Some(claim_id), Some(record_id)) =>
      latest_command_id == Some(command_id) &&
      latest_claim_id == Some(claim_id) &&
      latest_record_id == Some(record_id)
    _ => false
  }
}
