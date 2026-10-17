///|
fn render_cowork_blocked_recovery(model : Model) -> Html {
  guard model.cowork_detail is Some(detail) &&
    model.selected_cowork_session_key == Some(detail.session.session_key) &&
    !model.cowork_detail_loading &&
    detail.linked_run is Some(run) else {
    return nothing
  }
  let context : Json = {
    "session_key": detail.session.session_key,
    "cwd": detail.session.cwd.unwrap_or(""),
    "cwd_override": model.cowork_cwd_override,
    "run_id": run.id,
  }
  @html.details(id="claw-recovery-panel", class="procedure-panel", [
    @html.summary("Continue blocked work"),
    p(
      "See what is already retained and answer the blocked step without creating a replacement run. This control handles missing input only; uncertain external effects still need reconciliation.",
    ),
    @html.pre(
      id="claw-recovery-context",
      style=["display:none"],
      context.stringify(),
    ),
    button(
      id="claw-recovery-refresh",
      type_="button",
      "Refresh retained checkpoint",
    ),
    @html.pre(id="claw-recovery-evidence", "No checkpoint read yet"),
    @html.label([
      span("Missing input or explicitly permitted assumptions"),
      textarea(id="claw-recovery-answer", ""),
    ]),
    p(
      "Keep the original objective, permitted sources and authority. This answer does not grant new tools, spending, publication or acceptance authority.",
    ),
    button(
      id="claw-recovery-adopt",
      type_="button",
      "Use retained answer for reviewed checkpoint",
    ),
    button(
      id="claw-recovery-resume",
      type_="button",
      "Continue this blocked step",
    ),
    button(
      id="claw-recovery-cancel",
      type_="button",
      "Stop waiting for response",
    ),
    p(
      id="claw-recovery-status",
      attrs=@html.Attrs::build().role("status").aria_live("polite"),
      "Refresh to inspect the same run. Loading never starts execution.",
    ),
  ])
}
