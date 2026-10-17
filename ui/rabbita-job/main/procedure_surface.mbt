///|
fn render_cowork_procedures(model : Model) -> Html {
  guard model.cowork_detail is Some(detail) &&
    model.selected_cowork_session_key == Some(detail.session.session_key) &&
    !model.cowork_detail_loading else {
    return nothing
  }
  let context : Json = {
    "session_key": detail.session.session_key,
    "cwd": detail.session.cwd.unwrap_or(""),
    "cwd_override": model.cowork_cwd_override,
    "request_text": detail.linked_proposal
    .map(p => p.request_text)
    .unwrap_or(""),
    "run_id": detail.linked_run.map(r => r.id).unwrap_or(""),
  }
  @html.details(id="claw-procedure-panel", class="procedure-panel", [
    @html.summary("Use what worked"),
    p(
      "Browse accepted Book procedures in this work thread’s folder. Choose one only after checking its original conditions and evidence. Missing outcome or effort stays unknown.",
    ),
    @html.pre(
      id="claw-procedure-context",
      style=["display:none"],
      context.stringify(),
    ),
    button(id="claw-procedure-load", type_="button", "Load accepted procedures"),
    @html.label([
      span("Find a method"),
      input(
        id="claw-procedure-query",
        input_type=@html.Text,
        placeholder="Words from the task or procedure",
      ),
    ]),
    @html.label([
      span("Choose an approach"),
      @html.select(id="claw-procedure-choice", [
        @html.option(value="", "Load procedures first"),
      ]),
    ]),
    @html.pre(id="claw-procedure-evidence", "No procedure selected"),
    @html.details([
      @html.summary("Read the exact accepted procedure and its provenance"),
      @html.pre(id="claw-procedure-original", ""),
    ]),
    @html.label([
      span("Why it applies to this task, and which limits still apply"),
      textarea(id="claw-procedure-why", ""),
    ]),
    @html.label([
      span("Expected delivered result and how you will check it"),
      textarea(id="claw-procedure-expected", ""),
    ]),
    button(
      id="claw-procedure-apply",
      type_="button",
      "Use selected approach in draft",
    ),
    p(
      "Then use Plan, inspect Preview, Promote, and Confirm through the existing work controls. Choosing a method does not start a run or approve its result.",
    ),
    button(
      id="claw-procedure-compare",
      type_="button",
      "Compare with linked result",
    ),
    @html.pre(
      id="claw-procedure-comparison",
      "The comparison uses the approach retained in this thread’s linked proposal, never an unsent selection.",
    ),
    button(id="claw-procedure-cancel", type_="button", "Interrupt pending read"),
    p(
      id="claw-procedure-status",
      attrs=@html.Attrs::build().role("status").aria_live("polite"),
      "Choose a work folder containing the Book’s memory/procedures directory. Reload loses unsent form fields; sent plan context is retained with the proposal.",
    ),
  ])
}
