///|
fn cowork_starts_action(msg : Msg) -> Bool {
  match msg {
    CreateCoworkSession
    | SendCoworkMessage
    | StartCoworkPlan
    | PreviewCoworkPlan
    | PromoteCoworkPlan
    | ConfirmCoworkProposal(_)
    | ResumeCoworkRun(_)
    | SaveCoworkConfig
    | RunQueuedCoworkDraft(_) => true
    _ => false
  }
}

///|
fn cowork_ready_to_send(model : Model) -> Bool {
  !model.cowork_action_loading &&
  !cowork_thread_request_pending(model) &&
  !model.cowork_detail_loading &&
  model.route is Cowork &&
  (match (model.selected_cowork_session_key, model.cowork_detail) {
    (Some(key), Some(detail)) => key == detail.session.session_key
    _ => false
  })
}

///|
fn cowork_thread_request_pending(model : Model) -> Bool {
  model.cowork_pending_requests.any(request => {
    Some(request.session_key) == model.selected_cowork_session_key
  })
}

///|
fn cowork_consumes_draft(msg : Msg) -> Bool {
  match msg {
    SendCoworkMessage
    | StartCoworkPlan
    | PreviewCoworkPlan
    | PromoteCoworkPlan
    | ResumeCoworkRun(_) => true
    _ => false
  }
}

///|
fn cowork_has_pending_request(
  model : Model,
  generation : Int,
  key : String,
  revision : Int,
  consumes : Bool,
) -> Bool {
  model.cowork_pending_requests.any(request => {
    request.generation == generation &&
    request.session_key == key &&
    request.draft_revision == revision &&
    request.consumes_draft == consumes
  })
}

///|
fn cowork_settle_request(
  model : Model,
  generation : Int,
  key : String,
  revision : Int,
  consumes : Bool,
  confirmed : Bool,
) -> Model {
  let clear = confirmed && consumes
  let clear_current = clear &&
    model.selected_cowork_session_key == Some(key) &&
    model.cowork_draft_revision == revision
  {
    ..model,
    cowork_pending_requests: model.cowork_pending_requests.filter(request => {
      request.generation != generation
    }),
    cowork_saved_drafts: model.cowork_saved_drafts.filter(draft => {
      !(clear && draft.session_key == Some(key) && draft.revision == revision)
    }),
    cowork_composer: if clear_current {
      ""
    } else {
      model.cowork_composer
    },
    cowork_local_uploads: if clear_current {
      []
    } else {
      model.cowork_local_uploads
    },
    cowork_context_chips: if clear_current {
      []
    } else {
      model.cowork_context_chips
    },
    cowork_reply_preview: if clear_current {
      None
    } else {
      model.cowork_reply_preview
    },
  }
}

///|
fn cowork_action_is_current(
  model : Model,
  generation : Int,
  key : String,
) -> Bool {
  model.cowork_action_loading &&
  !model.cowork_create_pending &&
  model.cowork_request_generation == generation &&
  model.selected_cowork_session_key == Some(key) &&
  model.route is Cowork
}

///|
fn cowork_request_ownership(before : Model, after : Model, msg : Msg) -> Model {
  let after = if cowork_starts_action(msg) && after.cowork_action_loading {
    {
      ..after,
      cowork_request_generation: before.cowork_request_generation + 1,
      cowork_pending_requests: if !(msg is CreateCoworkSession) &&
        before.selected_cowork_session_key is Some(key) {
        [
          ..before.cowork_pending_requests,
          {
            generation: before.cowork_request_generation + 1,
            session_key: key,
            draft_revision: before.cowork_draft_revision,
            consumes_draft: cowork_consumes_draft(msg),
          },
        ]
      } else {
        after.cowork_pending_requests
      },
    }
  } else {
    after
  }
  let accepted_create = match msg {
    CoworkSessionCreated(generation, Ok(_)) =>
      before.cowork_create_pending &&
      generation == before.cowork_request_generation
    _ => false
  }
  // Creating a thread transfers the current draft; a stale cached origin slot
  // must not revive that same request after it has been sent from the new thread.
  let after = if accepted_create {
    {
      ..after,
      cowork_saved_drafts: after.cowork_saved_drafts.filter(draft => {
        draft.session_key != before.selected_cowork_session_key &&
        draft.session_key != after.selected_cowork_session_key
      }),
    }
  } else {
    after
  }
  let after = if !accepted_create &&
    before.selected_cowork_session_key != after.selected_cowork_session_key {
    let drafts = before.cowork_saved_drafts.filter(draft => {
      draft.session_key != before.selected_cowork_session_key
    })
    drafts.push({
      session_key: before.selected_cowork_session_key,
      revision: before.cowork_draft_revision,
      content: before.cowork_composer,
      uploads: before.cowork_local_uploads,
      context: before.cowork_context_chips,
      reply: before.cowork_reply_preview,
    })
    let restored = drafts
      .filter(draft => draft.session_key == after.selected_cowork_session_key)
      .get(0)
    {
      ..after,
      cowork_saved_drafts: drafts,
      cowork_composer: restored.map(draft => draft.content).unwrap_or(""),
      cowork_local_uploads: restored.map(draft => draft.uploads).unwrap_or([]),
      cowork_context_chips: restored.map(draft => draft.context).unwrap_or([]),
      cowork_reply_preview: restored.map(draft => draft.reply).unwrap_or(None),
      cowork_draft_revision: restored.map(draft => draft.revision).unwrap_or(0),
    }
  } else {
    after
  }
  // Navigation parks the current request. A late response may still exist in
  // the server's thread history, but must not retarget this screen or its draft.
  let after = if !accepted_create &&
    (
      before.route != after.route ||
      before.selected_cowork_session_key != after.selected_cowork_session_key
    ) {
    {
      ..after,
      cowork_request_generation: after.cowork_request_generation + 1,
      cowork_create_pending: false,
      cowork_action_loading: false,
      cowork_action_error: None,
      cowork_detail_generation: if msg is UrlChanged(_) {
        after.cowork_detail_generation + 1
      } else {
        after.cowork_detail_generation
      },
    }
  } else {
    after
  }
  if before.selected_cowork_session_key == after.selected_cowork_session_key &&
    cowork_composer_content(before, before.cowork_composer) !=
    cowork_composer_content(after, after.cowork_composer) {
    { ..after, cowork_draft_revision: before.cowork_draft_revision + 1, }
  } else {
    after
  }
}
