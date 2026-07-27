// Aggregate-memory-independent durable goal projection.

///|
priv enum MoonCodeGoalIdentityResult {
  IdentityNew
  IdentitySeen
}

///|
priv struct MoonCodeGoalRuntimeProjection {
  cursor : MoonCodeJournalSequence
  genesis : MoonCodeGoalRuntimeIndexedEntry?
  phase : @mooncode_core.GoalRuntimePhase
  terminal : Bool
  outcome : String
  handled_count : MoonCodeJournalSequence
  operation_count : MoonCodeJournalSequence
  checkpoint_count : MoonCodeJournalSequence
  target_digest : String?
}

///|
fn mooncode_goal_runtime_empty_projection() -> MoonCodeGoalRuntimeProjection {
  {
    cursor: MoonCodeJournalSequence::zero(),
    genesis: None,
    phase: @mooncode_core.Queued,
    terminal: false,
    outcome: "none",
    handled_count: MoonCodeJournalSequence::zero(),
    operation_count: MoonCodeJournalSequence::zero(),
    checkpoint_count: MoonCodeJournalSequence::zero(),
    target_digest: None,
  }
}

///|
async fn mooncode_goal_identity_check_and_add(
  root : String,
  identity_space : String,
  id : String,
  digest : String,
) -> MoonCodeGoalIdentityResult {
  let key = identity_space + "\u{0}" + id
  let hash = mooncode_goal_runtime_sha256_hex(key)
  let path = @pathx.join(root, hash[:2].to_owned())
  if (@fsx.exists(path) catch { _ => false }) {
    let reader = @fs.open(path, mode=ReadOnly)
    defer reader.close()
    while true {
      match reader.read_until("\n") {
        Some(line) => {
          let json = @json.parse(line) catch {
            _ =>
              mooncode_goal_runtime_store_corrupt("identity ledger is corrupt")
          }
          if mooncode_json_string(json, "namespace", default="") ==
            identity_space &&
            mooncode_json_string(json, "id", default="") == id {
            let previous = mooncode_json_string(json, "digest", default="")
            if previous != digest {
              raise MoonCodeGoalRuntimeStoreError::IdentityConflict(
                id, previous, digest,
              )
            }
            return IdentitySeen
          }
        }
        None => break
      }
    }
  }
  let writer = @fs.open(
    path,
    mode=ReadWrite,
    append=true,
    create=0o600,
    truncate=false,
  )
  defer writer.close()
  writer.write(
    ({ "namespace": identity_space, "id": id, "digest": digest } : Json).stringify() +
    "\n",
  )
  IdentityNew
}

///|
fn mooncode_goal_record_with_sequence(
  record : Json,
  sequence : Int,
) -> Json raise MoonCodeGoalRuntimeStoreError {
  guard record is Object(fields) else {
    mooncode_goal_runtime_store_corrupt("journal record is not an object")
  }
  let copy = fields.copy()
  copy["sequence"] = if mooncode_json_string(record, "contract_id", default="") ==
    mooncode_journal_contract_id_v2() {
    sequence.to_string().to_json()
  } else {
    sequence.to_json()
  }
  Json::object(copy)
}

///|
fn mooncode_goal_runtime_carrier_from_stream_record(
  record : Json,
  genesis_record : Json?,
  expected_session_id : String,
) -> MoonCodeGoalRuntimeIndexedEntry? raise MoonCodeGoalRuntimeStoreError {
  let payload = mooncode_json_object_field_or_empty(record, "payload")
  let kind = mooncode_json_string(payload, "kind", default="")
  let shaped = kind.has_prefix("mooncode-goal-runtime-carrier.") ||
    mooncode_journal_json_field(payload, "logical_kind") is Some(_) ||
    mooncode_journal_json_field(payload, "semantic_digest") is Some(_) ||
    mooncode_journal_json_field(payload, "canonical_record") is Some(_)
  if !shaped {
    return None
  }
  let normalized = mooncode_goal_record_with_sequence(record, 1)
  let scan = if mooncode_json_string(payload, "logical_kind", default="") ==
    "genesis" {
    mooncode_goal_runtime_scan_records([normalized], expected_session_id)
  } else {
    guard genesis_record is Some(first) else {
      mooncode_goal_runtime_store_corrupt("event before genesis")
    }
    mooncode_goal_runtime_scan_records(
      [
        mooncode_goal_record_with_sequence(first, 1),
        mooncode_goal_record_with_sequence(record, 2),
      ],
      expected_session_id,
    )
  }
  match mooncode_json_string(payload, "logical_kind", default="") {
    "genesis" => scan.genesis
    "event" =>
      if scan.events.length() == 1 {
        Some(scan.events[0])
      } else {
        None
      }
    _ =>
      mooncode_goal_runtime_store_corrupt(
        "invalid runtime carrier logical kind",
      )
  }
}

