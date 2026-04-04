///|
fn cowork_message_kind_label(message : CoworkMessage) -> String {
  match message.kind {
    "plan_preview" => "Plan Preview"
    "proposal" => "Draft Proposal"
    "run_event" => "Run Event"
    "resume" => "Resume Input"
    "command" => "Command"
    "error" => "Error"
    _ =>
      if message.role == "user" {
        "You"
      } else if message.role == "assistant" {
        "Assistant"
      } else {
        "System"
      }
  }
}

///|
fn cowork_compact_preview(text : String, max_len : Int) -> String {
  let trimmed = text.trim().to_string()
  if trimmed.length() <= max_len {
    trimmed
  } else {
    "\{trimmed[:max_len - 3].to_string()}..."
  }
}

///|
fn cowork_message_class(message : CoworkMessage) -> String {
  let mut classes = "cowork-message"
  if message.role == "user" {
    classes = classes + " user"
  } else if message.kind == "error" {
    classes = classes + " error"
  } else if message.kind == "plan_preview" ||
    message.kind == "proposal" ||
    message.kind == "run_event" {
    classes = classes + " card"
  }
  classes
}

///|
fn cowork_message_preview(message : CoworkMessage) -> String {
  cowork_compact_preview(message.content, 180)
}

///|
fn render_cowork_sidebar(dispatch : Dispatch[Msg], model : Model) -> Html {
  section(class="panel cowork-sidebar", [
    header(class="panel-header", [
      h2(class="panel-title", "Cowork"),
      button(
        class="tree-control-button",
        on_click=dispatch(CreateCoworkSession),
        "New Chat",
      ),
    ]),
    div(class="panel-body cowork-sidebar-body", [
      if model.cowork_sessions_loading {
        p(class="empty", "Loading conversations...")
      } else if model.cowork_sessions_error is Some(error) {
        p(class="empty", error)
      } else if model.cowork_sessions.is_empty() {
        p(
          class="empty",
          "No conversation sessions yet. Start one to chat, plan, preview, and promote into jobs.",
        )
      } else {
        div(
          class="cowork-session-list",
          model.cowork_sessions.map(fn(session) {
            let selected = model.selected_cowork_session_key ==
              Some(session.session_key)
            button(
              class=if selected {
                "cowork-session-item selected"
              } else {
                "cowork-session-item"
              },
              on_click=dispatch(SelectCoworkSession(session.session_key)),
              [
                div(class="cowork-session-row", [
                  p(class="node-title", session.title),
                  span(class="meta-chip", session.state),
                ]),
                p(
                  class="muted",
                  session.last_message_preview.unwrap_or("No messages yet"),
                ),
                div(class="cowork-session-row", [
                  span(class="mono tiny", session.session_key),
                  span(class="muted tiny", session.updated_at.to_string()),
                ]),
              ],
            )
          }),
        )
      },
    ]),
  ])
}

///|
fn render_cowork_message(
  dispatch : Dispatch[Msg],
  message : CoworkMessage,
) -> Html {
  let action = match message.metadata {
    { "proposal_id": String(proposal_id), .. } =>
      button(
        class="tree-control-button",
        on_click=dispatch(ConfirmCoworkProposal(proposal_id)),
        "Confirm",
      )
    { "run_id": String(run_id), .. } =>
      button(
        class="tree-control-button",
        on_click=@nav.push_url(run_url(run_id)),
        "Open Job",
      )
    _ => nothing
  }
  let secondary_actions = div(class="cowork-message-actions", [
    button(
      class="tree-control-button",
      on_click=dispatch(
        QuoteCoworkMessage(message.id, cowork_message_preview(message)),
      ),
      "Reply",
    ),
    button(
      class="tree-control-button",
      on_click=dispatch(ReuseCoworkMessage(message.content)),
      "Reuse",
    ),
    button(
      class="tree-control-button",
      on_click=dispatch(CopyCoworkMessage(message.content)),
      "Copy",
    ),
  ])
  article(class=cowork_message_class(message), [
    div(class="cowork-message-meta", [
      span(class="meta-chip", cowork_message_kind_label(message)),
      span(class="muted tiny", message.timestamp.to_string()),
    ]),
    p(class="cowork-message-content mono", message.content),
    div(class="cowork-action-row", [action, secondary_actions]),
  ])
}

