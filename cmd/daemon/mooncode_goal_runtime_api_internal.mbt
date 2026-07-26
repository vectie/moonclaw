///|
fn mooncode_goal_runtime_authority_error() -> MoonCodeGoalRuntimeApiResponse {
  mooncode_goal_runtime_api_error(409, "goal_runtime_corrupt")
}

///|
async fn mooncode_goal_runtime_api_get_internal(
  book_root : String,
  session_id : String,
) -> MoonCodeGoalRuntimeApiResponse {
  ignore(mooncode_goal_require_active_session(session_id, book_root)) catch {
    InvalidGoalSessionQuery =>
      return mooncode_goal_runtime_api_error(
        400, "invalid_goal_runtime_session_query",
      )
    GoalSessionAbsentOrMismatch =>
      return mooncode_goal_runtime_api_error(
        404, "goal_runtime_session_not_found",
      )
    GoalSessionCorrupt =>
      return mooncode_goal_runtime_api_error(
        409, "goal_runtime_session_corrupt",
      )
  }
  let lifecycle_gate = mooncode_open_session_lifecycle_gate(
    book_root, session_id,
  ) catch {
    _ => return mooncode_goal_runtime_api_error(500, "internal_error")
  }
  defer lifecycle_gate.close()
  lifecycle_gate.lock(Shared) catch {
    _ => return mooncode_goal_runtime_api_error(500, "internal_error")
  }
  defer lifecycle_gate.unlock()
  let session_lock = mooncode_open_session_lock(book_root, session_id) catch {
    _ => return mooncode_goal_runtime_api_error(500, "internal_error")
  }
  defer session_lock.close()
  session_lock.lock(Shared) catch {
    _ => return mooncode_goal_runtime_api_error(500, "internal_error")
  }
  defer session_lock.unlock()
  ignore(mooncode_goal_require_active_session(session_id, book_root)) catch {
    InvalidGoalSessionQuery =>
      return mooncode_goal_runtime_api_error(
        400, "invalid_goal_runtime_session_query",
      )
    GoalSessionAbsentOrMismatch =>
      return mooncode_goal_runtime_api_error(
        404, "goal_runtime_session_not_found",
      )
    GoalSessionCorrupt =>
      return mooncode_goal_runtime_api_error(
        409, "goal_runtime_session_corrupt",
      )
  }
  let state = mooncode_session_state_locked(book_root, session_id) catch {
    _ =>
      return mooncode_goal_runtime_api_error(
        409, "goal_runtime_session_corrupt",
      )
  }
  if state != "active" {
    return mooncode_goal_runtime_api_error(409, "goal_runtime_session_corrupt")
  }
  let records = mooncode_goal_authority_records_locked(book_root, session_id) catch {
    InvalidJournal(_) => return mooncode_goal_runtime_authority_error()
    _ => return mooncode_goal_runtime_api_error(500, "internal_error")
  }
  let authority = mooncode_goal_authority_snapshot(records, session_id) catch {
    InvalidGoalGenesis(_) => return mooncode_goal_runtime_authority_error()
    MoonCodeGoalRuntimeStoreError::CorruptStore(_) =>
      return mooncode_goal_runtime_authority_error()
    MoonCodeGoalRuntimeStoreError::IdentityConflict(_, _, _) =>
      return mooncode_goal_runtime_authority_error()
    _ => return mooncode_goal_runtime_api_error(500, "internal_error")
  }
  if mooncode_goal_authority_is_dual(authority) {
    return mooncode_goal_runtime_api_error(409, "goal_authority_conflict")
  }
  match authority.runtime.genesis {
    None => mooncode_goal_runtime_api_error(404, "goal_runtime_not_found")
    Some(_) =>
      mooncode_goal_runtime_status_response(authority.runtime) catch {
        _ => mooncode_goal_runtime_authority_error()
      }
  }
}

