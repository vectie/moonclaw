///|
fn render_book_outcome_panel(snapshot : UiSnapshot) -> Html {
  let context : Json = {
    "run_id": snapshot.run.id,
    "status": normalize_status(snapshot.run.status),
    "artifacts": snapshot.artifacts.map(artifact => {
      "id": artifact.id,
      "type": artifact.content_type,
      "path": artifact.path,
    }),
  }
  @html.details(id="claw-book-panel", [
    @html.summary("Send completed output to Book"),
    p(
      "Select retained text, explain what it means, then export a file for Book’s existing review. Completion alone does not establish correctness, customer acceptance, cash or capability activation.",
    ),
    @html.pre(
      id="claw-book-context",
      style=["display:none"],
      context.stringify(),
    ),
    h3("1 · Select exact completed output"),
    p(
      "Book v1 retains UTF-8 text with an 8 MiB total package limit. Binary output remains available through Download; it is never converted or silently omitted here.",
    ),
    div(
      snapshot.artifacts.mapi((index, artifact) => {
        @html.label([
          input(
            id="claw-book-choose-" + index.to_string(),
            input_type=@html.Checkbox,
            attrs=@html.Attrs::build().disabled(
              !artifact_is_textual(artifact) ||
              artifact.id.has_prefix("synthetic:"),
            ),
          ),
          span(
            artifact.logical_key.unwrap_or(path_basename(artifact.path)) +
            " · " + artifact.content_type,
          ),
        ])
      }),
    ),
    button(id="claw-book-freeze", type_="button", "Freeze selected text"),
    @html.details([
      @html.summary("Inspect frozen run, versions and retained source"),
      @html.pre(id="claw-book-identity", "No source frozen yet"),
      @html.pre(id="claw-book-original", ""),
      @html.label([
        span("Original source index (0 for the first selected artifact)"),
        input(id="claw-book-source-index", input_type=@html.Text, value="0"),
      ]),
      button(
        id="claw-book-download-source",
        type_="button",
        "Download exact original text",
      ),
    ]),
    h3("2 · Describe the outcome and Three-Gap findings"),
    @html.label([
      span("Your interpretation and limits"),
      textarea(id="claw-book-summary", ""),
    ]),
    @html.label([
      span("Observed at (UTC, for example 2026-10-07T01:00:00Z)"),
      input(id="claw-book-observed", input_type=@html.Text),
    ]),
    div(
      ["information", "recognition", "decisiveness"].map(key => {
        div([
          @html.label([
            span(key + " gap severity: 0 explicitly absent; 1–5 present"),
            input(id="claw-book-" + key + "-severity", input_type=@html.Text),
          ]),
          @html.label([
            span(key + " explanation, including why absent when zero"),
            textarea(id="claw-book-" + key + "-summary", ""),
          ]),
        ])
      }),
    ),
    @html.details([
      @html.summary(
        "Proposed capability change (required by Book when a gap is present)",
      ),
      p(
        "All three fields are required together. A proposal does not approve or activate any capability.",
      ),
      @html.label([
        span("Capability ID"),
        input(id="claw-book-capability-id", input_type=@html.Text),
      ]),
      @html.label([
        span("Version"),
        input(id="claw-book-capability-version", input_type=@html.Text),
      ]),
      @html.label([
        span("Proposed change"),
        textarea(id="claw-book-capability-summary", ""),
      ]),
    ]),
    h3("3 · Export, reopen and inspect Book’s disposition"),
    button(id="claw-book-export", type_="button", "Export outcome for Book"),
    button(id="claw-book-cancel", type_="button", "Interrupt pending read"),
    p(id="claw-book-saved", "No exported handoff saved"),
    button(
      id="claw-book-download",
      type_="button",
      "Download saved handoff unchanged",
    ),
    @html.label([
      span("Open a saved Claw handoff (up to 16 MiB)"),
      input(
        id="claw-book-open",
        input_type=@html.File,
        accept="application/json,.json",
      ),
    ]),
    @html.label([
      span("Import Book’s receipt for the open handoff (up to 16 MiB)"),
      input(
        id="claw-book-receipt",
        input_type=@html.File,
        accept="application/json,.json",
      ),
    ]),
    @html.pre(id="claw-book-readback", "No Book disposition opened"),
    @html.details([
      @html.summary("Draft recovery and earlier sources"),
      @html.pre(
        id="claw-book-history",
        "Earlier sources are preserved when selecting a new version",
      ),
      @html.label([
        span("Earlier source index"),
        input(id="claw-book-history-index", input_type=@html.Text, value="0"),
      ]),
      button(
        id="claw-book-history-open",
        type_="button",
        "Reopen earlier source and handoff",
      ),
      button(id="claw-book-recovery", type_="button", "Download draft recovery"),
      @html.label([
        span("Open draft recovery (up to 64 MiB)"),
        input(
          id="claw-book-recovery-open",
          input_type=@html.File,
          accept="application/json,.json",
        ),
      ]),
    ]),
    p(
      id="claw-book-status",
      attrs=@html.Attrs::build().role("status").aria_live("polite"),
      "Manual file handoff. Book owns review; returned dispositions are historical observations.",
    ),
  ])
}
