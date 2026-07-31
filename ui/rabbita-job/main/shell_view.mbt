///|
fn render_surface_tabs(model : Model) -> Html {
  let tab = fn(label : String, icon : String, route : Surface, url : String) {
    let active = route_surface(model.route) == route
    button(
      class=if active { "surface-tab active-filter" } else { "surface-tab" },
      title=label,
      attrs=@html.Attrs::build().aria_current(
        if active {
          "page"
        } else {
          "false"
        },
      ),
      on_click=@nav.push_url(url),
      [operator_icon(icon), span(label)],
    )
  }
  @html.nav(
    class="surface-tabs",
    attrs=@html.Attrs::build().aria_label("MoonClaw workspace"),
    [
      tab("Home", "home", SurfaceOverview, "/"),
      tab("Work", "work", SurfaceCowork, "/cowork"),
      tab("Runs", "runs", SurfaceJobs, "/jobs"),
      tab("Remote", "remote", SurfaceAcp, "/acp"),
    ],
  )
}

///|
fn render_artifact_modal(dispatch : Dispatch[Msg], model : Model) -> Html {
  if !model.artifact_modal_loading &&
    model.artifact_modal is None &&
    model.artifact_modal_error is None {
    return nothing
  }
  let title = match model.artifact_modal {
    Some(loaded) =>
      loaded.artifact.logical_key.unwrap_or(loaded.artifact.artifact_type)
    None => "Artifact Viewer"
  }
  let subtitle = match model.artifact_modal {
    Some(loaded) => loaded.artifact.path
    None => ""
  }
  let content_type = match model.artifact_modal {
    Some(loaded) => loaded.artifact.content_type
    None => "text/plain"
  }
  div(class="artifact-modal-backdrop", [
    div(
      class="artifact-modal",
      attrs=@html.Attrs::build()
        .role("dialog")
        .aria_modal("true")
        .aria_labelledby("artifact-modal-title"),
      [
        div(class="artifact-modal-header", [
          div([
            p(class="eyebrow", "Artifact Editor"),
            h2(id="artifact-modal-title", class="detail-title", title),
            if subtitle == "" {
              nothing
            } else {
              p(class="mono artifact-modal-path", subtitle)
            },
          ]),
          div(class="tree-controls", [
            span(class="meta-chip", content_type),
            button(
              class="tree-control-button",
              title="Close artifact viewer",
              on_click=dispatch(CloseArtifactModal),
              "Close",
            ),
          ]),
        ]),
        div(class="artifact-modal-body", [
          if model.artifact_modal_loading {
            p(class="empty", "Loading artifact content...")
          } else if model.artifact_modal_error is Some(error) {
            p(class="empty", error)
          } else {
            div(class="artifact-editor-stack", [
              p(
                class="muted",
                "Local editing only for now. Changes here are not persisted back to the artifact yet.",
              ),
              textarea(
                class="artifact-editor-textarea mono",
                value=model.artifact_editor_draft,
                on_input=value => dispatch(SetArtifactEditorDraft(value)),
                nothing,
              ),
            ])
          },
        ]),
      ],
    ),
  ])
}

///|
fn view(dispatch : Dispatch[Msg], model : Model) -> Html {
  let current_surface = route_surface(model.route)
  let shell_class = if current_surface == SurfaceCowork {
    "shell cowork-shell"
  } else {
    "shell"
  }
  let topbar_class = if current_surface == SurfaceCowork {
    "topbar cowork-topbar"
  } else {
    "topbar"
  }
  let main_class = if current_surface == SurfaceOverview {
    "layout overview-layout"
  } else if current_surface == SurfaceCowork {
    "layout cowork-layout"
  } else if model.route is RunCanvas(_) {
    if model.canvas_fullscreen {
      "layout canvas-layout canvas-layout-fullscreen"
    } else {
      "layout canvas-layout"
    }
  } else {
    "layout"
  }
  div(class=shell_class, [
    @html.a(class="operator-skip-link", href="#moonclaw-main", "Skip to work"),
    header(class=topbar_class, [
      div([
        p(class="eyebrow", "MoonClaw · governed agent runtime"),
        h1(class="headline", "What do you want MoonClaw to accomplish?"),
        p(
          class="subline",
          "Describe the outcome, review the plan, then follow durable work and its evidence from one place.",
        ),
        render_surface_tabs(model),
      ]),
      div(class="topbar-side", [
        render_live_chip(model),
        @html.details(class="runtime-disclosure", [
          @html.summary(title="Show runtime connection details", [
            operator_icon("settings", size=18),
            span("Runtime details"),
          ]),
          div(class="runtime-disclosure-body", [
            span(class="gateway-chip", last_update_label(model)),
            span(class="gateway-chip", "Gateway · \{model.gateway_base}"),
          ]),
        ]),
      ]),
    ]),
    main_(
      id="moonclaw-main",
      class=main_class,
      match route_surface(model.route) {
        SurfaceOverview => [render_overview(dispatch, model)]
        SurfaceCowork => render_cowork_surface(dispatch, model)
        SurfaceJobs =>
          match model.route {
            RunCanvas(_) =>
              if model.canvas_fullscreen {
                [render_run_canvas(dispatch, model)]
              } else {
                [
                  render_runs_panel(dispatch, model),
                  render_run_canvas(dispatch, model),
                  match model.snapshot {
                    Some(snapshot) =>
                      render_right_panel(dispatch, model, snapshot)
                    None =>
                      section(class="panel", [
                        header(class="panel-header", [
                          h2(class="panel-title", "Outputs"),
                        ]),
                        div(class="panel-body", [
                          p(
                            class="empty",
                            "Artifacts, workspace, and memory appear here once a run is selected.",
                          ),
                        ]),
                      ])
                  },
                ]
              }
            _ =>
              [
                render_runs_panel(dispatch, model),
                render_detail(dispatch, model),
                match model.snapshot {
                  Some(snapshot) =>
                    render_right_panel(dispatch, model, snapshot)
                  None =>
                    section(class="panel", [
                      header(class="panel-header", [
                        h2(class="panel-title", "Outputs"),
                      ]),
                      div(class="panel-body", [
                        p(
                          class="empty",
                          "Artifacts, workspace, and memory appear here once a run is selected.",
                        ),
                      ]),
                    ])
                },
              ]
          }
        SurfaceAcp =>
          [
            render_acp_panel(dispatch, model),
            render_acp_detail(dispatch, model),
            render_acp_inspector(dispatch, model),
          ]
      },
    ),
    render_artifact_modal(dispatch, model),
  ])
}