///|
fn render_cowork_queue(dispatch : Dispatch[Msg], model : Model) -> Html {
  if model.cowork_draft_queue.is_empty() {
    p(class="muted tiny", "Queue is empty.")
  } else {
    div(
      class="cowork-queue-list",
      model.cowork_draft_queue.map(fn(draft) {
        article(class="artifact-card", [
          div(class="cowork-session-row", [
            p(class="node-title", "Queued \{draft.action}"),
            span(class="meta-chip", draft.action),
          ]),
          p(
            class="mono",
            cowork_compact_preview(queued_cowork_draft_content(draft), 220),
          ),
          div(class="cowork-action-row", [
            button(
              class="tree-control-button",
              on_click=dispatch(RunQueuedCoworkDraft(draft.id)),
              "Run",
            ),
            button(
              class="tree-control-button",
              on_click=dispatch(RemoveQueuedCoworkDraft(draft.id)),
              "Remove",
            ),
          ]),
        ])
      }),
    )
  }
}

///|
fn render_cowork_preview_panel(detail : CoworkSessionDetail) -> Html {
  let preview_text = match detail.plan_preview {
    Some(text) => text
    None =>
      match detail.linked_proposal {
        Some(proposal) =>
          [
            proposal.title,
            "",
            proposal.summary,
            "",
            "Request:",
            proposal.request_text,
          ].join("\n")
        None =>
          match detail.messages {
            [.., last] => last.content
            _ => "No preview content yet."
          }
      }
  }
  div(class="cowork-context-pane", [
    p(class="eyebrow", "Preview"),
    textarea(
      class="artifact-editor-textarea mono cowork-preview-textarea",
      value=preview_text,
      on_input=_ => @rabbita.none,
      nothing,
    ),
  ])
}

///|
fn render_cowork_artifacts_panel(
  dispatch : Dispatch[Msg],
  model : Model,
) -> Html {
  match model.cowork_linked_snapshot {
    Some(snapshot) =>
      if snapshot.artifacts.is_empty() {
        p(class="empty", "No artifacts yet for the linked run.")
      } else {
        div(
          class="artifact-grid",
          snapshot.artifacts.map(fn(artifact) {
            render_artifact_card(dispatch, artifact)
          }),
        )
      }
    None =>
      if model.cowork_linked_snapshot_loading {
        p(class="empty", "Loading linked run artifacts...")
      } else {
        p(class="empty", "Link a run to inspect artifacts here.")
      }
  }
}

///|
fn render_cowork_workspace_panel(model : Model) -> Html {
  match model.cowork_linked_snapshot {
    Some(snapshot) =>
      div(class="cowork-context-pane", [
        p(class="eyebrow", "Workspace"),
        p(
          class="mono",
          snapshot.workspace_dir.unwrap_or("No linked workspace directory."),
        ),
        if snapshot.memories.is_empty() {
          p(class="empty", "No linked memory items yet.")
        } else {
          div(
            class="cowork-memory-list",
            snapshot.memories.map(fn(memory) {
              article(class="artifact-card", [
                p(class="node-title", memory.title.unwrap_or(memory.kind)),
                p(class="muted", memory.kind),
                p(class="mono", cowork_compact_preview(memory.content, 240)),
              ])
            }),
          )
        },
      ])
    None =>
      if model.cowork_linked_snapshot_loading {
        p(class="empty", "Loading linked workspace context...")
      } else {
        p(
          class="empty",
          "Link a run to inspect workspace and memory context here.",
        )
      }
  }
}

