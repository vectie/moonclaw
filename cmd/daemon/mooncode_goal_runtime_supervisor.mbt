///|
priv enum MoonCodeGoalRuntimeSupervisorAppendResult {
  NoRuntimeGoal
  Appended
  Idempotent
  Terminal
}

///|
async fn mooncode_goal_runtime_append_supervisor_event(
  book_root : String,
  session_id : String,
  event : @mooncode_core.GoalRuntimeEvent,
  recorded_at : Int64,
) -> MoonCodeGoalRuntimeSupervisorAppendResult {
  let session_lock = mooncode_open_session_lock(book_root, session_id)
  defer session_lock.close()
  session_lock.lock(Exclusive)
  defer session_lock.unlock()
  mooncode_goal_runtime_append_supervisor_event_locked(
    book_root, session_id, event, recorded_at,
  )
}

///|
async fn mooncode_goal_runtime_append_supervisor_event_locked(
  book_root : String,
  session_id : String,
  event : @mooncode_core.GoalRuntimeEvent,
  recorded_at : Int64,
) -> MoonCodeGoalRuntimeSupervisorAppendResult {
  let records = mooncode_goal_authority_records_locked(book_root, session_id)
  let authority = mooncode_goal_authority_snapshot(records, session_id)
  if mooncode_goal_authority_is_dual(authority) || authority.legacy is Some(_) {
    mooncode_goal_runtime_store_corrupt(
      "legacy goal authority cannot accept runtime supervisor events",
    )
  }
  guard authority.runtime.genesis is Some(genesis_entry) &&
    genesis_entry.carrier.record is Genesis(genesis) else {
    return NoRuntimeGoal
  }
  let stored = new_mooncode_goal_runtime_stored_event(
    session_id,
    genesis.goal_id,
    event,
    recorded_at,
  )
  match authority.runtime.id_index.get(stored.id) {
    Some(previous) => {
      if previous.semantic_digest != stored.semantic_digest {
        raise MoonCodeGoalRuntimeStoreError::IdentityConflict(
          stored.id,
          previous.semantic_digest,
          stored.semantic_digest,
        )
      }
      return Idempotent
    }
    None => ()
  }
  let state = mooncode_goal_runtime_state_from_scan(authority.runtime)
  if @mooncode_core.goal_runtime_is_terminal(state) {
    return Terminal
  }
  let next = @mooncode_core.reduce_goal_runtime(state, stored.event)
  if @mooncode_core.goal_runtime_handled_count(next) !=
    @mooncode_core.goal_runtime_handled_count(state) + 1 {
    mooncode_goal_runtime_store_corrupt(
      "supervisor event was not accepted by the goal runtime reducer",
    )
  }
  let canonical = encode_mooncode_goal_runtime_stored_event(stored)
  let payload = encode_mooncode_goal_runtime_carrier(
    mooncode_goal_runtime_carrier_from_event(canonical),
  )
  let appended = mooncode_append_session_journal_once_locked(
    book_root,
    session_id,
    mooncode_journal_event(),
    payload,
  )
  let committed_records = mooncode_goal_authority_records_locked(
    book_root, session_id,
  )
  let committed = mooncode_goal_authority_snapshot(
    committed_records, session_id,
  )
  if mooncode_goal_authority_is_dual(committed) || committed.legacy is Some(_) {
    mooncode_goal_runtime_store_corrupt(
      "goal authority changed while appending a supervisor event",
    )
  }
  guard committed.runtime.id_index.get(stored.id) is Some(winner) else {
    mooncode_goal_runtime_store_corrupt(
      "committed supervisor event disappeared",
    )
  }
  if winner.semantic_digest != stored.semantic_digest {
    raise MoonCodeGoalRuntimeStoreError::IdentityConflict(
      stored.id,
      winner.semantic_digest,
      stored.semantic_digest,
    )
  }
  ignore(mooncode_goal_runtime_state_from_scan(committed.runtime))
  if appended {
    Appended
  } else {
    Idempotent
  }
}

///|
fn mooncode_goal_runtime_event_id_from_source(
  role : String,
  source_id : String,
) -> String {
  "goal-runtime-" +
  role +
  "-" +
  mooncode_goal_runtime_sha256_hex(role + ":" + source_id)
}

