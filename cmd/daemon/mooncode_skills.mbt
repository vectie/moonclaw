///|
async fn mooncode_skill_loader(book_root : String) -> @skills.Loader {
  let loader = @skills.Loader::new(
    cwd=book_root,
    logger=@pino.logger("mooncode-skills", @pino.Transport::console()),
  )
  loader.load()
  loader
}

///|
async fn mooncode_runtime_turn_skill_catalog(book_root : String) -> String {
  let loader = mooncode_skill_loader(book_root) catch {
    error => return "\n\nSkill discovery is unavailable for this turn: \{error}"
  }
  let names = loader.skills().keys().collect()
  names.sort()
  if names.is_empty() {
    return "\n\nNo installed skills were discovered for this MoonBook."
  }
  let out = StringBuilder()
  out.write_string(
    (
      #|
      #|
      #|Installed skills are available through progressive disclosure. If the
      #|user names a skill, or the task clearly matches a skill description, you
      #|must call `read_skill` for that skill before task work. Read the complete
      #|SKILL.md first. Load referenced files only when the selected instructions
      #|make them relevant. A `read_skill` call ends the current tool batch so
      #|the returned instructions can govern the next planner prompt.
      #|
      #|<available_skills>
      #|
    ),
  )
  for name in names {
    match loader.skills().get(name) {
      Some(skill) => {
        out.write_string("  <skill>\n")
        out.write_string("    <name>\{skill.name}</name>\n")
        out.write_string(
          "    <description>\{skill.description}</description>\n",
        )
        out.write_string("  </skill>\n")
      }
      None => ()
    }
  }
  out.write_string("</available_skills>")
  out.to_string()
}

///|
fn mooncode_skill_relative_path_safe(path : String) -> Bool {
  if path == "" || @pathx.is_absolute(path) {
    return false
  }
  for part in path.split("/") {
    if part == ".." {
      return false
    }
  }
  true
}

///|
fn mooncode_skill_path_within(root : String, candidate : String) -> Bool {
  candidate == root || candidate.has_prefix(root + "/")
}

///|
async fn mooncode_tool_read_skill(book_root : String, arguments : Json) -> Json {
  let name = mooncode_json_string(arguments, "name", default="")
    .trim()
    .to_owned()
  if name == "" {
    return mooncode_tool_error_result(
      "read_skill",
      message="skill name must be non-empty",
    )
  }
  let loader = mooncode_skill_loader(book_root) catch {
    error =>
      return mooncode_tool_error_result(
        "read_skill",
        message="failed to discover installed skills: \{error}",
      )
  }
  let skill = match loader.skills().get(name) {
    Some(skill) => skill
    None =>
      return mooncode_tool_error_result(
        "read_skill",
        message="installed skill not found: \{name}",
      )
  }
  let requested = mooncode_json_string(arguments, "path", default="")
    .trim()
    .to_owned()
  if requested != "" && !mooncode_skill_relative_path_safe(requested) {
    return mooncode_tool_error_result(
      "read_skill",
      message="skill resource path must stay inside the selected skill",
      metadata={ "name": skill.name, "path": requested },
    )
  }
  let skill_root = @fsx.resolve(@pathx.dirname(skill.location)) catch {
    error =>
      return mooncode_tool_error_result(
        "read_skill",
        message="failed to resolve skill root: \{error}",
      )
  }
  let source_path = if requested == "" || requested == "SKILL.md" {
    skill.location
  } else {
    @pathx.join(skill_root, requested)
  }
  let resolved_path = @fsx.resolve(source_path) catch {
    error =>
      return mooncode_tool_error_result(
        "read_skill",
        message="failed to resolve skill resource: \{error}",
      )
  }
  if !mooncode_skill_path_within(skill_root, resolved_path) {
    return mooncode_tool_error_result(
      "read_skill",
      message="skill resource path escapes the selected skill",
      metadata={ "name": skill.name, "path": requested },
    )
  }
  if !@fsx.exists(resolved_path) {
    return mooncode_tool_error_result(
      "read_skill",
      message="skill resource does not exist",
      metadata={ "name": skill.name, "path": requested },
    )
  }
  let content = @fsx.read_file(resolved_path)
  let relative_path = if requested == "" { "SKILL.md" } else { requested }
  mooncode_tool_ok_result(
    "read_skill",
    message="loaded complete skill resource",
    output=content,
    metadata={
      "name": skill.name,
      "description": skill.description,
      "path": relative_path,
      "location": resolved_path,
      "content_sha256_base64": mooncode_runtime_turn_sha256_base64(content),
      "content_chars": content.length(),
      "truncated": false,
    },
  )
}