///|
fn render_cowork_run_panel(
  dispatch : Dispatch[Msg],
  model : Model,
  detail : CoworkSessionDetail,
) -> Html {
  let proposal_card = match detail.linked_proposal {
    Some(proposal) =>
      article(class="artifact-card", [
        p(class="node-title", proposal.title),
        p(class="muted", proposal.status),
        p(class="mono", proposal.id),
        p(class="muted", proposal.summary),
        if detail.linked_run is None && proposal.status == "Draft" {
          button(
            class="tree-control-button",
            on_click=dispatch(ConfirmCoworkProposal(proposal.id)),
            "Confirm",
          )
        } else {
          nothing
        },
      ])
    None => p(class="empty", "No linked proposal yet.")
  }
  let run_card = match detail.linked_run {
    Some(run) =>
      article(class="artifact-card", [
        p(class="node-title", run.job_id),
        p(class="muted", normalize_status(run.status)),
        p(class="mono", run.id),
        p(class="muted", run.summary.unwrap_or("No run summary yet.")),
        div(class="cowork-action-row", [
          button(
            class="tree-control-button",
            on_click=@nav.push_url(run_url(run.id)),
            "Open Job",
          ),
          if normalize_status(run.status).contains("WaitingForInput") {
            button(
              class="tree-control-button",
              on_click=dispatch(ResumeCoworkRun(run.id)),
              "Resume",
            )
          } else {
            nothing
          },
        ]),
      ])
    None => p(class="empty", "No linked run yet.")
  }
  div(class="cowork-context-pane", [
    p(class="eyebrow", "Run Context"),
    proposal_card,
    run_card,
    if model.cowork_linked_snapshot_error is Some(error) {
      p(class="empty", error)
    } else {
      nothing
    },
  ])
}

///|
fn render_cowork_context(
  dispatch : Dispatch[Msg],
  model : Model,
  detail : CoworkSessionDetail,
) -> Html {
  section(class="panel cowork-context", [
    header(class="panel-header", [
      h2(class="panel-title", "Context"),
      div(class="surface-tabs", [
        button(
          class=if model.cowork_panel == CoworkPreview {
            "surface-tab active-filter"
          } else {
            "surface-tab"
          },
          on_click=dispatch(SelectCoworkPanel(CoworkPreview)),
          "Preview",
        ),
        button(
          class=if model.cowork_panel == CoworkWorkspace {
            "surface-tab active-filter"
          } else {
            "surface-tab"
          },
          on_click=dispatch(SelectCoworkPanel(CoworkWorkspace)),
          "Workspace",
        ),
        button(
          class=if model.cowork_panel == CoworkArtifacts {
            "surface-tab active-filter"
          } else {
            "surface-tab"
          },
          on_click=dispatch(SelectCoworkPanel(CoworkArtifacts)),
          "Artifacts",
        ),
        button(
          class=if model.cowork_panel == CoworkRun {
            "surface-tab active-filter"
          } else {
            "surface-tab"
          },
          on_click=dispatch(SelectCoworkPanel(CoworkRun)),
          "Run",
        ),
      ]),
    ]),
    div(class="panel-body", [
      match model.cowork_panel {
        CoworkPreview => render_cowork_preview_panel(detail)
        CoworkWorkspace => render_cowork_workspace_panel(model)
        CoworkArtifacts => render_cowork_artifacts_panel(dispatch, model)
        CoworkRun => render_cowork_run_panel(dispatch, model, detail)
      },
    ]),
  ])
}

