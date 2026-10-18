///|
async fn mooncode_realtime_credentials(
  model : @model.Model,
  body : Json,
) -> Json {
  let base = model.base_url.trim_end(chars="/").to_owned()
  let realtime_model = mooncode_json_string(
    body,
    "realtime_model",
    default="gpt-realtime",
  )
  let voice = mooncode_json_string(body, "voice", default="marin")
  let token = if model.api_key != "" {
    model.api_key
  } else {
    model.access_token.unwrap_or("")
  }
  let request : Json = {
    "session": {
      "type": "realtime",
      "model": realtime_model,
      "audio": { "output": { "voice": voice } },
      "instructions": "You are the voice companion for this coding conversation. Help the user think through their task. Use an available coding-request tool to hand execution to the coding agent, and report its returned result accurately.\n" +
      mooncode_json_string(body, "context", default=""),
    },
  }
  let (response, data) = @http.post(
    base + "/realtime/client_secrets",
    request.stringify(),
    headers={
      "Content-Type": "application/json",
      "Authorization": "Bearer " + token,
    },
  )
  let payload = @json.parse(data.text()) catch {
    _ => raise InvalidJournal("This provider returned unreadable realtime JSON")
  }
  if response.code < 200 || response.code >= 300 {
    let error = mooncode_json_object_field_or_empty(payload, "error")
    let message = mooncode_json_string(
      error,
      "message",
      default="This provider could not start realtime voice (HTTP \{response.code})",
    )
    raise InvalidJournal(
      if token == "" {
        message
      } else {
        message
        .split(token)
        .map(part => part.to_owned())
        .collect()
        .join("[redacted]")
      },
    )
  }
  let value = mooncode_json_string(payload, "value", default="")
  if value == "" {
    raise InvalidJournal(
      "This provider did not return a realtime client secret",
    )
  }
  let expires_at = match payload {
    Object(fields) => fields.get("expires_at").unwrap_or(Json::null())
    _ => Json::null()
  }
  if token != "" && value.contains(token) {
    raise InvalidJournal(
      "This provider returned an invalid realtime client secret",
    )
  }
  guard expires_at is Number(_) || expires_at == Json::null() else {
    raise InvalidJournal(
      "This provider returned an invalid realtime expiration",
    )
  }
  {
    "value": value,
    "expires_at": expires_at,
    "endpoint": base + "/realtime/calls",
    "model": realtime_model,
  }
}

///|
async fn Daemon::mooncode_realtime_session(
  self : Daemon,
  config : @moondesk_sandbox_config.Config,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  self.with_mooncode_integration_request(config, r, (body, root) => {
    let session = mooncode_json_string(body, "session_id", default="")
    let mut default_model = ""
    let mut model_workspace = ""
    if session != "" {
      let binding = self.mooncode_binding_for_session(session)
      guard binding.bind_book_root(root) else {
        raise json_error(409, "Conflict", {
          "error": { "message": "Session is bound to a different Book" },
        })
      }
      // Admission restored only validated metadata through pinned descriptors.
      default_model = binding.model
      model_workspace = binding.model_workspace
    }
    let requested = mooncode_json_string(body, "model", default=default_model)
    let requested = if requested.trim() == "" {
      default_model
    } else {
      requested
    }
    let selector = mooncode_runtime_model_selector(requested).unwrap_or(
      requested,
    )
    let selection : Json = if model_workspace == "" {
      { "book_root": root }
    } else {
      { "book_root": root, "model_workspace": model_workspace }
    }
    let model = match
      mooncode_runtime_turn_resolve_model(
        self.models,
        self.home,
        selection,
        selector,
        resource_reader=path => @book_runtime.read_resource(path.to_owned()),
      ) {
      Some(model) => model
      None =>
        raise json_error(400, "Model unavailable", {
          "error": {
            "message": "Choose a configured provider that supports realtime voice",
          },
        })
    }
    let result = mooncode_realtime_credentials(model, body) catch {
      InvalidJournal(message) =>
        raise json_error(502, "Voice unavailable", {
          "error": { "message": message },
        })
      _ =>
        raise json_error(502, "Voice unavailable", {
          "error": { "message": "Could not connect to the realtime provider" },
        })
    }
    w.header().set("Content-Type", "application/json")
    w.write_header(200)
    w.write(result.stringify())
  }) catch {
    HttpError(..) as error => raise error
    _ =>
      raise json_error(403, "Forbidden", {
        "error": { "message": "Configured model resource is unavailable" },
      })
  }
}
