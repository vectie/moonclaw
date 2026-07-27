///|
priv struct MoonCodeGoalAuthoritySnapshot {
  legacy : @mooncode_core.Goal?
  runtime : MoonCodeGoalRuntimeScan
}

///|
priv struct MoonCodeGoalAuthorityProjection {
  legacy : @mooncode_core.Goal?
  runtime : MoonCodeGoalRuntimeProjection
}

///|
fn mooncode_goal_authority_projection_is_dual(
  projection : MoonCodeGoalAuthorityProjection,
) -> Bool {
  projection.legacy is Some(_) && projection.runtime.genesis is Some(_)
}

///|
fn mooncode_goal_authority_snapshot(
  records : Array[Json],
  session_id : String,
) -> MoonCodeGoalAuthoritySnapshot raise {
  {
    legacy: mooncode_replay_goal_records(records, session_id),
    runtime: mooncode_goal_runtime_scan_records(records, session_id),
  }
}

///|
fn mooncode_goal_authority_is_dual(
  snapshot : MoonCodeGoalAuthoritySnapshot,
) -> Bool {
  snapshot.legacy is Some(_) && snapshot.runtime.genesis is Some(_)
}

///|
async fn mooncode_goal_authority_records_locked(
  book_root : String,
  session_id : String,
) -> Array[Json] {
  mooncode_read_session_journal_path(
    mooncode_session_journal_path(book_root, session_id),
    session_id,
  )
}
