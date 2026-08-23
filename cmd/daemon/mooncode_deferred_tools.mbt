///|
const MOONCODE_DEFERRED_TOOL_CATALOG_CONTRACT : String = "moonclaw.deferred-tool-catalog.v1"

///|
const MOONCODE_DEFERRED_TOOL_SEARCH_MAX_RESULTS : Int = 5

///|
fn mooncode_runtime_turn_deferred_tool_search_spec() -> @openai.ChatCompletionToolParam {
  mooncode_runtime_turn_model_tool(
    "tool_search",
    "Search the bounded MoonCode deferred-tool catalog. Successful matches are loaded into the next planner request; this tool does not execute the matched capability.",
    {
      "type": "object",
      "properties": {
        "query": {
          "type": "string",
          "description": "Short capability query, such as browser screenshots, MoonBit semantic navigation, or delegate workers.",
        },
        "max_results": {
          "type": "integer",
          "minimum": 1,
          "maximum": MOONCODE_DEFERRED_TOOL_SEARCH_MAX_RESULTS,
        },
      },
      "required": ["query"],
      "additionalProperties": false,
    },
  )
}

///|
fn mooncode_runtime_turn_deferred_tool_words(value : String) -> Array[String] {
  let normalized = StringBuilder()
  for character in value.to_lower() {
    if character.is_ascii_alphabetic() || character.is_ascii_digit() {
      normalized.write_char(character)
    } else {
      normalized.write_char(' ')
    }
  }
  normalized
  .to_string()
  .split(" ")
  .filter_map(word => if word == "" { None } else { Some(word.to_string()) })
  .collect()
}

///|
fn mooncode_runtime_turn_deferred_tool_search_text(value : String) -> String {
  " " + mooncode_runtime_turn_deferred_tool_words(value).join(" ") + " "
}

///|
fn mooncode_runtime_turn_deferred_tool_summary(description : String) -> String {
  let description = description.trim().to_owned()
  if description.length() <= 240 {
    description
  } else {
    description[:240].to_owned() + "…"
  }
}

///|
fn mooncode_runtime_turn_deferred_tool_query_valid(query : String) -> Bool {
  if query == "" || query.length() > 256 {
    return false
  }
  for character in query {
    if character < ' ' || character == '\u{7f}' {
      return false
    }
  }
  true
}

///|
/// Build the discovery registry from the same typed definitions sent to the
/// provider. First occurrence wins so an accidental duplicate definition
/// cannot make receipt validation or result ordering ambiguous.
fn mooncode_runtime_turn_deferred_tool_registry_from_tools(
  tools : Array[@openai.ChatCompletionToolParam],
) -> Array[Json] {
  let base_names = mooncode_runtime_turn_dynamic_coding_tool_names("")
  let seen : Array[String] = []
  let registry : Array[Json] = []
  for ordinal, tool in tools {
    let function = mooncode_json_object_field_or_empty(
      tool.to_json(),
      "function",
    )
    let name = mooncode_json_string(function, "name", default="")
    if name == "" || seen.contains(name) {
      continue
    }
    seen.push(name)
    // The small coding bundle already exposes these definitions. Every other
    // authoritative definition is deferred automatically, including tools
    // added after this registry was implemented.
    if base_names.contains(name) {
      continue
    }
    let description = mooncode_json_string(
      function,
      "description",
      default=name,
    )
    let parameters = mooncode_json_object_field_or_empty(function, "parameters")
    registry.push({
      "name": name,
      "summary": mooncode_runtime_turn_deferred_tool_summary(description),
      "search_text": mooncode_runtime_turn_deferred_tool_search_text(
        name + " " + description + " " + parameters.stringify(),
      ),
      "ordinal": ordinal,
    })
  }
  registry
}

///|
fn mooncode_runtime_turn_deferred_tool_catalog() -> Array[Json] {
  mooncode_runtime_turn_deferred_tool_registry_from_tools(
    mooncode_runtime_turn_model_tools(),
  )
}

///|
fn mooncode_runtime_turn_deferred_tool_match_score(
  query : String,
  entry : Json,
) -> Int {
  let name = mooncode_json_string(entry, "name", default="")
  let normalized_query = mooncode_runtime_turn_deferred_tool_words(query).join(
    " ",
  )
  let normalized_name = mooncode_runtime_turn_deferred_tool_words(name).join(
    " ",
  )
  let search_text = mooncode_json_string(entry, "search_text", default="")
  let mut score = 0
  if normalized_query == normalized_name {
    score += 1000
  } else if normalized_query.contains(normalized_name) {
    score += 500
  } else if normalized_query.length() >= 3 &&
    normalized_name.contains(normalized_query) {
    score += 250
  }
  if normalized_query != "" &&
    search_text.contains(" " + normalized_query + " ") {
    score += 200
  }
  let name_words = mooncode_runtime_turn_deferred_tool_words(name)
  for word in mooncode_runtime_turn_deferred_tool_words(query) {
    if word.length() < 2 {
      continue
    }
    if name_words.contains(word) {
      score += 100
    } else if search_text.contains(" " + word + " ") {
      score += 20
    }
  }
  score
}