///|
async fn mooncode_goal_runtime_api_put_internal(
  book_root : String,
  session_id : String,
  body : Json,
  epoch_seconds : Int64,
) -> MoonCodeGoalRuntimeApiResponse {
  let request = mooncode_goal_runtime_parse_put_request(body, session_id) catch {
    MoonCodeGoalRuntimeCodecError::Invalid(_) =>
      return mooncode_goal_runtime_api_error(
        400, "invalid_goal_runtime_request",
      )
  }
  ignore(mooncode_goal_require_active_session(session_id, book_root)) catch {
    InvalidGoalSessionQuery =>
      return mooncode_goal_runtime_api_error(
        400, "invalid_goal_runtime_session_query",
      )
    GoalSessionAbsentOrMismatch =>
      return mooncode_goal_runtime_api_error(
        404, "goal_runtime_session_not_found",
      )
    GoalSessionCorrupt =>
      return mooncode_goal_runtime_api_error(
        409, "goal_runtime_session_corrupt",
      )
  }
  if epoch_seconds < 0L {
    return mooncode_goal_runtime_api_error(
      500, "goal_runtime_clock_out_of_range",
    )
  }
  let expected = new_mooncode_goal_runtime_genesis(
    request.session_id,
    request.goal_id,
    request.objective,
    request.criteria,
    epoch_seconds,
  ) catch {
    MoonCodeGoalRuntimeCodecError::Invalid(_) =>
      return mooncode_goal_runtime_api_error(
        400, "invalid_goal_runtime_request",
      )
  }
  let lifecycle_gate = mooncode_open_session_lifecycle_gate(
    book_root, session_id,
  ) catch {
    _ => return mooncode_goal_runtime_api_error(500, "internal_error")
  }
  defer lifecycle_gate.close()
  lifecycle_gate.lock(Shared) catch {
    _ => return mooncode_goal_runtime_api_error(500, "internal_error")
  }
  defer lifecycle_gate.unlock()
  let session_lock = mooncode_open_session_lock(book_root, session_id) catch {
    _ => return mooncode_goal_runtime_api_error(500, "internal_error")
  }
  defer session_lock.close()
  session_lock.lock(Exclusive) catch {
    _ => return mooncode_goal_runtime_api_error(500, "internal_error")
  }
  defer session_lock.unlock()
  ignore(mooncode_goal_require_active_session(session_id, book_root)) catch {
    InvalidGoalSessionQuery =>
      return mooncode_goal_runtime_api_error(
        400, "invalid_goal_runtime_session_query",
      )
    GoalSessionAbsentOrMismatch =>
      return mooncode_goal_runtime_api_error(
        404, "goal_runtime_session_not_found",
      )
    GoalSessionCorrupt =>
      return mooncode_goal_runtime_api_error(
        409, "goal_runtime_session_corrupt",
      )
  }
  mooncode_require_active_session_state_locked(book_root, session_id) catch {
    _ =>
      return mooncode_goal_runtime_api_error(
        409, "goal_runtime_session_corrupt",
      )
  }
  let records = mooncode_goal_authority_records_locked(book_root, session_id) catch {
    InvalidJournal(_) => return mooncode_goal_runtime_authority_error()
    _ => return mooncode_goal_runtime_api_error(500, "internal_error")
  }
  let authority = mooncode_goal_authority_snapshot(records, session_id) catch {
    InvalidGoalGenesis(_) => return mooncode_goal_runtime_authority_error()
    MoonCodeGoalRuntimeStoreError::CorruptStore(_) =>
      return mooncode_goal_runtime_authority_error()
    MoonCodeGoalRuntimeStoreError::IdentityConflict(_, _, _) =>
      return mooncode_goal_runtime_authority_error()
    _ => return mooncode_goal_runtime_api_error(500, "internal_error")
  }
  if mooncode_goal_authority_is_dual(authority) || authority.legacy is Some(_) {
    return mooncode_goal_runtime_api_error(409, "goal_authority_conflict")
  }
  match authority.runtime.genesis {
    Some(entry) => {
      if entry.semantic_digest != expected.semantic_digest {
        return mooncode_goal_runtime_api_error(409, "goal_runtime_conflict")
      }
      return mooncode_goal_runtime_status_response(authority.runtime) catch {
        _ => mooncode_goal_runtime_authority_error()
      }
    }
    None => ()
  }
  let canonical = encode_mooncode_goal_runtime_genesis(expected) catch {
    _ => return mooncode_goal_runtime_api_error(500, "internal_error")
  }
  let carrier = mooncode_goal_runtime_carrier_from_genesis(canonical) catch {
    _ => return mooncode_goal_runtime_api_error(500, "internal_error")
  }
  let payload = encode_mooncode_goal_runtime_carrier(carrier) catch {
    _ => return mooncode_goal_runtime_api_error(500, "internal_error")
  }
  let appended = mooncode_append_session_journal_once_locked(
    book_root,
    session_id,
    mooncode_journal_event(),
    payload,
  ) catch {
    InvalidJournal(_) => return mooncode_goal_runtime_authority_error()
    _ => return mooncode_goal_runtime_api_error(500, "internal_error")
  }
  if !appended {
    return mooncode_goal_runtime_api_error(409, "goal_runtime_conflict")
  }
  let committed = mooncode_goal_authority_records_locked(book_root, session_id) catch {
    _ => return mooncode_goal_runtime_api_error(500, "internal_error")
  }
  let winner = mooncode_goal_authority_snapshot(committed, session_id) catch {
    _ => return mooncode_goal_runtime_authority_error()
  }
  if mooncode_goal_authority_is_dual(winner) || winner.legacy is Some(_) {
    return mooncode_goal_runtime_api_error(409, "goal_authority_conflict")
  }
  guard winner.runtime.genesis is Some(entry) &&
    entry.semantic_digest == expected.semantic_digest else {
    return mooncode_goal_runtime_api_error(409, "goal_runtime_conflict")
  }
  mooncode_goal_runtime_status_response(winner.runtime, status_code=201) catch {
    _ => mooncode_goal_runtime_authority_error()
  }
}
