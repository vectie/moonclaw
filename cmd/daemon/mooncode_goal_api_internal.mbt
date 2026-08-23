///|
/// Nofollow state of the durable session journal used by the goal API.
priv enum MoonCodeGoalJournalProbe {
  Missing
  Ready
  Corrupt
  Unavailable
}

///|
async fn mooncode_goal_journal_probe(
  book_root : String,
  session_id : String,
) -> MoonCodeGoalJournalProbe {
  let path = mooncode_session_journal_path(book_root, session_id)
  let kind = @fs.kind(path, follow_symlink=false) catch {
    @os_error.OSError(_) as error if error.is_ENOENT() => return Missing
    @os_error.OSError(_) => return Unavailable
    _ => return Unavailable
  }
  match kind {
    Regular => Ready
    _ => Corrupt
  }
}

///|
priv suberror MoonCodeGoalCommittedPrefixReadError {
  Io
  Corrupt
}

///|
/// Read only complete newline-terminated records for goal API preflight. A torn
/// suffix is ignored in memory and the canonical replay path remains untouched.
async fn mooncode_goal_read_committed_prefix(
  path : String,
) -> String raise MoonCodeGoalCommittedPrefixReadError {
  let file = @fs.open(path, mode=ReadOnly) catch { _ => raise Io }
  defer file.close()
  let size = file.size() catch { _ => raise Io }
  if size == 0L {
    return ""
  }
  if size > 0x7fffffffL {
    raise Io
  }
  let bytes = file.read_exactly_at(size.to_int(), position=0L) catch {
    _ => raise Io
  }
  let mut committed_size = 0
  let mut index = 0
  while index < bytes.length() {
    if bytes[index] == b'\n' {
      committed_size = index + 1
    }
    index += 1
  }
  @encoding/utf8.decode(bytes[:committed_size]) catch {
    _ => raise Corrupt
  }
}

///|
async fn mooncode_goal_api_get_internal(
  book_root : String,
  session_id : String,
) -> MoonCodeGoalApiResponse {
  ignore(mooncode_goal_require_active_session(session_id, book_root)) catch {
    InvalidGoalSessionQuery =>
      return goal_api_error(400, "invalid_goal_session_query")
    GoalSessionAbsentOrMismatch =>
      return goal_api_error(404, "goal_session_not_found")
    GoalSessionCorrupt => return goal_api_error(409, "goal_session_corrupt")
  }
  let journal_path = mooncode_session_journal_path(book_root, session_id)
  match mooncode_goal_journal_probe(book_root, session_id) {
    Missing => goal_api_error(404, "goal_not_found")
    Corrupt => goal_api_error(409, "goal_corrupt")
    Unavailable => goal_api_error(500, "internal_error")
    Ready => {
      let text = mooncode_goal_read_committed_prefix(journal_path) catch {
        Corrupt => return goal_api_error(409, "goal_corrupt")
        Io => return goal_api_error(500, "internal_error")
      }
      let records = mooncode_parse_journal_text(text, journal_path) catch {
        _ => return goal_api_error(409, "goal_corrupt")
      }
      let runtime = mooncode_goal_runtime_scan_records(records, session_id) catch {
        CorruptStore(_) => return goal_api_error(409, "goal_corrupt")
        IdentityConflict(_, _, _) => return goal_api_error(409, "goal_corrupt")
      }
      let goal = mooncode_replay_goal_records(records, session_id) catch {
        InvalidGoalGenesis(_) => return goal_api_error(409, "goal_corrupt")
        _ => return goal_api_error(500, "internal_error")
      }
      if goal is Some(_) && runtime.genesis is Some(_) {
        return goal_api_error(409, "goal_authority_conflict")
      }
      match goal {
        Some(goal) => goal_api_status(goal)
        None => goal_api_error(404, "goal_not_found")
      }
    }
  }
}

///|
async fn mooncode_goal_api_put_internal(
  book_root : String,
  session_id : String,
  body : Json,
  epoch_seconds : Int64,
) -> MoonCodeGoalApiResponse {
  let request = mooncode_parse_goal_put_request(body, session_id) catch {
    InvalidGoalRequest(_) => return goal_api_error(400, "invalid_goal_request")
  }
  ignore(mooncode_goal_require_active_session(session_id, book_root)) catch {
    InvalidGoalSessionQuery =>
      return goal_api_error(400, "invalid_goal_session_query")
    GoalSessionAbsentOrMismatch =>
      return goal_api_error(404, "goal_session_not_found")
    GoalSessionCorrupt => return goal_api_error(409, "goal_session_corrupt")
  }
  let created_at = match goal_api_checked_epoch_seconds(epoch_seconds) {
    Some(value) => value
    None => return goal_api_error(500, "goal_clock_out_of_range")
  }
  // The journal is trusted only after strict parsing/replay. This API currently assumes a
  // single daemon and a non-adversarial filesystem; locking and the remaining probe/open
  // TOCTOU hardening are deferred.
  match mooncode_goal_journal_probe(book_root, session_id) {
    Corrupt => return goal_api_error(409, "goal_corrupt")
    Unavailable => return goal_api_error(500, "internal_error")
    Ready => {
      let existing = mooncode_goal_read_committed_prefix(
        mooncode_session_journal_path(book_root, session_id),
      ) catch {
        Corrupt => return goal_api_error(409, "goal_corrupt")
        Io => return goal_api_error(500, "internal_error")
      }
      let records = mooncode_parse_journal_text(
        existing,
        mooncode_session_journal_path(book_root, session_id),
      ) catch {
        InvalidJournal(_) => return goal_api_error(409, "goal_corrupt")
      }
      ignore(mooncode_replay_goal_records(records, session_id)) catch {
        InvalidGoalGenesis(_) => return goal_api_error(409, "goal_corrupt")
        _ => return goal_api_error(500, "internal_error")
      }
    }
    Missing => ()
  }
  let result = mooncode_create_goal(
    book_root,
    mooncode_protocol_version(),
    request.session_id,
    request.goal_id,
    request.objective,
    created_at,
    request.budget,
    request.requirements,
  ) catch {
    InvalidJournal(_) | InvalidGoalGenesis(_) =>
      return goal_api_error(409, "goal_corrupt")
    _ => return goal_api_error(500, "internal_error")
  }
  match result {
    Created(goal) => goal_api_created(goal)
    Idempotent(goal) => goal_api_status(goal)
    Conflict(_) => goal_api_error(409, "goal_conflict")
    AuthorityConflict => goal_api_error(409, "goal_authority_conflict")
  }
}