///|
fn mooncode_runtime_turn_deferred_tool_matches(
  query : String,
  max_results : Int,
  excluded_names? : Array[String] = [],
) -> Array[Json] {
  mooncode_runtime_turn_deferred_tool_matches_in_catalog(
    mooncode_runtime_turn_deferred_tool_catalog(),
    query,
    max_results,
    excluded_names~,
  )
}

///|
fn mooncode_runtime_turn_deferred_tool_matches_in_catalog(
  catalog : Array[Json],
  query : String,
  max_results : Int,
  excluded_names? : Array[String] = [],
) -> Array[Json] {
  let scores = catalog.map(entry => {
    mooncode_runtime_turn_deferred_tool_match_score(query, entry)
  })
  let selected_indices : Array[Int] = []
  let matches : Array[Json] = []
  for _ in 0..<max_results {
    let mut best_index = -1
    let mut best_score = 0
    for index, score in scores {
      let name = mooncode_json_string(catalog[index], "name", default="")
      if !selected_indices.contains(index) &&
        !excluded_names.contains(name) &&
        score > best_score {
        best_index = index
        best_score = score
      }
    }
    if best_index < 0 {
      break
    }
    selected_indices.push(best_index)
    let entry = catalog[best_index]
    matches.push({
      "name": mooncode_json_string(entry, "name", default=""),
      "summary": mooncode_json_string(entry, "summary", default=""),
      "score": best_score,
    })
  }
  matches
}

///|
fn mooncode_runtime_turn_deferred_tool_search_result(
  arguments : Json,
  excluded_names? : Array[String] = [],
) -> Json {
  let query = mooncode_json_string(arguments, "query", default="")
    .trim()
    .to_owned()
    .to_lower()
  if query == "" {
    return mooncode_tool_error_result(
      "tool_search",
      message="deferred tool search requires a non-empty query",
      metadata={ "contract": MOONCODE_DEFERRED_TOOL_CATALOG_CONTRACT },
    )
  }
  if query.length() > 256 {
    return mooncode_tool_error_result(
      "tool_search",
      message="deferred tool search query exceeds the 256-character limit",
      metadata={ "contract": MOONCODE_DEFERRED_TOOL_CATALOG_CONTRACT },
    )
  }
  if !mooncode_runtime_turn_deferred_tool_query_valid(query) {
    return mooncode_tool_error_result(
      "tool_search",
      message="deferred tool search query contains unsupported control characters",
      metadata={ "contract": MOONCODE_DEFERRED_TOOL_CATALOG_CONTRACT },
    )
  }
  let requested_limit = mooncode_json_int(arguments, "max_results", default=3)
  let limit = if requested_limit < 1 {
    1
  } else if requested_limit > MOONCODE_DEFERRED_TOOL_SEARCH_MAX_RESULTS {
    MOONCODE_DEFERRED_TOOL_SEARCH_MAX_RESULTS
  } else {
    requested_limit
  }
  let matches = mooncode_runtime_turn_deferred_tool_matches(
    query,
    limit,
    excluded_names~,
  )
  let names = matches.map(match_ => {
    mooncode_json_string(match_, "name", default="").to_json()
  })
  mooncode_tool_ok_result(
    "tool_search",
    message=if matches.is_empty() {
      "No deferred MoonCode tool matched the bounded catalog query"
    } else {
      "Matched \{matches.length()} deferred MoonCode tool(s) for the next planner request"
    },
    output=Json::array(matches).stringify(),
    metadata={
      "contract": MOONCODE_DEFERRED_TOOL_CATALOG_CONTRACT,
      "query": query,
      "limit": limit,
      "match_count": matches.length(),
      "loadable_tools": Json::array(names),
    },
  )
}

