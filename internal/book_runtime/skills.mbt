///|
pub async fn read_skill(book_root : String, arguments : Json) -> Json {
  let name = text(arguments, "name").trim().to_owned()
  if name == "" {
    return error("read_skill", "skill name must be non-empty")
  }
  let loader = @skills.Loader::new(cwd=book_root) catch {
    e => return error("read_skill", "failed to discover installed skills: \{e}")
  }
  loader.load() catch {
    e => return error("read_skill", "failed to discover installed skills: \{e}")
  }
  let skill = match loader.skills().get(name) {
    Some(skill) => skill
    None => {
      let matches = loader
        .skills()
        .values()
        .filter(skill => skill.name == name)
        .collect()
      if matches.length() > 1 {
        return error(
          "read_skill", "Multiple installed Skills share this display name; use the exact installed folder id",
        )
      }
      if matches.is_empty() {
        return error("read_skill", "installed skill not found: \{name}")
      }
      matches[0]
    }
  }
  let requested = text(arguments, "path").trim().to_owned()
  if requested != "" &&
    (
      @pathx.is_absolute(requested) ||
      requested.split("/").any(part => part == "..")
    ) {
    return error(
      "read_skill",
      "skill resource path must stay inside the selected skill",
      metadata={ "name": skill.name, "path": requested },
    )
  }
  let root = @fsx.resolve(@pathx.dirname(skill.location)) catch {
    e => return error("read_skill", "failed to resolve skill root: \{e}")
  }
  let path = if requested == "" || requested == "SKILL.md" {
    skill.location
  } else {
    @pathx.join(root, requested)
  }
  let path = @fsx.resolve(path) catch {
    e => return error("read_skill", "failed to resolve skill resource: \{e}")
  }
  if path != root && !path.has_prefix(root + "/") {
    return error(
      "read_skill",
      "skill resource path escapes the selected skill",
      metadata={ "name": skill.name, "path": requested },
    )
  }
  if !@fsx.exists(path) {
    return error("read_skill", "skill resource does not exist", metadata={
      "name": skill.name,
      "path": requested,
    })
  }
  let content = @fsx.read_file(path)
  {
    "tool": "read_skill",
    "ok": true,
    "is_error": false,
    "message": "loaded complete skill resource",
    "output": content,
    "metadata": {
      "name": skill.id,
      "id": skill.id,
      "display_name": skill.name,
      "description": skill.description,
      "path": if requested == "" {
        "SKILL.md"
      } else {
        requested
      },
      "location": path,
      "content_sha256_base64": @base64.encode(
        Bytes::from_array(@crypto.sha256(@encoding/utf8.encode(content))),
        url_safe=false,
      ),
      "content_chars": content.length(),
      "truncated": false,
    },
  }
}

///|
pub async fn instructions(book_root : String) -> String {
  let agents = @fsx.read_file(@pathx.join(book_root, "AGENTS.md")) catch {
    _ => ""
  }
  let canonical_book_root = @fs.realpath(book_root)
  let integrations = mcp_servers(canonical_book_root)
    .filter(server => flag(server, "enabled", default=true))
    .map(server => text(server, "id"))
  let available = if integrations.is_empty() {
    ""
  } else {
    "\nAvailable MoonBook MCP integrations: " +
    integrations.join(", ") +
    ". Use mcp_list_tools to discover their actual schemas and mcp_call_tool with the selected server and exact tool name. Preserve sources and report missing data honestly.\n"
  }
  "\n<moonbook_instructions>\n" +
  agents +
  "\n</moonbook_instructions>\n" +
  available +
  "\nUse read_skill to load a selected Skill's full instructions and its required resources before applying it.\n"
}
