///|
fn close_artifact_viewer(model : Model) -> Model {
  {
    ..model,
    artifact_pending_id: None,
    artifact_modal_loading: false,
    artifact_modal_error: None,
    artifact_modal: None,
    artifact_editor_draft: "",
  }
}

///|
fn open_artifact_viewer(
  dispatch : Dispatch[Msg],
  model : Model,
  artifact_id : String,
) -> (Cmd, Model) {
  // Each open has a distinct generation, including retries of the same ID.
  let generation = model.artifact_request_generation + 1
  (
    fetch_artifact(dispatch, model.gateway_base, artifact_id, generation),
    {
      ..model,
      artifact_request_generation: generation,
      artifact_pending_id: Some(artifact_id),
      artifact_modal_loading: true,
      artifact_modal_error: None,
      artifact_modal: None,
      artifact_editor_draft: "",
    },
  )
}

///|
fn artifact_request_is_current(
  model : Model,
  artifact_id : String,
  generation : Int,
) -> Bool {
  model.artifact_pending_id == Some(artifact_id) &&
  model.artifact_request_generation == generation
}

///|
fn artifact_context_changed(previous : Model, current : Model) -> Bool {
  let workspace_changed = match
    (previous.cowork_workspace_snapshot, current.cowork_workspace_snapshot) {
    (Some(old), Some(next)) => old.root != next.root
    _ => false
  }
  let session_workspace_changed = match
    (previous.cowork_detail, current.cowork_detail) {
    (Some(old), Some(next)) => old.session.cwd != next.session.cwd
    _ => false
  }
  previous.gateway_base != current.gateway_base ||
  previous.route != current.route ||
  previous.selected_run_id != current.selected_run_id ||
  previous.selected_cowork_session_key != current.selected_cowork_session_key ||
  (
    previous.route is Cowork &&
    current.route is Cowork &&
    (workspace_changed || session_workspace_changed)
  )
}