///|
async fn mooncode_goal_runtime_apply_projected_event(
  projection : MoonCodeGoalRuntimeProjection,
  genesis : MoonCodeGoalRuntimeStoredGenesis,
  value : MoonCodeGoalRuntimeStoredEvent,
  ledger_root : String,
) -> MoonCodeGoalRuntimeProjection {
  if projection.terminal {
    mooncode_goal_runtime_store_corrupt(
      "unique runtime event follows terminal settlement",
    )
  }
  let mut next = {
    ..projection,
    handled_count: projection.handled_count.next(),
  }
  match value.event {
    @mooncode_core.PlannerDecision(_, @mooncode_core.Continue(operations, _, _)) => {
      next = { ..next, phase: @mooncode_core.Running }
      for operation in operations {
        if mooncode_goal_identity_check_and_add(
            ledger_root,
            "operation",
            operation.operation_id,
            "",
          )
          is IdentityNew {
          next = { ..next, operation_count: next.operation_count.next() }
        }
      }
    }
    @mooncode_core.PlannerDecision(_, @mooncode_core.Achieved(_, evidence)) => {
      if evidence.length() != genesis.criteria.length() {
        mooncode_goal_runtime_store_corrupt(
          "achieved evidence does not cover every genesis criterion",
        )
      }
      for criterion in genesis.criteria {
        if !evidence.any(item => item.criterion == criterion.id) {
          mooncode_goal_runtime_store_corrupt(
            "achieved evidence does not match genesis criteria",
          )
        }
      }
      next = { ..next, terminal: true, outcome: "achieved" }
    }
    @mooncode_core.PlannerDecision(_, @mooncode_core.Blocked(_, _, _)) =>
      next = { ..next, terminal: true, outcome: "blocked" }
    @mooncode_core.OperationAccepted(_, operation_id) =>
      if mooncode_goal_identity_check_and_add(
          ledger_root, "operation", operation_id, "",
        )
        is IdentityNew {
        next = { ..next, operation_count: next.operation_count.next() }
      }
    @mooncode_core.CheckpointAccepted(_, checkpoint_id) =>
      if mooncode_goal_identity_check_and_add(
          ledger_root, "checkpoint", checkpoint_id, "",
        )
        is IdentityNew {
        next = { ..next, checkpoint_count: next.checkpoint_count.next() }
      }
    @mooncode_core.PhaseChanged(_, phase) => next = { ..next, phase, }
    @mooncode_core.Cancelled(_, _) =>
      next = { ..next, terminal: true, outcome: "cancelled" }
  }
  next
}

