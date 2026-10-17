///|
fn report_escape(text : String) -> String {
  text
  .replace_all(old="&", new="&amp;")
  .replace_all(old="<", new="&lt;")
  .replace_all(old=">", new="&gt;")
  .replace_all(old="\"", new="&quot;")
  .replace_all(old="'", new="&#39;")
}

///|
// Keep all output buffered and bounded before a caller writes any HTML.
fn report_append(
  parts : Array[String],
  units : Ref[Int32],
  text : String,
) -> Unit raise {
  guard text.length() <= 8388608 - units.val else {
    fail("HTML report exceeds 8 Mi code units")
  }
  units.val += text.length()
  parts.push(text)
}

///|
fn report_group_row(
  label : String,
  indices : Array[Int32],
  entries : Array[JournalEntry],
) -> String raise {
  let first_index = indices[0]
  let first = event_fields(entries[first_index])
  let last = event_fields(entries[indices[indices.length() - 1]])
  let mut status = "not recorded"
  let mut status_link = ""
  for index in indices {
    // Recorded null differs from absent status. Step status is never run status.
    if entries[index].record is Object(fields) &&
      fields.get("status") is Some(value) {
      status = value.stringify()
      status_link = "<a href=\"#event-\{index + 1}\">observation \{index + 1}</a>"
    }
  }
  let span = last.timestamp.to_int64() - first.timestamp.to_int64()
  "<tr><th scope=\"row\"><a href=\"#event-\{first_index + 1}\">" +
  report_escape(label) +
  "</a></th><td>\{indices.length()}</td>" +
  "<td>\{first.timestamp} to \{last.timestamp}<br>span \{span}</td><td><code>" +
  report_escape(status) +
  "</code></td><td>" +
  status_link +
  "</td></tr>\n"
}

///|
/// Create a standalone, script-free HTML inspection report for an exact saved
/// job/run pair. All supplied records are validated. Equal-timestamp ordering,
/// duplicate observations, original sources/lines and unknown fields survive.
/// This is an offline presentation, not a live state or acceptance projection.
pub fn journal_run_html(
  entries : Array[JournalEntry],
  job_id~ : String,
  run_id~ : String,
) -> String raise {
  let ordered = select_journal_entries(entries)
  let selected : Array[JournalEntry] = []
  for entry in ordered {
    let event = event_fields(entry)
    if event.job_id == job_id && event.run_id == run_id {
      selected.push(entry)
    }
  }
  guard !selected.is_empty() else {
    fail("No observations for the exact job/run pair")
  }
  let run_level : Array[Int32] = []
  let steps : Map[String, Array[Int32]] = Map([])
  for index, entry in selected {
    match event_fields(entry).step_id {
      None => run_level.push(index)
      Some(step) => {
        let indices = steps
          .get(step)
          .unwrap_or_else(() => {
            let indices : Array[Int32] = []
            steps[step] = indices
            indices
          })
        indices.push(index)
      }
    }
  }
  let parts : Array[String] = []
  let units = Ref(0)
  report_append(
    parts,
    units,
    (
      #|<!doctype html>
      #|<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
      #|<title>Saved run report</title>
      #|<style>
      #|:root{color-scheme:light}body{margin:0;background:#f3f5f7;color:#182333;font:16px/1.5 system-ui,sans-serif}main{max-width:1050px;margin:auto;padding:24px}h1,h2{line-height:1.2}header,section{background:white;border:1px solid #d5dce5;border-radius:10px;padding:20px;margin-bottom:20px}a{color:#174f93}code,pre{white-space:pre-wrap;overflow-wrap:anywhere;font-family:ui-monospace,monospace}pre{padding:12px;background:#f3f5f7;border-radius:6px}table{border-collapse:collapse;width:100%;font-size:14px}th,td{text-align:left;vertical-align:top;padding:10px;border-bottom:1px solid #d5dce5;overflow-wrap:anywhere}th{font-weight:600}details{border-top:1px solid #d5dce5;padding:12px 0;scroll-margin-top:16px}summary{cursor:pointer;overflow-wrap:anywhere}details:target{background:#fff4cd}small{color:#4b586a}.scroll{overflow-x:auto}.notice{border-left:4px solid #bc861c;padding-left:12px}dt{font-weight:600}dd{margin-left:0;margin-bottom:10px}@media(max-width:650px){main{padding:10px}header,section{padding:14px}table{min-width:640px}}@media print{body{background:white}header,section{border:0;padding:0}a{color:inherit}}
      #|</style></head><body><main id="top"><header><h1>Saved run report</h1>
      #|
    ),
  )
  report_append(
    parts,
    units,
    "<dl><dt>Job</dt><dd><code>" +
    report_escape(job_id.to_json().stringify()) +
    "</code></dd><dt>Run</dt><dd><code>" +
    report_escape(run_id.to_json().stringify()) +
    "</code></dd></dl>\n",
  )
  report_append(
    parts,
    units,
    "<p class=\"notice\">Historical observations from the supplied files only. Recorded statuses are not current runtime state, execution proof, safe retry permission, or owner acceptance. This report does not refresh.</p>" +
    "<p>Selected observations: \{selected.length()}; excluded: \{entries.length() - selected.length()}; distinct steps: \{steps.length()}.</p>" +
    "<p>Timestamps and spans use the journal's recorded integer units. Observed spans are not execution durations. Duplicate observations remain visible.</p>" +
    "<nav aria-label=\"Report sections\"><a href=\"#steps\">Step index</a> · <a href=\"#observations\">Chronological observations</a></nav></header>\n" +
    "<section id=\"steps\"><h2>Step index</h2><p>Each row links to its first observation. Status links point to the latest observation that actually contains a status field, including explicit null.</p>" +
    "<div class=\"scroll\"><table><thead><tr><th>Scope / step ID</th><th>Events</th><th>Observed interval</th><th>Latest recorded status</th><th>Status source</th></tr></thead><tbody>\n",
  )
  if !run_level.is_empty() {
    report_append(
      parts,
      units,
      report_group_row("Run-level", run_level, selected),
    )
  }
  for step, indices in steps {
    report_append(
      parts,
      units,
      report_group_row("Step " + step.to_json().stringify(), indices, selected),
    )
  }
  report_append(
    parts,
    units,
    "</tbody></table></div><p><a href=\"#top\">Back to top</a></p></section>\n" +
    "<section id=\"observations\"><h2>Chronological observations</h2><p>Open an observation to inspect its message and complete parsed JSON record. Source positions refer to the original input files.</p>\n",
  )
  for index, entry in selected {
    let event = event_fields(entry)
    let scope = event.step_id
      .map(step => "Step " + step.to_json().stringify())
      .unwrap_or("Run-level")
    report_append(
      parts,
      units,
      "<details id=\"event-\{index + 1}\"><summary><strong>\{index + 1}. \{event.timestamp}</strong> · " +
      report_escape(event.event_type) +
      " · " +
      report_escape(scope) +
      "</summary><p><small>Source: <code>" +
      report_escape(entry.source) +
      "</code>; physical line \{entry.line}</small></p><h3>Message</h3><pre>" +
      report_escape(event.message) +
      "</pre><h3>Complete recorded JSON</h3><pre>" +
      report_escape(entry.record.stringify()) +
      "</pre><p><a href=\"#steps\">Back to step index</a></p></details>\n",
    )
  }
  report_append(
    parts, units, "</section><footer><p>moonclaw.saved-run-html.v1 · Offline inspection. Content is unredacted; inspect before sharing.</p></footer></main></body></html>\n",
  )
  parts.join("")
}