///|
fn mooncode_runtime_turn_loaded_skill_messages(
  all_tool_results : Array[Json],
) -> Array[Json] {
  let messages : Array[Json] = []
  let retained : Map[String, Bool] = {}
  for execution in all_tool_results {
    if !mooncode_json_bool(execution, "accepted", default=false) ||
      mooncode_json_string(execution, "tool", default="") != "read_skill" {
      continue
    }
    let result = mooncode_json_object_field_or_empty(execution, "result")
    let metadata = mooncode_json_object_field_or_empty(result, "metadata")
    let location = mooncode_json_string(metadata, "location", default="")
    if location == "" || retained.contains(location) {
      continue
    }
    retained[location] = true
    let name = mooncode_json_string(metadata, "name", default="")
    let path = mooncode_json_string(metadata, "path", default="SKILL.md")
    messages.push(
      mooncode_runtime_context_text_message(
        "user",
        "Retained installed skill resource `\{name}/\{path}`. Continue to follow it:\n\n" +
        mooncode_json_string(result, "output", default=""),
        SkillContext,
        "skill.loaded_resource",
      ),
    )
  }
  messages
}

///|
/// Keep the fact that a skill was fully loaded available after provider and
/// transcript compaction without resending the complete skill body on every
/// planner round. The original accepted tool result remains in the durable
/// journal and continues to govern the command.
fn mooncode_runtime_turn_loaded_skill_receipt_messages(
  all_tool_results : Array[Json],
) -> Array[Json] {
  let messages : Array[Json] = []
  let retained : Map[String, Bool] = {}
  for execution in all_tool_results {
    if !mooncode_json_bool(execution, "accepted", default=false) ||
      mooncode_json_string(execution, "tool", default="") != "read_skill" {
      continue
    }
    let result = mooncode_json_object_field_or_empty(execution, "result")
    let metadata = mooncode_json_object_field_or_empty(result, "metadata")
    let location = mooncode_json_string(metadata, "location", default="")
    if location == "" || retained.contains(location) {
      continue
    }
    retained[location] = true
    let name = mooncode_json_string(metadata, "name", default="")
    let path = mooncode_json_string(metadata, "path", default="SKILL.md")
    let digest = mooncode_json_string(
      metadata,
      "content_sha256_base64",
      default="unrecorded",
    )
    let content_chars = mooncode_json_int(metadata, "content_chars", default=0)
    messages.push(
      mooncode_runtime_context_text_message(
        "system",
        "Loaded-skill receipt: `\{name}/\{path}` was loaded completely earlier in this preserved command (chars=\{content_chars}, sha256=\{digest}). Its full bytes remain in the durable journal and it already governs this run. Treat its trigger and loading gate as satisfied and continue following it. A missing or empty filesystem result cannot invalidate this receipt. Do not select read, shell, glob, grep, find, ls, or web tools to locate this skill, and do not call `read_skill` again unless this receipt is absent or the recorded version digest changes. Installed skill resources are served only through `read_skill`; they are not MoonBook or home-directory filesystem paths.",
        SkillContext,
        "skill.loaded_receipt",
      ),
    )
  }
  messages
}