///|
async fn mooncode_goal_authority_project_file(
  file : @fs.File,
  expected_session_id : String,
  target_runtime_id? : String? = None,
) -> MoonCodeGoalAuthorityProjection {
  @moonclaw_fsx.with_temporary_directory("moonclaw-goal-projection-XXXXXX", async fn(
    ledger_root,
  ) {
    let mut runtime = mooncode_goal_runtime_empty_projection()
    let mut legacy : @mooncode_core.Goal? = None
    let mut genesis_record : Json? = None
    while true {
      match file.read_until("\n") {
        Some(line) => {
          let (record, cursor) = mooncode_journal_stream_record(
            line,
            runtime.cursor,
          )
          if mooncode_json_string(record, "session_id", default="") !=
            expected_session_id {
            raise InvalidJournal(
              "journal record belongs to a different session",
            )
          }
          runtime = { ..runtime, cursor, }
          match mooncode_replay_goal_records([record], expected_session_id) {
            Some(goal) => {
              if legacy is Some(_) {
                raise InvalidGoalGenesis("duplicate goal genesis")
              }
              legacy = Some(goal)
            }
            None => ()
          }
          match
            mooncode_goal_runtime_carrier_from_stream_record(
              record, genesis_record, expected_session_id,
            ) {
            None => ()
            Some(entry) => {
              let carrier = entry.carrier
              let identity = mooncode_goal_identity_check_and_add(
                ledger_root,
                "runtime-event",
                carrier.id,
                carrier.semantic_digest,
              )
              match target_runtime_id {
                Some(target) if target == carrier.id =>
                  runtime = {
                    ..runtime,
                    target_digest: Some(carrier.semantic_digest),
                  }
                _ => ()
              }
              if identity is IdentitySeen {
                continue
              }
              match carrier.record {
                Genesis(_) => {
                  if runtime.genesis is Some(_) {
                    mooncode_goal_runtime_store_corrupt("second genesis")
                  }
                  runtime = { ..runtime, genesis: Some(entry) }
                  genesis_record = Some(record)
                }
                Event(value) => {
                  guard runtime.genesis is Some(first) &&
                    first.carrier.record is Genesis(genesis) else {
                    mooncode_goal_runtime_store_corrupt("event before genesis")
                  }
                  if value.goal_id != genesis.goal_id {
                    mooncode_goal_runtime_store_corrupt("event goal mismatch")
                  }
                  runtime = mooncode_goal_runtime_apply_projected_event(
                    runtime, genesis, value, ledger_root,
                  )
                }
              }
            }
          }
        }
        None => break
      }
    }
    MoonCodeGoalAuthorityProjection::{ legacy, runtime }
  })
}

///|
async fn mooncode_goal_authority_project_locked(
  book_root : String,
  session_id : String,
  target_runtime_id? : String? = None,
) -> MoonCodeGoalAuthorityProjection {
  let path = mooncode_session_journal_path(book_root, session_id)
  if !(@fsx.exists(path) catch { _ => false }) {
    return { legacy: None, runtime: mooncode_goal_runtime_empty_projection() }
  }
  let file = @fs.open(path, mode=ReadWrite, append=false)
  defer file.close()
  file.lock(Exclusive)
  defer file.unlock()
  mooncode_repair_journal_tail(file)
  mooncode_goal_authority_project_file(file, session_id, target_runtime_id~)
}

///|
fn mooncode_goal_runtime_projection_count_json(
  count : MoonCodeJournalSequence,
) -> Json raise MoonCodeGoalRuntimeStoreError {
  @json.parse(count.text()) catch {
    _ => mooncode_goal_runtime_store_corrupt("runtime count is not JSON")
  }
}

///|
fn mooncode_goal_runtime_projection_status_response(
  projection : MoonCodeGoalRuntimeProjection,
  status_code? : Int = 200,
) -> MoonCodeGoalRuntimeApiResponse raise {
  guard projection.genesis is Some(entry) &&
    entry.carrier.record is Genesis(genesis) else {
    return mooncode_goal_runtime_api_error(404, "goal_runtime_not_found")
  }
  let canonical = encode_mooncode_goal_runtime_genesis(genesis)
  let genesis_json = @json.parse(canonical) catch {
    _ => mooncode_goal_runtime_fail("canonical genesis is invalid JSON")
  }
  mooncode_goal_runtime_api_response(status_code, {
    "kind": "mooncode-goal-runtime-status",
    "protocol": mooncode_goal_runtime_protocol_v1,
    "owner": "moonclaw",
    "contract": mooncode_goal_runtime_contract_v1,
    "session_id": genesis.session_id,
    "goal_id": genesis.goal_id,
    "cursor": projection.cursor.text(),
    "genesis": genesis_json,
    "status": {
      "contract": mooncode_goal_runtime_contract_v1,
      "phase": match projection.phase {
        @mooncode_core.Queued => "queued"
        @mooncode_core.Running => "running"
        @mooncode_core.WaitingApproval => "waiting_approval"
        @mooncode_core.RetryBackoff => "retry_backoff"
        @mooncode_core.PausedNoProgress => "paused_no_progress"
        @mooncode_core.PausedExternal => "paused_external"
      },
      "terminal": projection.terminal,
      "outcome": projection.outcome,
      "handled_count": mooncode_goal_runtime_projection_count_json(
        projection.handled_count,
      ),
      "operation_count": mooncode_goal_runtime_projection_count_json(
        projection.operation_count,
      ),
      "checkpoint_count": mooncode_goal_runtime_projection_count_json(
        projection.checkpoint_count,
      ),
    },
  })
}