///|
fn render_cowork_center(dispatch : Dispatch[Msg], model : Model) -> Html {
  let transcript_body = match model.cowork_detail {
    Some(detail) =>
      div(class="cowork-transcript", [
        if detail.session.has_plan_mode {
          article(class="cowork-banner", [
            p(class="node-title", "Plan Mode Active"),
            p(
              class="muted",
              "Plain follow-up messages refine the current plan. Use Preview to inspect it and Promote to create a normal draft proposal.",
            ),
          ])
        } else {
          nothing
        },
        if detail.messages.is_empty() {
          p(
            class="empty",
            "Send a message, start plan mode, or promote a draft proposal into a durable job.",
          )
        } else {
          div(
            class="cowork-transcript-list",
            detail.messages.map(fn(message) {
              render_cowork_message(dispatch, message)
            }),
          )
        },
      ])
    None =>
      if model.cowork_detail_loading {
        p(class="empty", "Loading conversation...")
      } else if model.cowork_detail_error is Some(error) {
        p(class="empty", error)
      } else {
        p(
          class="empty",
          "Select a conversation on the left or create a new one to start.",
        )
      }
  }
  section(class="panel cowork-main", [
    header(class="panel-header", [
      h2(
        class="panel-title",
        model.cowork_detail
        .map(fn(detail) { detail.session.title })
        .unwrap_or("Conversation"),
      ),
      div(class="tree-controls", [
        button(
          class="tree-control-button",
          on_click=dispatch(SaveCoworkConfig),
          "Save Config",
        ),
        button(
          class="tree-control-button",
          on_click=dispatch(StartCoworkPlan),
          "Plan",
        ),
        button(
          class="tree-control-button",
          on_click=dispatch(PreviewCoworkPlan),
          "Preview",
        ),
        button(
          class="tree-control-button",
          on_click=dispatch(PromoteCoworkPlan),
          "Promote",
        ),
      ]),
    ]),
    div(class="panel-body cowork-main-body", [
      div(class="cowork-config-bar", [
        input(
          class="runs-search-input cowork-config-input",
          value=model.cowork_model_override,
          on_input=value => dispatch(SetCoworkModelOverride(value)),
          placeholder="Model override",
          nothing,
        ),
        input(
          class="runs-search-input cowork-config-input",
          value=model.cowork_provider_override,
          on_input=value => dispatch(SetCoworkProviderOverride(value)),
          placeholder="Provider override",
          nothing,
        ),
        input(
          class="runs-search-input cowork-config-input cowork-config-cwd",
          value=model.cowork_cwd_override,
          on_input=value => dispatch(SetCoworkCwdOverride(value)),
          placeholder="Working directory",
          nothing,
        ),
      ]),
      transcript_body,
      if model.cowork_reply_preview is Some(preview) {
        article(class="cowork-banner", [
          p(class="node-title", "Reply Target"),
          p(class="mono", preview),
          button(
            class="tree-control-button",
            on_click=dispatch(ClearCoworkReply),
            "Clear Reply",
          ),
        ])
      } else {
        nothing
      },
      section(class="operator-hint cowork-queue-panel", [
        p(class="mono", "Draft Queue"),
        render_cowork_queue(dispatch, model),
        div(class="cowork-action-row", [
          button(
            class="tree-control-button",
            on_click=dispatch(QueueCoworkDraft("send")),
            "Queue Send",
          ),
          button(
            class="tree-control-button",
            on_click=dispatch(QueueCoworkDraft("plan")),
            "Queue Plan",
          ),
          button(
            class="tree-control-button",
            on_click=dispatch(QueueCoworkDraft("preview")),
            "Queue Preview",
          ),
          button(
            class="tree-control-button",
            on_click=dispatch(QueueCoworkDraft("promote")),
            "Queue Promote",
          ),
          button(
            class="tree-control-button",
            on_click=dispatch(RunAllQueuedCoworkDrafts),
            "Run Next",
          ),
        ]),
      ]),
      div(class="cowork-composer", [
        textarea(
          class="artifact-editor-textarea cowork-composer-textarea",
          value=model.cowork_composer,
          on_input=value => dispatch(SetCoworkComposer(value)),
          nothing,
        ),
        div(class="cowork-action-row", [
          button(
            class="tree-control-button",
            on_click=dispatch(RecallPreviousCoworkInput),
            "Older",
          ),
          button(
            class="tree-control-button",
            on_click=dispatch(RecallNextCoworkInput),
            "Newer",
          ),
          button(
            class="tree-control-button",
            on_click=dispatch(SendCoworkMessage),
            "Send",
          ),
          if model.cowork_action_loading {
            span(class="status-badge pending", "Working")
          } else {
            nothing
          },
          match model.cowork_action_error {
            Some(error) => p(class="empty", error)
            None => nothing
          },
          match model.cowork_notice {
            Some(notice) => p(class="muted", notice)
            None => nothing
          },
        ]),
      ]),
    ]),
  ])
}

///|
fn render_cowork_surface(
  dispatch : Dispatch[Msg],
  model : Model,
) -> Array[Html] {
  [
    render_cowork_sidebar(dispatch, model),
    render_cowork_center(dispatch, model),
    match model.cowork_detail {
      Some(detail) => render_cowork_context(dispatch, model, detail)
      None =>
        section(class="panel cowork-context", [
          header(class="panel-header", [h2(class="panel-title", "Context")]),
          div(class="panel-body", [
            p(
              class="empty",
              "Linked proposals, runs, artifacts, and previews show up here once a conversation has state.",
            ),
          ]),
        ])
    },
  ]
}