///|
fn mooncode_runtime_turn_deferred_tool_search_execution(
  command : Json,
  session_id : String,
  book_root : String,
  command_id : String,
  tool_call : Json,
  now~ : @clock.Timestamp,
) -> Json {
  let arguments = mooncode_json_object_field_or_empty(tool_call, "arguments")
  let result = if !mooncode_runtime_turn_dynamic_tool_bundles_enabled(command) ||
    mooncode_runtime_turn_explicit_allowed_tool_names(command).length() > 0 {
    mooncode_tool_error_result(
      "tool_search",
      message="deferred tool search is available only for dynamic bundles without an explicit planner allow-list",
      metadata={ "contract": MOONCODE_DEFERRED_TOOL_CATALOG_CONTRACT },
    )
  } else {
    let exposed_names = mooncode_runtime_turn_model_tools_for_command(command).map(tool => {
        let function = mooncode_json_object_field_or_empty(
          tool.to_json(),
          "function",
        )
        mooncode_json_string(function, "name", default="")
      },
    )
    mooncode_runtime_turn_deferred_tool_search_result(
      arguments,
      excluded_names=exposed_names,
    )
  }
  {
    "accepted": !mooncode_json_bool(result, "is_error", default=false),
    "kind": "mooncode-tool-execution",
    "protocol": mooncode_protocol_version(),
    "owner": "moonclaw",
    "session_id": session_id,
    "book_root": book_root,
    "command_id": command_id,
    "tool": "tool_search",
    "arguments": arguments,
    "result": result,
    "event": mooncode_tool_result_event(
      session_id,
      book_root,
      command_id,
      "tool_search",
      result,
      now~,
    ),
  }
}

///|
fn mooncode_runtime_turn_explicit_allowed_tool_names(
  command : Json,
) -> Array[String] {
  let payload = mooncode_json_object_field_or_empty(command, "payload")
  mooncode_json_array_items(payload, "planner_allowed_tools").filter_map(item => {
    match item {
      String(name) if name != "" => Some(name)
      _ => None
    }
  })
}

///|
fn mooncode_runtime_turn_validated_deferred_tool_names(
  command : Json,
  results : Array[Json],
) -> Array[String] {
  let names : Array[String] = []
  let catalog_names = mooncode_runtime_turn_deferred_tool_catalog().map(entry => {
    mooncode_json_string(entry, "name", default="")
  })
  for execution in results {
    let result = mooncode_json_object_field_or_empty(execution, "result")
    let metadata = mooncode_json_object_field_or_empty(result, "metadata")
    if mooncode_json_string(execution, "tool", default="") != "tool_search" ||
      !mooncode_json_bool(execution, "accepted", default=false) ||
      !mooncode_json_bool(result, "ok", default=false) ||
      mooncode_json_string(result, "tool", default="") != "tool_search" ||
      mooncode_json_string(metadata, "contract", default="") !=
      MOONCODE_DEFERRED_TOOL_CATALOG_CONTRACT {
      continue
    }
    let query = mooncode_json_string(metadata, "query", default="")
    let limit = mooncode_json_int(metadata, "limit", default=0)
    if query == "" ||
      query.length() > 256 ||
      limit < 1 ||
      limit > MOONCODE_DEFERRED_TOOL_SEARCH_MAX_RESULTS {
      continue
    }
    let exposed_names = mooncode_runtime_turn_model_tools_for_command(command).map(tool => {
        let function = mooncode_json_object_field_or_empty(
          tool.to_json(),
          "function",
        )
        mooncode_json_string(function, "name", default="")
      },
    )
    let expected = mooncode_runtime_turn_deferred_tool_matches(
      query,
      limit,
      excluded_names=exposed_names,
    ).map(match_ => mooncode_json_string(match_, "name", default=""))
    let declared = mooncode_json_array_string_items(metadata, "loadable_tools")
    if declared != expected ||
      mooncode_json_int(metadata, "match_count", default=-1) !=
      expected.length() {
      continue
    }
    for name in declared {
      if catalog_names.contains(name) && !names.contains(name) {
        names.push(name)
      }
    }
  }
  names
}

///|
fn mooncode_runtime_turn_model_tools_for_followup(
  command : Json,
  all_tool_results : Array[Json],
) -> Array[@openai.ChatCompletionToolParam] {
  let selected = mooncode_runtime_turn_model_tools_for_command(command)
  if !mooncode_runtime_turn_dynamic_tool_bundles_enabled(command) ||
    mooncode_runtime_turn_explicit_allowed_tool_names(command).length() > 0 {
    return selected
  }
  let loaded = mooncode_runtime_turn_validated_deferred_tool_names(
    command, all_tool_results,
  )
  if loaded.is_empty() {
    return selected
  }
  let selected_names = selected.map(tool => {
    let function = mooncode_json_object_field_or_empty(
      tool.to_json(),
      "function",
    )
    mooncode_json_string(function, "name", default="")
  })
  let all_tools = mooncode_runtime_turn_model_tools(
    active_goal_runtime=mooncode_json_string(
        mooncode_json_object_field_or_empty(command, "goal_runtime"),
        "goal_id",
        default="",
      ) !=
      "",
  )
  for tool in all_tools {
    let function = mooncode_json_object_field_or_empty(
      tool.to_json(),
      "function",
    )
    let name = mooncode_json_string(function, "name", default="")
    if loaded.contains(name) && !selected_names.contains(name) {
      selected.push(tool)
      selected_names.push(name)
    }
  }
  selected
}
