///|
/// Optional trusted owner/model root. It never supplies execution cwd or tools.
fn mooncode_command_model_workspace(body : Json) -> Result[String, String] {
  guard body is Object(fields) else {
    return Err("MoonCode command must be an object")
  }
  match fields.get("model_workspace") {
    None => Ok("")
    Some(String(root)) if root != "" &&
      root == root.trim().to_owned() &&
      @pathx.is_absolute(root) => Ok(root)
    _ => Err("model_workspace must be a nonempty absolute path when supplied")
  }
}

///|
async fn mooncode_model_workspace_is_canonical(root : String) -> Bool {
  if root == "" {
    return true
  }
  (@fs.realpath(root) == root && @fs.kind(root) == Directory) catch {
    _ => false
  }
}

///|
/// A saved session may inherit its owner, but neither a legacy session nor an
/// explicit-owner session can be rebound after its first accepted command.
fn mooncode_command_with_model_workspace(
  body : Json,
  accepted_root : String?,
) -> Result[Json, String] {
  let requested = match mooncode_command_model_workspace(body) {
    Ok(root) => root
    Err(error) => return Err(error)
  }
  match accepted_root {
    Some(root) => {
      if requested != "" && requested != root {
        return Err(
          "MoonCode session is already bound to a different model workspace",
        )
      }
      if root != "" {
        Ok(
          mooncode_json_object_with_field(
            body,
            "model_workspace",
            root.to_json(),
          ),
        )
      } else {
        Ok(body)
      }
    }
    None => Ok(body)
  }
}

///|
/// Read the authoritative first command, including a legacy omitted root. A
/// torn/missing/stale sidecar cannot retarget an accepted session on restart.
fn mooncode_journal_model_workspace(
  journal : Array[Json],
) -> String? raise MoonCodeJournalError {
  let mut accepted : String? = None
  for entry in mooncode_journal_entries(journal, mooncode_journal_command()) {
    let body = mooncode_json_object_field_or_empty(entry, "command")
    let root = match mooncode_command_model_workspace(body) {
      Ok(root) => root
      Err(error) => raise InvalidJournal(error)
    }
    match accepted {
      None => accepted = Some(root)
      Some(previous) if previous != root =>
        raise InvalidJournal(
          "MoonCode journal changes model_workspace within a session",
        )
      _ => ()
    }
  }
  accepted
}

///|
/// The common admission/initial/follow-up resolution policy. Explicit owner
/// lookup is exclusive: a same-named daemon or source model is never fallback.
async fn[T] mooncode_resolve_model_workspace(
  command : Json,
  selector : String,
  legacy_source_fallback? : Bool = true,
  owner_lookup~ : async (String, String) -> T?,
  daemon_lookup~ : async (String) -> T?,
  source_lookup~ : async (String, String) -> T?,
) -> T? {
  let owner = match mooncode_command_model_workspace(command) {
    Ok(root) => root
    Err(_) => return None
  }
  if owner != "" {
    return owner_lookup(owner, selector)
  }
  match daemon_lookup(selector) {
    Some(model) => Some(model)
    None => {
      let source = mooncode_book_root(command)
      if source == "" || !legacy_source_fallback {
        None
      } else {
        source_lookup(source, selector)
      }
    }
  }
}

///|
/// Locked command acceptance shares the same journal transaction as identity
/// checks; concurrent callers cannot bind two owners to one session.
async fn mooncode_persist_bound_command(
  book_root : String,
  session_id : String,
  body : Json,
  payload : Json,
) -> Bool {
  mooncode_session_journal_transaction(book_root, session_id, journal => {
    let accepted = mooncode_journal_model_workspace(journal)
    let root = match mooncode_command_model_workspace(body) {
      Ok(root) => root
      Err(error) => raise InvalidJournal(error)
    }
    if accepted is Some(previous) && previous != root {
      raise InvalidJournal(
        "MoonCode session model workspace changed during command admission",
      )
    }
    for entry in mooncode_journal_entries(journal, mooncode_journal_command()) {
      if mooncode_json_string(entry, "command_id", default="") ==
        mooncode_command_id(body) {
        if mooncode_json_object_field_or_empty(entry, "command").stringify() !=
          body.stringify() {
          raise InvalidJournal(
            "MoonCode command ID is already used for a different command",
          )
        }
        return NoAppend(false)
      }
    }
    Append(mooncode_journal_command(), payload, true)
  })
}
