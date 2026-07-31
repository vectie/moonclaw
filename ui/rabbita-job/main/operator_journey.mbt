///|
struct OperatorNextStep {
  position : Int
  title : String
  detail : String
  action : String
  action_label : String
  blocked : Bool
} derive(Debug, Eq)

///|
fn operator_next_step_for(
  has_load_error : Bool,
  conversation_count : Int,
  live_runs : Int,
  failed_runs : Int,
  completed_runs : Int,
) -> OperatorNextStep {
  if has_load_error {
    {
      position: 1,
      title: "Reconnect to your work",
      detail: "MoonClaw could not refresh one or more views. Retry the safe read before starting anything new.",
      action: "retry",
      action_label: "Retry status",
      blocked: true,
    }
  } else if failed_runs > 0 {
    {
      position: 4,
      title: "Resolve a blocked run",
      detail: "Open the failed run to see the plain-language blocker, retained evidence, and safe recovery action.",
      action: "jobs",
      action_label: "Review blocked run",
      blocked: true,
    }
  } else if live_runs > 0 {
    {
      position: 4,
      title: "Check work already in progress",
      detail: "A run is active. Inspect its current step and outputs before starting overlapping work.",
      action: "jobs",
      action_label: "Open active run",
      blocked: false,
    }
  } else if conversation_count == 0 {
    {
      position: 1,
      title: "Tell MoonClaw what you want to accomplish",
      detail: "Start with an ordinary request. You can turn it into a reviewed plan before any durable execution.",
      action: "cowork",
      action_label: "Start working",
      blocked: false,
    }
  } else if completed_runs > 0 {
    {
      position: 5,
      title: "Review the latest outcome",
      detail: "Completed work is ready for inspection. Check the result and evidence before handing it onward.",
      action: "jobs",
      action_label: "Inspect result",
      blocked: false,
    }
  } else {
    {
      position: 2,
      title: "Continue a conversation into a plan",
      detail: "Open your work thread, refine the request, and preview the plan before promoting it.",
      action: "cowork",
      action_label: "Continue conversation",
      blocked: false,
    }
  }
}

///|
fn operator_next_step(model : Model) -> OperatorNextStep {
  let live_runs = model.runs
    .filter(run => run_status_is_live(run.status))
    .length()
  let failed_runs = model.runs
    .filter(run => normalize_status(run.status).contains("Failed"))
    .length()
  let completed_runs = model.runs
    .filter(run => normalize_status(run.status).contains("Completed"))
    .length()
  operator_next_step_for(
    model.runs_error is Some(_) ||
    model.cowork_sessions_error is Some(_) ||
    model.acp_error is Some(_),
    model.cowork_sessions.length(),
    live_runs,
    failed_runs,
    completed_runs,
  )
}

///|
fn render_operator_progress(step : OperatorNextStep) -> Html {
  let stages = [
    (1, "ask", "Ask"),
    (2, "plan", "Plan"),
    (3, "review", "Review"),
    (4, "runs", "Run"),
    (5, "inspect", "Inspect"),
  ]
  div(
    class="operator-progress",
    attrs=@html.Attrs::build().role("list").aria_label("Work progress"),
    stages.map(stage => {
      let state = if stage.0 < step.position {
        "complete"
      } else if stage.0 == step.position && step.blocked {
        "blocked"
      } else if stage.0 == step.position {
        "current"
      } else {
        "next"
      }
      div(
        class="operator-progress-step {state}",
        attrs=@html.Attrs::build()
          .role("listitem")
          .aria_current(
            if state == "current" || state == "blocked" {
              "step"
            } else {
              "false"
            },
          ),
        [operator_icon(stage.1, size=18), span(stage.2)],
      )
    }),
  )
}

///|
fn render_operator_next_step(dispatch : Dispatch[Msg], model : Model) -> Html {
  let step = operator_next_step(model)
  let action = if step.action == "retry" {
    button(
      class="operator-primary-action",
      title="Retry loading conversations, jobs, and remote status",
      on_click=@rabbita.batch([
        dispatch(LoadCoworkSessions),
        dispatch(LoadRuns),
        dispatch(LoadAcp),
      ]),
      [operator_icon("retry"), span(step.action_label)],
    )
  } else {
    let target = if step.action == "jobs" { "/jobs" } else { "/cowork" }
    button(
      class="operator-primary-action",
      title=step.action_label,
      on_click=@nav.push_url(target),
      [
        operator_icon(if step.action == "jobs" { "runs" } else { "work" }),
        span(step.action_label),
        operator_icon("arrow", size=17),
      ],
    )
  }
  article(
    class=if step.blocked {
      "operator-next-step blocked"
    } else {
      "operator-next-step"
    },
    attrs=@html.Attrs::build()
      .data_set("testid", "moonclaw-next-step")
      .aria_live("polite"),
    [
      div(class="operator-next-copy", [
        p(class="eyebrow", "Your next step"),
        h2(class="operator-next-title", step.title),
        p(class="muted", step.detail),
      ]),
      action,
      render_operator_progress(step),
    ],
  )
}