///|
fn mooncode_goal_runtime_events_from_source(
  source : Json,
) -> Array[@mooncode_core.GoalRuntimeEvent] {
  let source_id = mooncode_json_string(source, "id", default="")
  if !mooncode_goal_runtime_canonical(source_id) {
    return []
  }
  let kind = mooncode_json_string(source, "kind", default="")
  if kind == "runtime.turn_started" {
    return [
      @mooncode_core.PhaseChanged(
        mooncode_goal_runtime_event_id_from_source("phase-running", source_id),
        @mooncode_core.Running,
      ),
    ]
  }
  if mooncode_json_string(source, "tool", default="") != "" &&
    mooncode_json_string(source, "status", default="") == "done" {
    return [
      @mooncode_core.OperationAccepted(
        mooncode_goal_runtime_event_id_from_source("operation", source_id),
        source_id,
      ),
    ]
  }
  if kind == mooncode_runtime_continuation_kind() {
    match mooncode_json_string(source, "state", default="") {
      "awaiting-approval" =>
        return [
          @mooncode_core.PhaseChanged(
            mooncode_goal_runtime_event_id_from_source(
              "phase-waiting-approval", source_id,
            ),
            @mooncode_core.WaitingApproval,
          ),
        ]
      "planner-quantum-paused" =>
        return [
          @mooncode_core.CheckpointAccepted(
            mooncode_goal_runtime_event_id_from_source("checkpoint", source_id),
            source_id,
          ),
          @mooncode_core.PhaseChanged(
            mooncode_goal_runtime_event_id_from_source(
              "phase-paused-external", source_id,
            ),
            @mooncode_core.PausedExternal,
          ),
        ]
      _ => ()
    }
  }
  []
}

///|
async fn mooncode_goal_runtime_reconcile_supervisor_events(
  book_root : String,
  session_id : String,
  sources : Array[Json],
  recorded_at : Int64,
) -> Unit {
  if !sources.any(fn(source) {
      mooncode_json_string(source, "kind", default="") ==
      mooncode_goal_runtime_carrier_kind_v1 &&
      mooncode_json_string(source, "logical_kind", default="") == "genesis"
    }) {
    return
  }
  let session_lock = mooncode_open_session_lock(book_root, session_id)
  defer session_lock.close()
  session_lock.lock(Exclusive)
  defer session_lock.unlock()
  let records = mooncode_goal_authority_records_locked(book_root, session_id)
  let authority = mooncode_goal_authority_snapshot(records, session_id)
  if mooncode_goal_authority_is_dual(authority) || authority.legacy is Some(_) {
    mooncode_goal_runtime_store_corrupt(
      "legacy goal authority cannot accept runtime supervisor events",
    )
  }
  guard authority.runtime.genesis is Some(genesis_entry) &&
    genesis_entry.carrier.record is Genesis(genesis) else {
    return
  }
  let state = mooncode_goal_runtime_state_from_scan(authority.runtime)
  if @mooncode_core.goal_runtime_is_terminal(state) {
    return
  }
  let known : Map[String, String] = {}
  for id, entry in authority.runtime.id_index.iter2() {
    known[id] = entry.semantic_digest
  }
  let active_commands : Map[String, Bool] = {}
  for source in sources {
    let source_kind = mooncode_json_string(source, "kind", default="")
    let source_command = mooncode_json_string(source, "command_id", default="")
    if source_kind == "runtime.turn_started" &&
      mooncode_goal_runtime_canonical(source_command) {
      active_commands[source_command] = true
    }
    let requires_active_turn = mooncode_json_string(source, "tool", default="") !=
      "" ||
      source_kind == mooncode_runtime_continuation_kind()
    if !requires_active_turn || active_commands.contains(source_command) {
      for event in mooncode_goal_runtime_events_from_source(source) {
        let stored = new_mooncode_goal_runtime_stored_event(
          session_id,
          genesis.goal_id,
          event,
          recorded_at,
        )
        match known.get(stored.id) {
          Some(digest) => {
            if digest != stored.semantic_digest {
              raise MoonCodeGoalRuntimeStoreError::IdentityConflict(
                stored.id,
                digest,
                stored.semantic_digest,
              )
            }
            continue
          }
          None => ()
        }
        match
          mooncode_goal_runtime_append_supervisor_event_locked(
            book_root,
            session_id,
            stored.event,
            recorded_at,
          ) {
          NoRuntimeGoal => return
          Terminal => return
          Appended | Idempotent => known[stored.id] = stored.semantic_digest
        }
      }
    }
    if source_kind == mooncode_event_runtime_turn_finished() ||
      source_kind == "runtime.turn_invalid" {
      active_commands.remove(source_command)
    }
  }
}

///|
async fn mooncode_goal_runtime_supervisor_is_active(
  book_root : String,
  session_id : String,
) -> Bool {
  let session_lock = mooncode_open_session_lock(book_root, session_id)
  defer session_lock.close()
  session_lock.lock(Shared)
  defer session_lock.unlock()
  let records = mooncode_goal_authority_records_locked(book_root, session_id)
  let authority = mooncode_goal_authority_snapshot(records, session_id)
  if mooncode_goal_authority_is_dual(authority) {
    mooncode_goal_runtime_store_corrupt("dual goal authority")
  }
  if authority.legacy is Some(_) {
    return false
  }
  match authority.runtime.genesis {
    None => false
    Some(_) =>
      !@mooncode_core.goal_runtime_is_terminal(
        mooncode_goal_runtime_state_from_scan(authority.runtime),
      )
  }
}
