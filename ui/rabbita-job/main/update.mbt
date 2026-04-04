///|
fn snapshot_matches_run(snapshot : UiSnapshot?, run_id : String) -> Bool {
  match snapshot {
    Some(snapshot) => snapshot.run.id == run_id
    None => false
  }
}

///|
fn sync_cowork_session_fields(
  model : Model,
  detail : CoworkSessionDetail,
) -> Model {
  {
    ..model,
    cowork_title_override: detail.session.title,
    cowork_model_override: detail.session.model_override.unwrap_or(""),
    cowork_provider_override: detail.session.provider_override.unwrap_or(""),
    cowork_cwd_override: detail.session.cwd.unwrap_or(""),
  }
}

///|
fn cowork_composer_content(model : Model, content : String) -> String {
  let chip_lines = if model.cowork_context_chips.is_empty() {
    []
  } else {
    [
      "Attached context:",
      ..model.cowork_context_chips.map(fn(chip) {
        "### \{chip.label}\n\{chip.content}"
      }),
      "",
    ]
  }
  match model.cowork_reply_preview {
    Some(preview) => {
      let quoted = preview.replace(old="\n", new="\n> ").to_string()
      [..chip_lines, "Replying to:", "> \{quoted}", "", content].join("\n")
    }
    None =>
      if chip_lines.is_empty() {
        content
      } else {
        [..chip_lines, content].join("\n")
      }
  }
}

///|
fn push_cowork_input_history(model : Model, content : String) -> Model {
  let trimmed = content.trim().to_string()
  if trimmed.is_blank() {
    { ..model, cowork_input_history_index: None }
  } else {
    let deduped = model.cowork_input_history.filter(fn(item) { item != trimmed })
    let history = [trimmed, ..deduped]
    let limited : Array[String] = []
    let count = if history.length() > 30 { 30 } else { history.length() }
    for index in 0..<count {
      limited.push(history[index])
    }
    { ..model, cowork_input_history: limited, cowork_input_history_index: None }
  }
}

///|
fn queued_cowork_draft_content(draft : QueuedCoworkDraft) -> String {
  match draft.quoted_preview {
    Some(preview) => {
      let quoted = preview.replace(old="\n", new="\n> ").to_string()
      ["Replying to:", "> \{quoted}", "", draft.content].join("\n")
    }
    None => draft.content
  }
}

///|
fn next_queued_cowork_draft(model : Model) -> QueuedCoworkDraft? {
  if model.cowork_queue_paused {
    return None
  }
  match model.cowork_draft_queue {
    [first, ..] => Some(first)
    _ => None
  }
}

///|
fn queued_cowork_draft_by_id(
  model : Model,
  draft_id : String,
) -> QueuedCoworkDraft? {
  for draft in model.cowork_draft_queue {
    if draft.id == draft_id {
      return Some(draft)
    }
  }
  None
}

///|
fn move_draft_by_offset(
  drafts : Array[QueuedCoworkDraft],
  draft_id : String,
  delta : Int,
) -> Array[QueuedCoworkDraft] {
  let copied = drafts.copy()
  let mut found_index = -1
  for index in 0..<copied.length() {
    if copied[index].id == draft_id {
      found_index = index
      break
    }
  }
  if found_index < 0 {
    return copied
  }
  let target = found_index + delta
  if target < 0 || target >= copied.length() {
    return copied
  }
  let item = copied[found_index]
  copied[found_index] = copied[target]
  copied[target] = item
  copied
}

