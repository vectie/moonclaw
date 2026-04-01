///|
fn render_surface_tabs(model : Model) -> Html {
  let tab = fn(label : String, route : Surface, url : String) {
    let active = route_surface(model.route) == route
    button(
      class=if active { "surface-tab active-filter" } else { "surface-tab" },
      on_click=@nav.push_url(url),
      label,
    )
  }
  div(class="surface-tabs", [
    tab("Overview", SurfaceOverview, "/"),
    tab("Jobs", SurfaceJobs, "/jobs"),
    tab("ACP", SurfaceAcp, "/acp"),
  ])
}

///|
fn view(dispatch : Dispatch[Msg], model : Model) -> Html {
  div(class="shell", [
    header(class="topbar", [
      div([
        p(class="eyebrow", "MoonClaw Console"),
        h1(class="headline", "Jobs, Runs, and Remote Agents"),
        p(
          class="subline",
          "Track local runs, delegated work, and ACP-backed remote execution from one operator surface.",
        ),
        render_surface_tabs(model),
      ]),
      div(class="topbar-side", [
        div(class="live-stack", [
          render_live_chip(model),
          span(class="gateway-chip", last_update_label(model)),
        ]),
        div(class="gateway-chip", "Gateway: \{model.gateway_base}"),
      ]),
    ]),
    main_(
      class=if route_surface(model.route) == SurfaceOverview {
        "layout overview-layout"
      } else if model.route is RunCanvas(_) {
        "layout canvas-layout"
      } else {
        "layout"
      },
      match route_surface(model.route) {
        SurfaceOverview => [render_overview(dispatch, model)]
        SurfaceJobs =>
          match model.route {
            RunCanvas(_) =>
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
  ])
}
