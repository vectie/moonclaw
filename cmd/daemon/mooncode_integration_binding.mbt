///|
fn mooncode_integration_binding_path(
  config : @moondesk_sandbox_config.Config,
  session_id : String,
  suffix : String,
) -> String {
  @pathx.join(
    config.workspace_root,
    ".moonsuite/products/moonclaw/mooncode/integration-bindings/" +
    session_id +
    suffix,
  )
}

///|
fn mooncode_integration_check_binding(
  config : @moondesk_sandbox_config.Config,
  session_id : String,
  book_root : String,
) -> Unit raise {
  let path = mooncode_integration_binding_path(config, session_id, ".json")
  let existing = @book_runtime.read_resource(path)
  guard existing is Some(text) else {
    raise json_error(409, "Conflict", {
      "error": { "message": "Session has no recorded Book binding" },
    })
  }
  {
    let record = @json.parse(text) catch {
      _ =>
        raise json_error(409, "Conflict", {
          "error": { "message": "Session binding record is invalid" },
        })
    }
    guard mooncode_json_string(record, "session_id", default="") == session_id &&
      mooncode_json_string(record, "book_root", default="") == book_root else {
      raise json_error(409, "Conflict", {
        "error": {
          "message": "Session is already bound to a different Book or identity",
        },
      })
    }
  }
  // Retain conflict checks for visible legacy stores; never infer a new binding.
  for root in config.trusted_book_roots.unwrap_or([]) {
    for archived in [false, true] {
      let snapshot_path = mooncode_session_snapshot_path_by_safe_id(
        root,
        session_id,
        archived~,
      )
      if @book_runtime.read_resource(snapshot_path) is Some(text) {
        let snapshot = @json.parse(text) catch {
          _ =>
            raise json_error(409, "Conflict", {
              "error": { "message": "Existing session metadata is invalid" },
            })
        }
        guard mooncode_json_string(snapshot, "session_id", default="") ==
          session_id else {
          raise json_error(409, "Conflict", {
            "error": { "message": "Existing session identity does not match" },
          })
        }
        let stored_root = mooncode_json_string(
          snapshot,
          "book_root",
          default="",
        )
        guard stored_root == book_root else {
          raise json_error(409, "Conflict", {
            "error": {
              "message": "Session has an existing binding to a different Book",
            },
          })
        }
      }
    }
  }
}
