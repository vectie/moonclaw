///|
pub fn e2e_planner_system_guidance() -> Array[String] {
  [
    "Supported analysis metadata keys include preferred_skills (string[]), enable_tools (boolean), web_search (boolean), model (string), and system_prompt (string).",
    "If required public data is likely missing but discoverable, prefer a step with metadata.web_search=true instead of guessing.",
  ]
}

///|
pub fn e2e_planner_prompt_sections(intake : Json?) -> Array[String] {
  let sections : Array[String] = []
  match intake {
    Some(intake) => {
      sections.push("Structured intake:\n\{intake.stringify()}")
      sections.push(
        "Treat starter attachments as the initial working set and preserve the user's requested output format in the plan.",
      )
      sections.push(
        "If some data is missing, prefer steps that can explore available files, tools, skills, and public web data before falling back to assumptions.",
      )
    }
    None => ()
  }
  sections
}