///|
fn update(dispatch : Dispatch[Msg], msg : Msg, model : Model) -> (Cmd, Model) {
  match msg {
    LoadRuns =>
      (
        fetch_runs(dispatch, model.gateway_base),
        { ..model, runs_loading: true, runs_error: None },
      )
    LoadAcp =>
      (
        batch([
          fetch_acp_snapshot(dispatch, model.gateway_base),
          fetch_acp_timeline(dispatch, model.gateway_base),
          start_acp_stream_cmd(dispatch, model.gateway_base),
        ]),
        { ..model, acp_loading: true, acp_error: None },
      )
    LoadCoworkSessions =>
      (
        fetch_cowork_sessions(dispatch, model.gateway_base),
        { ..model, cowork_sessions_loading: true, cowork_sessions_error: None },
      )
    RunsLoaded(Ok(runs)) => {
      let next_model = { ..model, runs, runs_loading: false, runs_error: None }
      match model.route {
        Run(run_id) =>
          if model.selected_run_id == Some(run_id) &&
            snapshot_matches_run(model.snapshot, run_id) {
            (@rabbita.none, next_model)
          } else {
            (
              batch([
                load_run_cmd(dispatch, model.gateway_base, run_id),
                start_stream_cmd(dispatch, model.gateway_base, run_id),
              ]),
              {
                ..next_model,
                selected_run_id: Some(run_id),
                detail_loading: true,
                detail_error: None,
                artifact_modal_loading: false,
                artifact_modal_error: None,
                artifact_modal: None,
                artifact_editor_draft: "",
              },
            )
          }
        _ => (@rabbita.none, next_model)
      }
    }
    RunsLoaded(Err(error)) =>
      (@rabbita.none, { ..model, runs_loading: false, runs_error: Some(error) })
    SelectRun(run_id) =>
      (
        @nav.push_url(
          run_url(
            run_id,
            runs_status_filter=model.runs_status_filter,
            runs_query=model.runs_query,
            runs_sort=model.runs_sort,
            runs_page=model.runs_page,
          ),
        ),
        {
          ..model,
          route: Run(run_id),
          selected_run_id: Some(run_id),
          snapshot: None,
          timeline: [],
          fresh_node_ids: [],
          fresh_timeline_ids: [],
          focused_node_id: None,
          timeline_scope_node_id: None,
          timeline_scope_branch_only: false,
          collapsed_node_ids: [],
          expanded_node_ids: [],
          detail_loading: true,
          detail_error: None,
          artifact_modal_loading: false,
          artifact_modal_error: None,
          artifact_modal: None,
          artifact_editor_draft: "",
        },
      )
    LoadRun(run_id) =>
      (
        batch([
          load_run_cmd(dispatch, model.gateway_base, run_id),
          start_stream_cmd(dispatch, model.gateway_base, run_id),
        ]),
        {
          ..model,
          route: Run(run_id),
          selected_run_id: Some(run_id),
          snapshot: None,
          timeline: [],
          fresh_node_ids: [],
          fresh_timeline_ids: [],
          focused_node_id: None,
          timeline_scope_node_id: None,
          timeline_scope_branch_only: false,
          collapsed_node_ids: [],
          expanded_node_ids: [],
          detail_loading: true,
          detail_error: None,
          artifact_modal_loading: false,
          artifact_modal_error: None,
          artifact_modal: None,
          artifact_editor_draft: "",
        },
      )
    PollRun(run_id) =>
      if model.selected_run_id == Some(run_id) {
        (
          batch([
            fetch_runs(dispatch, model.gateway_base),
            fetch_snapshot(dispatch, model.gateway_base, run_id),
          ]),
          model,
        )
      } else {
        (@rabbita.none, model)
      }
    CoworkSessionsLoaded(Ok(sessions)) => {
      let next_model = {
        ..model,
        cowork_sessions: sessions,
        cowork_sessions_loading: false,
        cowork_sessions_error: None,
      }
      match (model.route, model.selected_cowork_session_key) {
        (Cowork, Some(session_key)) =>
          (
            fetch_cowork_session(dispatch, model.gateway_base, session_key),
            {
              ..next_model,
              cowork_detail_loading: true,
              cowork_detail_error: None,
            },
          )
        (Cowork, None) =>
          match sessions {
            [first, ..] =>
              (
                @nav.push_url(
                  cowork_url(
                    selected_session_key=Some(first.session_key),
                    panel=model.cowork_panel,
                  ),
                ),
                {
                  ..next_model,
                  selected_cowork_session_key: Some(first.session_key),
                },
              )
            _ => (@rabbita.none, next_model)
          }
        _ => (@rabbita.none, next_model)
      }
    }
    CoworkSessionsLoaded(Err(error)) =>
      (
        @rabbita.none,
        {
          ..model,
          cowork_sessions_loading: false,
          cowork_sessions_error: Some(error),
        },
      )
    CreateCoworkSession =>
      (
        create_cowork_session(dispatch, model.gateway_base),
        { ..model, cowork_action_loading: true, cowork_action_error: None },
      )
    CoworkSessionCreated(Ok(session)) => {
      let next_model = sync_cowork_session_fields(
        {
          ..model,
          cowork_action_loading: false,
          cowork_action_error: None,
          cowork_detail: Some(session),
          selected_cowork_session_key: Some(session.session.session_key),
          cowork_detail_loading: false,
          cowork_detail_error: None,
          cowork_composer: "",
          cowork_reply_to_message_id: None,
          cowork_reply_preview: None,
          cowork_notice: Some("Conversation created."),
        },
        session,
      )
      (
        batch([
          fetch_cowork_sessions(dispatch, model.gateway_base),
          fetch_cowork_workspace(dispatch, model.gateway_base),
          match session.linked_run {
            Some(run) =>
              fetch_cowork_linked_snapshot(dispatch, model.gateway_base, run.id)
            None => @rabbita.none
          },
          @nav.push_url(
            cowork_url(
              selected_session_key=Some(session.session.session_key),
              panel=model.cowork_panel,
            ),
          ),
        ]),
        next_model,
      )
    }
    CoworkSessionCreated(Err(error)) =>
      (
        @rabbita.none,
        {
          ..model,
          cowork_action_loading: false,
          cowork_action_error: Some(error),
        },
      )
    SelectCoworkSession(session_key) => {
      let next_model = {
        ..model,
        selected_cowork_session_key: Some(session_key),
        cowork_detail_loading: true,
        cowork_detail_error: None,
        cowork_linked_snapshot: None,
        cowork_linked_snapshot_loading: false,
        cowork_linked_snapshot_error: None,
        cowork_workspace_loading: true,
        cowork_workspace_error: None,
      }
      (
        batch([
          @nav.push_url(
            cowork_url(
              selected_session_key=Some(session_key),
              panel=model.cowork_panel,
            ),
          ),
          fetch_cowork_session(dispatch, model.gateway_base, session_key),
          fetch_cowork_workspace(dispatch, model.gateway_base),
        ]),
        next_model,
      )
    }
    LoadCoworkSession(session_key) =>
      (
        batch([
          fetch_cowork_session(dispatch, model.gateway_base, session_key),
          fetch_cowork_workspace(dispatch, model.gateway_base),
        ]),
        {
          ..model,
          selected_cowork_session_key: Some(session_key),
          cowork_detail_loading: true,
          cowork_detail_error: None,
          cowork_linked_snapshot: None,
          cowork_linked_snapshot_loading: false,
          cowork_linked_snapshot_error: None,
          cowork_workspace_loading: true,
          cowork_workspace_error: None,
        },
      )
    CoworkSessionLoaded(session_key, Ok(session)) =>
      if model.selected_cowork_session_key == Some(session_key) ||
        model.route is Cowork {
        (
          match session.linked_run {
            Some(run) =>
              fetch_cowork_linked_snapshot(dispatch, model.gateway_base, run.id)
            None => @rabbita.none
          },
          sync_cowork_session_fields(
            {
              ..model,
              cowork_detail: Some(session),
              cowork_detail_loading: false,
              cowork_detail_error: None,
              cowork_linked_snapshot_loading: session.linked_run is Some(_),
              cowork_linked_snapshot_error: None,
            },
            session,
          ),
        )
      } else {
        (@rabbita.none, model)
      }
    CoworkSessionLoaded(_, Err(error)) =>
      (
        @rabbita.none,
        {
          ..model,
          cowork_detail_loading: false,
          cowork_detail_error: Some(error),
        },
      )
    CoworkLinkedSnapshotLoaded(run_id, Ok(snapshot)) =>
      match model.cowork_detail {
        Some(detail) =>
          match detail.linked_run {
            Some(run) if run.id == run_id =>
              (
                @rabbita.none,
                {
                  ..model,
                  cowork_linked_snapshot: Some(snapshot),
                  cowork_linked_snapshot_loading: false,
                  cowork_linked_snapshot_error: None,
                },
              )
            _ => (@rabbita.none, model)
          }
        None => (@rabbita.none, model)
      }
    CoworkLinkedSnapshotLoaded(_, Err(error)) =>
      (
        @rabbita.none,
        {
          ..model,
          cowork_linked_snapshot_loading: false,
          cowork_linked_snapshot_error: Some(error),
        },
      )
    CoworkWorkspaceLoaded(Ok(workspace)) =>
      (
        @rabbita.none,
        {
          ..model,
          cowork_workspace_snapshot: Some(workspace),
          cowork_workspace_loading: false,
          cowork_workspace_error: None,
        },
      )
    CoworkWorkspaceLoaded(Err(error)) =>
      (
        @rabbita.none,
        {
          ..model,
          cowork_workspace_loading: false,
          cowork_workspace_error: Some(error),
        },
      )
    SetCoworkComposer(value) =>
      (
        @rabbita.none,
        { ..model, cowork_composer: value, cowork_input_history_index: None },
      )
    SetCoworkTitleOverride(value) =>
      (@rabbita.none, { ..model, cowork_title_override: value })
    SetCoworkModelOverride(value) =>
      (@rabbita.none, { ..model, cowork_model_override: value })
    SetCoworkProviderOverride(value) =>
      (@rabbita.none, { ..model, cowork_provider_override: value })
    SetCoworkCwdOverride(value) =>
      (@rabbita.none, { ..model, cowork_cwd_override: value })
    SetCoworkSessionQuery(value) =>
      (@rabbita.none, { ..model, cowork_session_query: value })
    TogglePinnedCoworkSession(session_key) =>
      if contains_id(model.cowork_pinned_session_keys, session_key) {
        (
          @rabbita.none,
          {
            ..model,
            cowork_pinned_session_keys: model.cowork_pinned_session_keys.filter(fn(
                key,
              ) {
                key != session_key
              },
            ),
          },
        )
      } else {
        (
          @rabbita.none,
          {
            ..model,
            cowork_pinned_session_keys: [
              session_key,
              ..model.cowork_pinned_session_keys,
            ],
          },
        )
      }
    SaveCoworkConfig =>
      match model.selected_cowork_session_key {
        Some(session_key) =>
          (
            post_cowork_action(
              dispatch,
              "\{model.gateway_base}/v1/cowork/sessions/\{session_key}/config",
              body={
                "title": model.cowork_title_override,
                "cwd": model.cowork_cwd_override,
                "model": model.cowork_model_override,
                "provider": model.cowork_provider_override,
              },
            ),
            {
              ..model,
              cowork_action_loading: true,
              cowork_action_error: None,
              cowork_notice: Some("Saving conversation config..."),
            },
          )
        None => (@rabbita.none, model)
      }
    SendCoworkMessage =>
      match model.selected_cowork_session_key {
        Some(session_key) => {
          let content = cowork_composer_content(model, model.cowork_composer)
          let next_model = push_cowork_input_history(model, content)
          (
            post_cowork_action(
              dispatch,
              "\{model.gateway_base}/v1/cowork/sessions/\{session_key}/messages",
              body={
                "content": content,
                "cwd": next_model.cowork_cwd_override,
                "model": next_model.cowork_model_override,
              },
            ),
            {
              ..next_model,
              cowork_action_loading: true,
              cowork_action_error: None,
              cowork_notice: Some("Sending message..."),
            },
          )
        }
        None => (@rabbita.none, model)
      }
    StartCoworkPlan =>
      match model.selected_cowork_session_key {
        Some(session_key) => {
          let content = cowork_composer_content(model, model.cowork_composer)
          let next_model = push_cowork_input_history(model, content)
          (
            post_cowork_action(
              dispatch,
              "\{model.gateway_base}/v1/cowork/sessions/\{session_key}/plan",
              body={
                "request_text": content,
                "cwd": next_model.cowork_cwd_override,
              },
            ),
            {
              ..next_model,
              cowork_action_loading: true,
              cowork_action_error: None,
              cowork_notice: Some("Starting plan mode..."),
            },
          )
        }
        None => (@rabbita.none, model)
      }
    PreviewCoworkPlan =>
      match model.selected_cowork_session_key {
        Some(session_key) => {
          let content = cowork_composer_content(model, model.cowork_composer)
          let next_model = push_cowork_input_history(model, content)
          (
            post_cowork_action(
              dispatch,
              "\{model.gateway_base}/v1/cowork/sessions/\{session_key}/preview",
              body={
                "guidance": content,
                "cwd": next_model.cowork_cwd_override,
              },
            ),
            {
              ..next_model,
              cowork_action_loading: true,
              cowork_action_error: None,
              cowork_notice: Some("Refreshing plan preview..."),
            },
          )
        }
        None => (@rabbita.none, model)
      }
    PromoteCoworkPlan =>
      match model.selected_cowork_session_key {
        Some(session_key) => {
          let content = cowork_composer_content(model, model.cowork_composer)
          let next_model = push_cowork_input_history(model, content)
          (
            post_cowork_action(
              dispatch,
              "\{model.gateway_base}/v1/cowork/sessions/\{session_key}/promote",
              body={
                "guidance": content,
                "cwd": next_model.cowork_cwd_override,
              },
            ),
            {
              ..next_model,
              cowork_action_loading: true,
              cowork_action_error: None,
              cowork_notice: Some("Promoting plan into proposal..."),
            },
          )
        }
        None => (@rabbita.none, model)
      }
    ConfirmCoworkProposal(proposal_id) =>
      match model.selected_cowork_session_key {
        Some(session_key) =>
          (
            post_cowork_action(
              dispatch,
              "\{model.gateway_base}/v1/cowork/sessions/\{session_key}/proposals/\{proposal_id}/confirm",
            ),
            {
              ..model,
              cowork_action_loading: true,
              cowork_action_error: None,
              cowork_notice: Some("Confirming proposal..."),
            },
          )
        None => (@rabbita.none, model)
      }
    ResumeCoworkRun(run_id) =>
      match model.selected_cowork_session_key {
        Some(session_key) => {
          let content = cowork_composer_content(model, model.cowork_composer)
          let next_model = push_cowork_input_history(model, content)
          (
            post_cowork_action(
              dispatch,
              "\{model.gateway_base}/v1/cowork/sessions/\{session_key}/runs/\{run_id}/resume",
              body={ "content": content },
            ),
            {
              ..next_model,
              cowork_action_loading: true,
              cowork_action_error: None,
              cowork_notice: Some("Resuming linked run..."),
            },
          )
        }
        None => (@rabbita.none, model)
      }
    QueueCoworkDraft(action) => {
      let content = model.cowork_composer.trim().to_string()
      if content.is_blank() {
        (@rabbita.none, { ..model, cowork_notice: Some("Composer is empty.") })
      } else {
        let draft = QueuedCoworkDraft::{
          id: "queue:\{model.cowork_draft_queue.length() + 1}:\{content.length()}",
          action,
          content,
          quoted_message_id: model.cowork_reply_to_message_id,
          quoted_preview: model.cowork_reply_preview,
        }
        (
          @rabbita.none,
          {
            ..model,
            cowork_draft_queue: [..model.cowork_draft_queue, draft],
            cowork_notice: Some("Queued \{action}."),
          },
        )
      }
    }
    RunQueuedCoworkDraft(draft_id) =>
      match model.selected_cowork_session_key {
        Some(session_key) =>
          match queued_cowork_draft_by_id(model, draft_id) {
            Some(draft) => {
              let content = queued_cowork_draft_content(draft)
              let url = match draft.action {
                "plan" =>
                  "\{model.gateway_base}/v1/cowork/sessions/\{session_key}/plan"
                "preview" =>
                  "\{model.gateway_base}/v1/cowork/sessions/\{session_key}/preview"
                "promote" =>
                  "\{model.gateway_base}/v1/cowork/sessions/\{session_key}/promote"
                _ =>
                  "\{model.gateway_base}/v1/cowork/sessions/\{session_key}/messages"
              }
              let body : Json = match draft.action {
                "plan" =>
                  { "request_text": content, "cwd": model.cowork_cwd_override }
                "preview" =>
                  { "guidance": content, "cwd": model.cowork_cwd_override }
                "promote" =>
                  { "guidance": content, "cwd": model.cowork_cwd_override }
                _ =>
                  {
                    "content": content,
                    "cwd": model.cowork_cwd_override,
                    "model": model.cowork_model_override,
                  }
              }
              let next_model = push_cowork_input_history(
                {
                  ..model,
                  cowork_draft_queue: model.cowork_draft_queue.filter(fn(item) {
                    item.id != draft_id
                  }),
                },
                content,
              )
              (
                post_cowork_action(dispatch, url, body~),
                {
                  ..next_model,
                  cowork_action_loading: true,
                  cowork_action_error: None,
                  cowork_notice: Some("Running queued \{draft.action}..."),
                },
              )
            }
            None => (@rabbita.none, model)
          }
        None => (@rabbita.none, model)
      }
    RunAllQueuedCoworkDrafts =>
      match next_queued_cowork_draft(model) {
        Some(draft) => update(dispatch, RunQueuedCoworkDraft(draft.id), model)
        None =>
          (@rabbita.none, { ..model, cowork_notice: Some("Queue is empty.") })
      }
    RemoveQueuedCoworkDraft(draft_id) =>
      (
        @rabbita.none,
        {
          ..model,
          cowork_draft_queue: model.cowork_draft_queue.filter(fn(draft) {
            draft.id != draft_id
          }),
        },
      )
    MoveQueuedCoworkDraftUp(draft_id) =>
      (
        @rabbita.none,
        {
          ..model,
          cowork_draft_queue: move_draft_by_offset(
            model.cowork_draft_queue,
            draft_id,
            -1,
          ),
        },
      )
    MoveQueuedCoworkDraftDown(draft_id) =>
      (
        @rabbita.none,
        {
          ..model,
          cowork_draft_queue: move_draft_by_offset(
            model.cowork_draft_queue,
            draft_id,
            1,
          ),
        },
      )
    ToggleCoworkQueuePaused =>
      (
        @rabbita.none,
        {
          ..model,
          cowork_queue_paused: !model.cowork_queue_paused,
          cowork_notice: if model.cowork_queue_paused {
            Some("Draft queue resumed.")
          } else {
            Some("Draft queue paused.")
          },
        },
      )
    QuoteCoworkMessage(message_id, preview) =>
      (
        @rabbita.none,
        {
          ..model,
          cowork_reply_to_message_id: Some(message_id),
          cowork_reply_preview: Some(preview),
        },
      )
    ReuseCoworkMessage(content) =>
      (
        @rabbita.none,
        {
          ..model,
          cowork_composer: content,
          cowork_notice: Some("Loaded message into composer."),
        },
      )
    CopyCoworkMessage(content) =>
      (
        copy_cowork_text(dispatch, content),
        { ..model, cowork_notice: Some("Copying message...") },
      )
    CoworkCopyFinished(Ok(status)) =>
      (
        @rabbita.none,
        { ..model, cowork_notice: Some("Message copied: \{status}") },
      )
    CoworkCopyFinished(Err(error)) =>
      (@rabbita.none, { ..model, cowork_notice: Some("Copy failed: \{error}") })
    ClearCoworkReply =>
      (
        @rabbita.none,
        {
          ..model,
          cowork_reply_to_message_id: None,
          cowork_reply_preview: None,
        },
      )
    AttachCoworkContext(id, label, content) =>
      if contains_id(model.cowork_context_chips.map(fn(chip) { chip.id }), id) {
        (@rabbita.none, model)
      } else {
        (
          @rabbita.none,
          {
            ..model,
            cowork_context_chips: [
              ..model.cowork_context_chips,
              CoworkContextChip::{ id, label, content },
            ],
            cowork_notice: Some("Attached \{label} to composer context."),
          },
        )
      }
    RemoveCoworkContext(id) =>
      (
        @rabbita.none,
        {
          ..model,
          cowork_context_chips: model.cowork_context_chips.filter(fn(chip) {
            chip.id != id
          }),
        },
      )
    RecallPreviousCoworkInput =>
      if model.cowork_input_history.is_empty() {
        (@rabbita.none, model)
      } else {
        let index = match model.cowork_input_history_index {
          Some(current) =>
            if current + 1 >= model.cowork_input_history.length() {
              model.cowork_input_history.length() - 1
            } else {
              current + 1
            }
          None => 0
        }
        (
          @rabbita.none,
          {
            ..model,
            cowork_input_history_index: Some(index),
            cowork_composer: model.cowork_input_history[index],
          },
        )
      }
    RecallNextCoworkInput =>
      match model.cowork_input_history_index {
        Some(current) =>
          if current <= 0 {
            (
              @rabbita.none,
              { ..model, cowork_input_history_index: None, cowork_composer: "" },
            )
          } else {
            let index = current - 1
            (
              @rabbita.none,
              {
                ..model,
                cowork_input_history_index: Some(index),
                cowork_composer: model.cowork_input_history[index],
              },
            )
          }
        None => (@rabbita.none, model)
      }
    CoworkActionFinished(Ok(session)) => {
      let next_model = sync_cowork_session_fields(
        {
          ..model,
          cowork_action_loading: false,
          cowork_action_error: None,
          cowork_detail: Some(session),
          cowork_detail_loading: false,
          cowork_detail_error: None,
          cowork_linked_snapshot_loading: session.linked_run is Some(_),
          cowork_composer: "",
          cowork_reply_to_message_id: None,
          cowork_reply_preview: None,
          cowork_context_chips: [],
          cowork_notice: Some("Conversation updated."),
        },
        session,
      )
      (
        batch([
          fetch_cowork_sessions(dispatch, model.gateway_base),
          fetch_cowork_workspace(dispatch, model.gateway_base),
          match session.linked_run {
            Some(run) =>
              fetch_cowork_linked_snapshot(dispatch, model.gateway_base, run.id)
            None => @rabbita.none
          },
          if !next_model.cowork_draft_queue.is_empty() {
            dispatch(RunAllQueuedCoworkDrafts)
          } else {
            @rabbita.none
          },
        ]),
        next_model,
      )
    }
    CoworkActionFinished(Err(error)) =>
      (
        @rabbita.none,
        {
          ..model,
          cowork_action_loading: false,
          cowork_action_error: Some(error),
          cowork_notice: Some(error),
        },
      )
    SelectCoworkPanel(panel) => {
      let next_model = { ..model, cowork_panel: panel }
      (sync_url_cmd(next_model), next_model)
    }
    PollAcp =>
      (
        batch([
          fetch_acp_snapshot(dispatch, model.gateway_base),
          match model.acp_snapshot {
            Some(snapshot) =>
              if acp_snapshot_is_live(snapshot) {
                @rabbita.delay(dispatch(PollAcp), acp_poll_interval_ms())
              } else {
                @rabbita.none
              }
            None => @rabbita.none
          },
        ]),
        model,
      )
    PumpAcpStream => (drain_acp_stream_cmd(dispatch), model)
    PumpStream(run_id) =>
      if model.selected_run_id == Some(run_id) {
        (drain_stream_cmd(dispatch, run_id), model)
      } else {
        (@rabbita.none, model)
      }
    AcpSnapshotLoaded(Ok(snapshot)) => {
      let next_model = {
        ..model,
        acp_snapshot: Some(snapshot),
        acp_loading: false,
        acp_error: None,
        fresh_acp_node_ids: fresh_ids_from(
          snapshot.nodes,
          model.acp_snapshot
          .map(fn(item) { item.nodes.map(fn(node) { node.id }) })
          .unwrap_or([]),
          fn(node) { node.id },
        ),
        selected_acp_node_id: resolved_acp_node_id(
          { ..model, acp_snapshot: Some(snapshot) },
          snapshot,
        ),
      }
      (
        if acp_snapshot_is_live(snapshot) {
          @rabbita.delay(dispatch(PollAcp), acp_poll_interval_ms())
        } else {
          @rabbita.none
        },
        next_model,
      )
    }
    AcpSnapshotLoaded(Err(error)) =>
      (@rabbita.none, { ..model, acp_loading: false, acp_error: Some(error) })
    AcpEventsLoaded(Ok(timeline)) =>
      (
        @rabbita.none,
        {
          ..model,
          acp_timeline: timeline,
          fresh_acp_timeline_ids: fresh_ids_from(
            timeline,
            model.acp_timeline.map(fn(entry) { entry.id }),
            fn(entry) { entry.id },
          ),
        },
      )
    AcpEventsLoaded(Err(error)) =>
      (@rabbita.none, { ..model, acp_error: Some(error), acp_loading: false })
    AcpStreamDrained(Ok((entries, closed))) => {
      let merged : Array[AcpUiTimelineEntry] = model.acp_timeline.copy()
      let fresh : Array[String] = []
      let mut needs_snapshot = false
      for entry in entries {
        if !acp_timeline_contains_entry(merged, entry.id) {
          merged.push(entry)
          fresh.push(entry.id)
          if acp_stream_entry_requires_snapshot(entry) {
            needs_snapshot = true
          }
        }
      }
      let next_cmd = if closed {
        fetch_acp_snapshot(dispatch, model.gateway_base)
      } else if needs_snapshot {
        batch([
          fetch_acp_snapshot(dispatch, model.gateway_base),
          @rabbita.delay(dispatch(PumpAcpStream), 500),
        ])
      } else {
        @rabbita.delay(dispatch(PumpAcpStream), 500)
      }
      (
        next_cmd,
        {
          ..model,
          acp_timeline: merged,
          fresh_acp_timeline_ids: if fresh.is_empty() {
            model.fresh_acp_timeline_ids
          } else {
            fresh
          },
        },
      )
    }
    AcpStreamDrained(Err(error)) =>
      (
        @rabbita.delay(dispatch(PumpAcpStream), 1000),
        { ..model, acp_error: Some(error) },
      )
    SetAcpRunMessage(message) =>
      (@rabbita.none, { ..model, acp_run_message: message })
    AttachAcpTarget(target_id) =>
      (
        post_action(dispatch, "\{model.gateway_base}/v1/acp/sessions", body={
          "target_id": target_id,
          "session_key": "ui:acp:\{target_id}",
          "metadata": local_linkage_metadata(
            model.snapshot,
            focused_node_id=model.focused_node_id,
          ),
        }),
        {
          ..model,
          acp_action_notice: Some("Attaching ACP target \{target_id}..."),
        },
      )
    DetachAcpSession(session_id) =>
      (
        post_action(
          dispatch,
          "\{model.gateway_base}/v1/acp/sessions/\{session_id}/detach",
        ),
        {
          ..model,
          acp_action_notice: Some("Detaching ACP session \{session_id}..."),
        },
      )
    ResetAcpSession(session_id) =>
      (
        post_action(
          dispatch,
          "\{model.gateway_base}/v1/acp/sessions/\{session_id}/reset",
        ),
        {
          ..model,
          acp_action_notice: Some("Resetting ACP session \{session_id}..."),
        },
      )
    StartAcpRun(session_id) =>
      (
        post_action(
          dispatch,
          "\{model.gateway_base}/v1/acp/sessions/\{session_id}/run",
          body={
            "message": model.acp_run_message,
            "metadata": local_linkage_metadata(
              model.snapshot,
              focused_node_id=model.focused_node_id,
            ),
          },
        ),
        { ..model, acp_action_notice: Some("Starting remote ACP run...") },
      )
    CancelAcpRun(run_id) =>
      (
        post_action(
          dispatch,
          "\{model.gateway_base}/v1/acp/runs/\{run_id}/cancel",
        ),
        { ..model, acp_action_notice: Some("Cancelling ACP run \{run_id}...") },
      )
    AcpActionFinished(Ok(status)) =>
      (
        batch([dispatch(LoadAcp)]),
        {
          ..model,
          acp_action_notice: Some("ACP action completed: \{status}"),
          acp_run_message: if status == "accepted" {
            ""
          } else {
            model.acp_run_message
          },
        },
      )
    AcpActionFinished(Err(error)) =>
      (
        @rabbita.none,
        {
          ..model,
          acp_action_notice: Some("ACP action failed: \{error}"),
          acp_error: Some(error),
        },
      )
    SnapshotLoaded(run_id, Ok(snapshot)) =>
      if model.selected_run_id == Some(run_id) {
        let (collapsed_node_ids, expanded_node_ids) = manual_tree_state_for_snapshot(
          model, snapshot,
        )
        let fresh_node_ids = fresh_ids_from(
          snapshot.nodes,
          model.snapshot
          .map(fn(item) { item.nodes.map(fn(node) { node.id }) })
          .unwrap_or([]),
          fn(node) { node.id },
        )
        let focused_node_id = resolved_focus_node_id(model, snapshot)
        let next_model = {
          ..model,
          snapshot: Some(snapshot),
          fresh_node_ids,
          collapsed_node_ids,
          expanded_node_ids,
          focused_node_id,
          detail_loading: false,
          detail_error: None,
        }
        (
          if run_status_is_live(snapshot.run.status) {
            @rabbita.delay(dispatch(PollRun(run_id)), runs_poll_interval_ms())
          } else {
            @rabbita.none
          },
          { ..next_model },
        )
      } else {
        (@rabbita.none, model)
      }
    SnapshotLoaded(run_id, Err(error)) =>
      if model.selected_run_id == Some(run_id) {
        (
          @rabbita.none,
          {
            ..model,
            snapshot: None,
            timeline: [],
            fresh_node_ids: [],
            fresh_timeline_ids: [],
            collapsed_node_ids: [],
            expanded_node_ids: [],
            focused_node_id: None,
            detail_loading: false,
            detail_error: Some(error),
            artifact_modal_loading: false,
          },
        )
      } else {
        (@rabbita.none, model)
      }
    OpenArtifact(artifact_id) =>
      (
        fetch_artifact(dispatch, model.gateway_base, artifact_id),
        {
          ..model,
          artifact_modal_loading: true,
          artifact_modal_error: None,
          artifact_editor_draft: "",
        },
      )
    ArtifactLoaded(artifact_id, Ok(artifact)) =>
      if artifact.artifact.id == artifact_id {
        let content = artifact.content.unwrap_or(
          "Artifact content is not available as text.",
        )
        (
          @rabbita.none,
          {
            ..model,
            artifact_modal_loading: false,
            artifact_modal_error: None,
            artifact_modal: Some(artifact),
            artifact_editor_draft: content,
          },
        )
      } else {
        (@rabbita.none, { ..model, artifact_modal_loading: false })
      }
    ArtifactLoaded(_, Err(error)) =>
      (
        @rabbita.none,
        {
          ..model,
          artifact_modal_loading: false,
          artifact_modal_error: Some(error),
        },
      )
    SetArtifactEditorDraft(value) =>
      (@rabbita.none, { ..model, artifact_editor_draft: value })
    CloseArtifactModal =>
      (
        @rabbita.none,
        {
          ..model,
          artifact_modal_loading: false,
          artifact_modal_error: None,
          artifact_modal: None,
          artifact_editor_draft: "",
        },
      )
    EventsLoaded(run_id, Ok(timeline)) =>
      if model.selected_run_id == Some(run_id) {
        (
          @rabbita.none,
          {
            ..model,
            timeline,
            fresh_timeline_ids: fresh_ids_from(
              timeline,
              model.timeline.map(fn(entry) { entry.id }),
              fn(entry) { entry.id },
            ),
          },
        )
      } else {
        (@rabbita.none, model)
      }
    EventsLoaded(run_id, Err(error)) =>
      if model.selected_run_id == Some(run_id) && model.detail_error is None {
        (@rabbita.none, { ..model, detail_error: Some(error) })
      } else {
        (@rabbita.none, model)
      }
    StreamDrained(run_id, Ok((entries, closed))) =>
      if model.selected_run_id == Some(run_id) {
        let merged : Array[UiTimelineEntry] = model.timeline.copy()
        let fresh : Array[String] = []
        let mut needs_snapshot = false
        for entry in entries {
          if !timeline_contains_entry(merged, entry.id) {
            merged.push(entry)
            fresh.push(entry.id)
            if stream_entry_requires_snapshot(entry) {
              needs_snapshot = true
            }
          }
        }
        let next_cmd = if closed {
          batch([
            fetch_snapshot(dispatch, model.gateway_base, run_id),
            fetch_runs(dispatch, model.gateway_base),
          ])
        } else if needs_snapshot {
          batch([
            fetch_snapshot(dispatch, model.gateway_base, run_id),
            @rabbita.delay(dispatch(PumpStream(run_id)), 500),
          ])
        } else {
          @rabbita.delay(dispatch(PumpStream(run_id)), 500)
        }
        (
          next_cmd,
          {
            ..model,
            timeline: merged,
            fresh_timeline_ids: if fresh.is_empty() {
              model.fresh_timeline_ids
            } else {
              fresh
            },
          },
        )
      } else {
        (@rabbita.none, model)
      }
    StreamDrained(run_id, Err(error)) =>
      if model.selected_run_id == Some(run_id) {
        (
          @rabbita.delay(dispatch(PumpStream(run_id)), 1000),
          { ..model, detail_error: Some(error) },
        )
      } else {
        (@rabbita.none, model)
      }
    ExpandActiveBranches =>
      match model.snapshot {
        Some(snapshot) =>
          (
            @rabbita.none,
            {
              ..model,
              collapsed_node_ids: snapshot.nodes
              .filter(fn(node) { !keep_expanded_node(snapshot, model, node) })
              .map(fn(node) { node.id }),
              expanded_node_ids: snapshot.nodes
              .filter(fn(node) {
                node_has_collapsible_children(snapshot, node) &&
                keep_expanded_node(snapshot, model, node)
              })
              .map(fn(node) { node.id }),
            },
          )
        None => (@rabbita.none, model)
      }
    CollapseCompletedBranches =>
      match model.snapshot {
        Some(snapshot) =>
          (
            @rabbita.none,
            {
              ..model,
              collapsed_node_ids: auto_collapsed_ids(snapshot),
              expanded_node_ids: [],
            },
          )
        None => (@rabbita.none, model)
      }
    ResetTree =>
      (
        sync_url_cmd({
          ..model,
          collapsed_node_ids: [],
          expanded_node_ids: [],
          timeline_scope_node_id: None,
          timeline_scope_branch_only: false,
        }),
        {
          ..model,
          collapsed_node_ids: [],
          expanded_node_ids: [],
          timeline_scope_node_id: None,
          timeline_scope_branch_only: false,
        },
      )
    SelectRunsStatus(status) => {
      let next_model = { ..model, runs_status_filter: status, runs_page: 0 }
      (sync_url_cmd(next_model), next_model)
    }
    SetRunsQuery(query) => {
      let next_model = { ..model, runs_query: query, runs_page: 0 }
      (sync_url_cmd(next_model), next_model)
    }
    SelectRunsSort(sort) => {
      let next_model = { ..model, runs_sort: sort, runs_page: 0 }
      (sync_url_cmd(next_model), next_model)
    }
    SelectRunsPage(page) => {
      let next_model = { ..model, runs_page: page }
      (sync_url_cmd(next_model), next_model)
    }
    CanvasZoomIn =>
      (
        @rabbita.none,
        {
          ..model,
          canvas_zoom: if model.canvas_zoom + 10 > 220 {
            220
          } else {
            model.canvas_zoom + 10
          },
        },
      )
    CanvasZoomOut =>
      (
        @rabbita.none,
        {
          ..model,
          canvas_zoom: if model.canvas_zoom - 10 < 40 {
            40
          } else {
            model.canvas_zoom - 10
          },
        },
      )
    CanvasZoomReset => (@rabbita.none, { ..model, canvas_zoom: 100 })
    ToggleCanvasFullscreen =>
      (@rabbita.none, { ..model, canvas_fullscreen: !model.canvas_fullscreen })
    SelectMixedHandoff(key) => {
      let next_model = { ..model, selected_mixed_handoff_key: key }
      (sync_url_cmd(next_model), next_model)
    }
    ExportMixedLineage(key) =>
      match model.snapshot {
        Some(snapshot) =>
          match mixed_handoff_group_for_key(snapshot.handoffs, Some(key)) {
            Some(group) =>
              (
                download_mixed_text_file(
                  dispatch,
                  "mixed-lineage-\{snapshot.run.id}.txt",
                  mixed_lineage_transcript(snapshot, group),
                ),
                {
                  ..model,
                  acp_action_notice: Some(
                    "Exporting mixed lineage transcript \{key}...",
                  ),
                },
              )
            None =>
              (
                @rabbita.none,
                {
                  ..model,
                  acp_action_notice: Some(
                    "Mixed lineage not found for export: \{key}",
                  ),
                },
              )
          }
        None => (@rabbita.none, model)
      }
    ExportMixedCase(key) =>
      match (model.snapshot, model.acp_snapshot) {
        (Some(snapshot), Some(acp_snapshot)) =>
          match mixed_handoff_group_for_key(snapshot.handoffs, Some(key)) {
            Some(group) =>
              (
                download_mixed_text_file(
                  dispatch,
                  "case-\{snapshot.run.id}.txt",
                  mixed_case_transcript(snapshot, acp_snapshot, group),
                ),
                {
                  ..model,
                  acp_action_notice: Some(
                    "Exporting combined case transcript \{key}...",
                  ),
                },
              )
            None =>
              (
                @rabbita.none,
                {
                  ..model,
                  acp_action_notice: Some(
                    "Mixed lineage not found for case export: \{key}",
                  ),
                },
              )
          }
        _ => (@rabbita.none, model)
      }
    ToggleNode(node_id) =>
      match model.snapshot {
        Some(snapshot) => {
          let (collapsed_node_ids, expanded_node_ids) = toggle_manual_tree_state(
            model, snapshot, node_id,
          )
          (@rabbita.none, { ..model, collapsed_node_ids, expanded_node_ids })
        }
        None => (@rabbita.none, model)
      }
    FocusBranchPanel(node_id, panel) =>
      match model.snapshot {
        Some(snapshot) =>
          match node_for_id(snapshot, node_id) {
            Some(_) => {
              let next_model = {
                ..model,
                focused_node_id: Some(node_id),
                timeline_scope_node_id: Some(node_id),
                timeline_scope_branch_only: true,
                right_panel: panel,
              }
              (sync_url_cmd(next_model), next_model)
            }
            None => (@rabbita.none, model)
          }
        None => (@rabbita.none, model)
      }
    FocusBranchEvents(node_id) =>
      match model.snapshot {
        Some(snapshot) =>
          match node_for_id(snapshot, node_id) {
            Some(_) => {
              let next_model = {
                ..model,
                focused_node_id: Some(node_id),
                timeline_scope_node_id: Some(node_id),
                timeline_scope_branch_only: true,
              }
              (sync_url_cmd(next_model), next_model)
            }
            None => (@rabbita.none, model)
          }
        None => (@rabbita.none, model)
      }
    ClearTimelineScope => {
      let next_model = {
        ..model,
        timeline_scope_node_id: None,
        timeline_scope_branch_only: false,
      }
      (sync_url_cmd(next_model), next_model)
    }
    FocusNode(node_id) =>
      match model.snapshot {
        Some(snapshot) =>
          match node_for_id(snapshot, node_id) {
            Some(node) => {
              let maybe_artifact = artifact_for_node(snapshot, node)
              let should_open_report = match maybe_artifact {
                Some(artifact) =>
                  artifact_is_textual(artifact) &&
                  artifact_is_report_like(artifact)
                None => false
              }
              let next_model = {
                ..model,
                focused_node_id: Some(node_id),
                timeline_scope_node_id: None,
                timeline_scope_branch_only: false,
                right_panel: panel_for_node(model, node),
                artifact_modal_loading: should_open_report,
                artifact_modal_error: if should_open_report {
                  None
                } else {
                  model.artifact_modal_error
                },
              }
              let next_cmd = match maybe_artifact {
                Some(artifact) if should_open_report =>
                  batch([
                    sync_url_cmd(next_model),
                    fetch_artifact(dispatch, model.gateway_base, artifact.id),
                  ])
                _ => sync_url_cmd(next_model)
              }
              (next_cmd, next_model)
            }
            None => (@rabbita.none, { ..model, focused_node_id: Some(node_id) })
          }
        None => (@rabbita.none, { ..model, focused_node_id: Some(node_id) })
      }
    FocusTimeline(entry_id) =>
      match model.snapshot {
        Some(snapshot) => {
          for entry in model.timeline {
            if entry.id == entry_id {
              match node_id_for_entry(snapshot, entry) {
                Some(node_id) =>
                  match node_for_id(snapshot, node_id) {
                    Some(node) => {
                      let next_model = {
                        ..model,
                        focused_node_id: Some(node_id),
                        timeline_scope_node_id: None,
                        timeline_scope_branch_only: false,
                        right_panel: panel_for_node(model, node),
                      }
                      return (sync_url_cmd(next_model), next_model)
                    }
                    None =>
                      return (
                        @rabbita.none,
                        { ..model, focused_node_id: Some(node_id) },
                      )
                  }
                None => return (@rabbita.none, model)
              }
            }
          }
          (@rabbita.none, model)
        }
        None => (@rabbita.none, model)
      }
    ToggleAcpOutput(output_id) =>
      if contains_id(model.expanded_acp_output_ids, output_id) {
        (
          @rabbita.none,
          {
            ..model,
            expanded_acp_output_ids: model.expanded_acp_output_ids.filter(fn(
              id,
            ) {
              id != output_id
            }),
          },
        )
      } else {
        (
          @rabbita.none,
          {
            ..model,
            expanded_acp_output_ids: model.expanded_acp_output_ids + [output_id],
          },
        )
      }
    CopyAcpOutput(_label, text) =>
      (
        copy_to_clipboard(dispatch, text),
        { ..model, acp_action_notice: Some("Copying ACP output...") },
      )
    AcpCopyFinished(Ok(status)) =>
      (
        @rabbita.none,
        { ..model, acp_action_notice: Some("ACP output copied: \{status}") },
      )
    AcpCopyFinished(Err(error)) =>
      (
        @rabbita.none,
        {
          ..model,
          acp_action_notice: Some("ACP output copy failed: \{error}"),
          acp_error: Some(error),
        },
      )
    ExportAcpSession(session_id) =>
      match model.acp_snapshot {
        Some(snapshot) =>
          match acp_node_for_id(snapshot, "session:\{session_id}") {
            Some(node) =>
              (
                download_text_file(
                  dispatch,
                  "acp-session-\{session_id}.txt",
                  acp_session_transcript(snapshot, node),
                ),
                {
                  ..model,
                  acp_action_notice: Some(
                    "Exporting ACP session transcript \{session_id}...",
                  ),
                },
              )
            None =>
              (
                @rabbita.none,
                {
                  ..model,
                  acp_action_notice: Some(
                    "ACP session not found for export: \{session_id}",
                  ),
                },
              )
          }
        None => (@rabbita.none, model)
      }
    ExportAcpSessionTimeline(session_id) =>
      match model.acp_snapshot {
        Some(snapshot) =>
          match acp_node_for_id(snapshot, "session:\{session_id}") {
            Some(node) =>
              (
                download_text_file(
                  dispatch,
                  "acp-session-\{session_id}-timeline.txt",
                  acp_session_timeline_transcript(
                    node,
                    acp_timeline_for_node(node, model.acp_timeline),
                  ),
                ),
                {
                  ..model,
                  acp_action_notice: Some(
                    "Exporting ACP session timeline \{session_id}...",
                  ),
                },
              )
            None =>
              (
                @rabbita.none,
                {
                  ..model,
                  acp_action_notice: Some(
                    "ACP session not found for timeline export: \{session_id}",
                  ),
                },
              )
          }
        None => (@rabbita.none, model)
      }
    ExportAcpRun(run_id) =>
      match model.acp_snapshot {
        Some(snapshot) =>
          match acp_node_for_id(snapshot, "run:\{run_id}") {
            Some(node) =>
              (
                download_text_file(
                  dispatch,
                  "acp-\{run_id}.txt",
                  acp_run_transcript(node),
                ),
                {
                  ..model,
                  acp_action_notice: Some(
                    "Exporting ACP transcript \{run_id}...",
                  ),
                },
              )
            None =>
              (
                @rabbita.none,
                {
                  ..model,
                  acp_action_notice: Some(
                    "ACP run not found for export: \{run_id}",
                  ),
                },
              )
          }
        None => (@rabbita.none, model)
      }
    AcpExportFinished(Ok(status)) =>
      (
        @rabbita.none,
        {
          ..model,
          acp_action_notice: Some("ACP transcript exported: \{status}"),
        },
      )
    AcpExportFinished(Err(error)) =>
      (
        @rabbita.none,
        {
          ..model,
          acp_action_notice: Some("ACP transcript export failed: \{error}"),
          acp_error: Some(error),
        },
      )
    MixedExportFinished(Ok(status)) =>
      (
        @rabbita.none,
        {
          ..model,
          acp_action_notice: Some("Mixed lineage exported: \{status}"),
        },
      )
    MixedExportFinished(Err(error)) =>
      (
        @rabbita.none,
        {
          ..model,
          acp_action_notice: Some("Mixed lineage export failed: \{error}"),
          acp_error: Some(error),
        },
      )
    SelectPanel(panel) => {
      let next_model = { ..model, right_panel: panel }
      (sync_url_cmd(next_model), next_model)
    }
    SelectAcpNode(node_id) => {
      let next_model = { ..model, selected_acp_node_id: Some(node_id) }
      (sync_url_cmd(next_model), next_model)
    }
    UrlRequest(request) =>
      match request {
        Internal(url) => (@nav.push_url(url.to_string()), model)
        External(url) => (@nav.load(url), model)
      }
    UrlChanged(url) => {
      let route = route_from_url(url)
      let runs_status_filter = query_value(url, "status")
      let runs_query = query_value(url, "q").unwrap_or("")
      let runs_sort = run_sort_from_query(query_value(url, "sort"))
      let runs_page = match query_value(url, "page") {
        Some(page) => @strconv.parse_int(page) catch { _ => 0 }
        None => 0
      }
      let focused_node_id = query_value(url, "focus")
      let selected_acp_node_id = query_value(url, "focus")
      let selected_mixed_handoff_key = query_value(url, "mixed")
      let timeline_scope_node_id = query_value(url, "scope")
      let timeline_scope_branch_only = query_value(url, "branch") == Some("1")
      let right_panel = right_panel_from_query(query_value(url, "panel")).unwrap_or(
        model.right_panel,
      )
      let cowork_panel = cowork_panel_from_query(query_value(url, "panel"))
      let selected_cowork_session_key = query_value(url, "session")
      match route {
        Overview =>
          (
            batch([
              @nav.scroll_to_top(),
              stop_stream_cmd(),
              stop_acp_stream_cmd(),
              dispatch(LoadAcp),
            ]),
            {
              ..model,
              route,
              selected_mixed_handoff_key,
              selected_run_id: None,
              runs_status_filter,
              runs_query,
              runs_sort,
              runs_page,
              snapshot: None,
              timeline: [],
              fresh_node_ids: [],
              fresh_timeline_ids: [],
              focused_node_id: None,
              timeline_scope_node_id: None,
              timeline_scope_branch_only: false,
              collapsed_node_ids: [],
              expanded_node_ids: [],
              detail_loading: false,
              detail_error: None,
              selected_acp_node_id: None,
            },
          )
        Jobs =>
          (
            batch([
              @nav.scroll_to_top(),
              stop_stream_cmd(),
              stop_acp_stream_cmd(),
            ]),
            {
              ..model,
              route,
              selected_mixed_handoff_key: None,
              selected_run_id: None,
              runs_status_filter,
              runs_query,
              runs_sort,
              runs_page,
              snapshot: None,
              timeline: [],
              fresh_node_ids: [],
              fresh_timeline_ids: [],
              focused_node_id: None,
              timeline_scope_node_id: None,
              timeline_scope_branch_only: false,
              collapsed_node_ids: [],
              expanded_node_ids: [],
              detail_loading: false,
              detail_error: None,
            },
          )
        Run(run_id) =>
          if model.selected_run_id == Some(run_id) &&
            snapshot_matches_run(model.snapshot, run_id) {
            (
              @rabbita.none,
              {
                ..model,
                route,
                selected_mixed_handoff_key: None,
                runs_status_filter,
                runs_query,
                runs_sort,
                runs_page,
                focused_node_id,
                timeline_scope_node_id,
                timeline_scope_branch_only,
                right_panel,
              },
            )
          } else {
            (
              batch([
                @nav.scroll_to_top(),
                stop_acp_stream_cmd(),
                dispatch(LoadRun(run_id)),
              ]),
              {
                ..model,
                route,
                selected_mixed_handoff_key: None,
                selected_run_id: Some(run_id),
                snapshot: None,
                timeline: [],
                fresh_node_ids: [],
                fresh_timeline_ids: [],
                runs_status_filter,
                runs_query,
                runs_sort,
                runs_page,
                focused_node_id: None,
                timeline_scope_node_id: None,
                timeline_scope_branch_only: false,
                collapsed_node_ids: [],
                expanded_node_ids: [],
                right_panel,
              },
            )
          }
        RunCanvas(run_id) =>
          if model.selected_run_id == Some(run_id) &&
            snapshot_matches_run(model.snapshot, run_id) {
            (
              @rabbita.none,
              {
                ..model,
                route,
                selected_mixed_handoff_key: None,
                runs_status_filter,
                runs_query,
                runs_sort,
                runs_page,
                focused_node_id,
                timeline_scope_node_id,
                timeline_scope_branch_only,
                right_panel,
              },
            )
          } else {
            (
              batch([
                @nav.scroll_to_top(),
                stop_acp_stream_cmd(),
                dispatch(LoadRun(run_id)),
              ]),
              {
                ..model,
                route,
                selected_mixed_handoff_key: None,
                selected_run_id: Some(run_id),
                snapshot: None,
                timeline: [],
                fresh_node_ids: [],
                fresh_timeline_ids: [],
                runs_status_filter,
                runs_query,
                runs_sort,
                runs_page,
                focused_node_id: None,
                timeline_scope_node_id: None,
                timeline_scope_branch_only: false,
                collapsed_node_ids: [],
                expanded_node_ids: [],
                right_panel,
              },
            )
          }
        Acp =>
          (
            batch([
              @nav.scroll_to_top(),
              stop_stream_cmd(),
              stop_acp_stream_cmd(),
              dispatch(LoadAcp),
            ]),
            {
              ..model,
              route,
              selected_mixed_handoff_key: None,
              selected_acp_node_id,
            },
          )
        Cowork => {
          let next_model = {
            ..model,
            route,
            selected_mixed_handoff_key: None,
            selected_cowork_session_key,
            cowork_panel,
          }
          let next_cmd = batch([
            @nav.scroll_to_top(),
            stop_stream_cmd(),
            stop_acp_stream_cmd(),
            dispatch(LoadCoworkSessions),
            fetch_cowork_workspace(dispatch, model.gateway_base),
            match selected_cowork_session_key {
              Some(session_key) => dispatch(LoadCoworkSession(session_key))
              None => @rabbita.none
            },
          ])
          (
            next_cmd,
            {
              ..next_model,
              cowork_detail: None,
              cowork_detail_loading: selected_cowork_session_key is Some(_),
              cowork_detail_error: None,
              cowork_linked_snapshot: None,
              cowork_linked_snapshot_loading: false,
              cowork_linked_snapshot_error: None,
              cowork_workspace_snapshot: None,
              cowork_workspace_loading: true,
              cowork_workspace_error: None,
            },
          )
        }
      }
    }
  }
}
