///|
let mooncode_image_jobs : Map[String, Bool] = Map([])

///|
fn mooncode_image_request(
  model : String,
  prompt : String,
  images : Array[Json],
) -> Json {
  let content : Array[Json] = [{ "type": "input_text", "text": prompt }]
  for image in images {
    content.push({
      "type": "input_image",
      "image_url": "data:" +
      mooncode_json_string(image, "media_type", default="image/png") +
      ";base64," +
      mooncode_json_string(image, "data_base64", default=""),
    })
  }
  {
    "model": model,
    "input": [{ "role": "user", "content": Json::array(content) }],
    "tools": [{ "type": "image_generation", "output_format": "png" }],
    "tool_choice": { "type": "image_generation" },
  }
}

///|
fn mooncode_image_outputs(payload : Json) -> Array[String] {
  mooncode_json_array_items(payload, "output")
  .filter(item => {
    mooncode_json_string(item, "type", default="") == "image_generation_call"
  })
  .map(item => mooncode_json_string(item, "result", default=""))
  .filter(item => item != "")
}

///|
async fn Daemon::mooncode_start_image_job(
  self : Daemon,
  group : @async.TaskGroup[Unit],
  session : String,
  body : Json,
) -> Unit {
  let root = mooncode_json_string(body, "book_root", default="")
  guard self.mooncode_session_record(session, root) is Some(_) else {
    raise mooncode_session_management_error(
      404, "Not Found", "Chat not found", session,
    )
  }
  let prompt = mooncode_json_string(body, "prompt", default="")
    .trim()
    .to_owned()
  if prompt == "" {
    raise mooncode_session_management_error(
      400, "Bad Request", "Describe the image or the changes you want", session,
    )
  }
  let images = mooncode_json_array_items(body, "images")
  if !images.is_empty() {
    match
      mooncode_command_media_validation({
        "command": "prompt",
        "content_parts": Json::array(images),
      }) {
      Err(error) =>
        raise mooncode_session_management_error(
          400, "Bad Request", error, session,
        )
      _ => ()
    }
  }
  let binding = self.mooncode_binding_for_session(session)
  ignore(binding.bind_book_root(root))
  binding.restore_session_metadata()
  let requested = mooncode_json_string(body, "model", default=binding.model)
  let selector = mooncode_runtime_model_selector(requested).unwrap_or(requested)
  let model = match
    mooncode_runtime_turn_resolve_model(
      self.models,
      self.home,
      { "book_root": root, "model_workspace": binding.model_workspace },
      selector,
    ) {
    Some(value) => value
    None =>
      raise mooncode_session_management_error(
        400, "Model unavailable", "Choose a configured model whose provider supports image generation through Responses",
        session,
      )
  }
  let job_id = "image-" + self.uuid.v4().to_string()
  mooncode_append_session_journal(root, session, mooncode_journal_event(), {
    "id": job_id + ":started",
    "kind": "session.image.job",
    "job_id": job_id,
    "session_id": session,
    "status": "running",
    "prompt": prompt,
    "model": requested,
    "created_at": self.clock.now(),
    "title": "Creating image",
    "lane": "session",
  })
  mooncode_image_jobs[job_id] = true
  ignore(
    group.spawn(
      async fn() {
        defer mooncode_image_jobs.remove(job_id)
        let result : Json = mooncode_generate_image_artifacts(
          model, root, job_id, prompt, images,
        ) catch {
          InvalidJournal(message) => { "status": "failed", "message": message }
          error => { "status": "failed", "message": error.to_string() }
        }
        let event = result
          |> mooncode_json_object_with_field("id", Json(job_id + ":finished"))
          |> mooncode_json_object_with_field("kind", Json("session.image.job"))
          |> mooncode_json_object_with_field("job_id", Json(job_id))
          |> mooncode_json_object_with_field("session_id", Json(session))
          |> mooncode_json_object_with_field("prompt", Json(prompt))
          |> mooncode_json_object_with_field("model", Json(requested))
          |> mooncode_json_object_with_field(
            "created_at",
            self.clock.now().to_json(),
          )
        mooncode_append_session_journal(
          root,
          session,
          mooncode_journal_event(),
          event,
        )
      },
      no_wait=true,
    ),
  )
}

///|
async fn mooncode_generate_image_artifacts(
  model : @model.Model,
  root : String,
  job_id : String,
  prompt : String,
  images : Array[Json],
) -> Json {
  let base = model.base_url.trim_end(chars="/").to_owned()
  let endpoint = if base.has_suffix("/responses") {
    base
  } else {
    base + "/responses"
  }
  let token = if model.api_key != "" {
    model.api_key
  } else {
    model.access_token.unwrap_or("")
  }
  let (response, bytes) = @http.post(
    endpoint,
    mooncode_image_request(model.model_name, prompt, images).stringify(),
    headers={
      "Content-Type": "application/json",
      "Authorization": "Bearer " + token,
    },
  )
  let payload = @json.parse(bytes.text())
  if response.code < 200 || response.code >= 300 {
    let error = mooncode_json_object_field_or_empty(payload, "error")
    raise InvalidJournal(
      mooncode_json_string(
        error,
        "message",
        default="This provider could not generate an image (HTTP \{response.code})",
      ),
    )
  }
  let outputs = mooncode_image_outputs(payload)
  if outputs.is_empty() {
    raise InvalidJournal(
      "This model did not return an image. Choose a model with Responses image generation support.",
    )
  }
  let paths : Array[Json] = []
  @fsx.make_directory(
    @pathx.join(root, "artifacts/images"),
    recursive=true,
    exists_ok=true,
  )
  for index, output in outputs {
    let image = @base64.decode(output)
    if !mooncode_media_image_signature_valid("image/png", image) {
      raise InvalidJournal("The provider did not return a PNG image")
    }
    let relative = "artifacts/images/" +
      job_id +
      "-" +
      index.to_string() +
      ".png"
    @fsx.write_bytes_to_file(@pathx.join(root, relative), image)
    paths.push(Json(relative))
  }
  {
    "status": "done",
    "paths": Json::array(paths),
    "response_id": mooncode_json_string(payload, "id", default=""),
  }
}

///|
fn mooncode_image_job_projection(events : Array[Json]) -> Array[Json] {
  let jobs : Map[String, Json] = Map([])
  for event in events {
    if mooncode_json_string(event, "kind", default="") == "session.image.job" {
      let id = mooncode_json_string(event, "job_id", default="")
      jobs[id] = if mooncode_json_string(event, "status", default="") ==
        "running" &&
        !mooncode_image_jobs.contains(id) {
        mooncode_json_object_with_field(event, "status", Json("interrupted"))
      } else {
        event
      }
    }
  }
  jobs.values().to_array()
}
