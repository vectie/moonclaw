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
fn mooncode_skill_catalog_row(
  name : String,
  description : String,
  location : String,
  book_root : String,
) -> Json {
  let book_local = location.has_prefix(book_root + "/")
  {
    "name": name,
    "id": @pathx.basename(@pathx.dirname(location)).to_owned(),
    "description": description,
    "source": if book_local {
      "moonbook"
    } else {
      "installed"
    },
    "location": location,
    "authority": "moonclaw",
  }
}

///|
async fn mooncode_skill_catalog_json(
  book_root : String,
) -> Result[Json, String] {
  let loader = mooncode_skill_loader(book_root) catch {
    error => return Err("Skill discovery failed: \{error}")
  }
  let names = loader.skills().keys().collect()
  names.sort()
  let rows : Array[Json] = []
  for name in names {
    match loader.skills().get(name) {
      Some(skill) =>
        rows.push(
          mooncode_skill_catalog_row(
            skill.name,
            skill.description,
            skill.location,
            book_root,
          ),
        )
      None => ()
    }
  }
  Ok({
    "kind": "mooncode-skill-catalog",
    "owner": "moonclaw",
    "book_root": book_root,
    "skills": Json::array(rows),
    "skill_count": rows.length(),
    "content_included": false,
  })
}

///|
async fn Daemon::mooncode_list_skills(
  _self : Daemon,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let book_root = mooncode_request_book_root(r)
  if book_root == "" || !@fsx.exists(book_root) {
    raise json_error(400, "Bad Request", {
      "error": { "code": -1, "message": "A valid MoonBook root is required" },
    })
  }
  let catalog = match mooncode_skill_catalog_json(book_root) {
    Ok(value) => value
    Err(error) =>
      raise json_error(503, "Service Unavailable", {
        "error": { "code": -1, "message": error },
      })
  }
  w.header().set("Content-Type", "application/json")
  w.write_header(200)
  w.write(catalog.stringify(indent=2))
}

///|
async fn mooncode_runtime_turn_skill_catalog(book_root : String) -> String {
  let loader = mooncode_skill_loader(book_root) catch {
    error => return "\n\nSkill discovery is unavailable for this turn: \{error}"
  }
  let names = loader.skills().keys().collect()
  names.sort()
  mooncode_skill_index_prompt(names)
}

///|
fn mooncode_skill_index_prompt(names : Array[String]) -> String {
  if names.is_empty() {
    return "\n\nNo installed skills were discovered for this MoonBook."
  }
  let out = StringBuilder()
  out.write_string(
    (
      #|
      #|
      #|Use read_skill(name=id) for full instructions and referenced paths, or
      #|read_skill() for full descriptions. Read selected instructions completely.
      #|Load mooncode-tools for view_image, moon_ide, moon_cmd, apply_patch or checkpoint.
      #|read_skill ends the batch; declared tools are exposed next turn, not authorized.
      #|
      #|<available_skills>
      #|
    ),
  )
  out.write_string(Json(names).stringify())
  out.write_string("\n</available_skills>")
  out.to_string()
}

///|
async fn mooncode_tool_read_skill(book_root : String, arguments : Json) -> Json {
  if mooncode_json_string(arguments, "name", default="").trim().is_empty() {
    return match mooncode_skill_catalog_json(book_root) {
      Ok(catalog) =>
        mooncode_tool_ok_result(
          "read_skill",
          message="Installed skill descriptions",
          output=catalog.stringify(),
          metadata={},
        )
      Err(error) => mooncode_tool_error_result("read_skill", message=error)
    }
  }
  @book_runtime.read_skill(book_root, arguments)
}

///|
fn mooncode_runtime_turn_loaded_skill_messages(
  all_tool_results : Array[Json],
) -> Array[Json] {
  let messages : Array[Json] = []
  let retained : Map[String, Bool] = Map([])
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
