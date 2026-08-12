///|
const MoonDeskPromotionRequestBytes : Int = 65_536

///|
const MoonDeskPromotionMaxItems : Int = 256

///|
priv struct MoonDeskPromotionItem {
  source_relative : String
  destination_relative : String
} derive(Debug, Eq, ToJson, @json.FromJson)

///|
priv struct MoonDeskPromotionRequest {
  protocol_version : Int
  instance_id : String
  request_id : String
  workspace_id : String
  retention_id : String
  approval_digest : String
  command_digest : String
  items : Array[MoonDeskPromotionItem]
} derive(Debug, Eq, ToJson, @json.FromJson)

///|
priv struct MoonFortPromotionError {
  code : String
  message : String
} derive(Debug, Eq, @json.FromJson)

///|
priv struct MoonFortPromotionResponse {
  protocol_version : Int
  retention_id : String
  workspace_id : String
  approval_digest : String
  command_digest : String
  promoted_paths : Array[String]
  completed : Bool
  error : MoonFortPromotionError?
} derive(Debug, Eq, @json.FromJson)

///|
fn moondesk_promotion_safe_digest(value : String) -> Bool {
  value.length() == 64 &&
  value.all(character => {
    character.is_ascii_digit() || (character >= 'a' && character <= 'f')
  })
}

///|
fn moondesk_promotion_safe_relative_path(value : String) -> Bool {
  value.length() >= 1 &&
  value.length() <= 4_096 &&
  !value.has_prefix("/") &&
  !value.has_suffix("/") &&
  !value.contains("//") &&
  !value.contains("\u{0}") &&
  !value.split("/").any(component => component == "." || component == "..")
}

///|
fn moondesk_promotion_parse_request(
  json : Json,
) -> MoonDeskPromotionRequest raise {
  let request : MoonDeskPromotionRequest = @json.from_json(json) catch {
    _ => fail("invalid typed promotion request")
  }
  guard request.protocol_version == 1 &&
    moondesk_sandbox_safe_request_id(request.request_id) &&
    request.retention_id.length() >= 1 &&
    request.retention_id.length() <= 128 &&
    request.retention_id.all(character => {
      character.is_ascii_alphabetic() ||
      character.is_ascii_digit() ||
      character == '-' ||
      character == '_'
    }) &&
    moondesk_promotion_safe_digest(request.approval_digest) &&
    moondesk_promotion_safe_digest(request.command_digest) &&
    request.items.length() >= 1 &&
    request.items.length() <= MoonDeskPromotionMaxItems &&
    request.items.all(item => {
      moondesk_promotion_safe_relative_path(item.source_relative) &&
      moondesk_promotion_safe_relative_path(item.destination_relative)
    }) else {
    fail("invalid typed promotion request")
  }
  let sources : Map[String, Bool] = {}
  let destinations : Map[String, Bool] = {}
  for item in request.items {
    guard !sources.contains(item.source_relative) &&
      !destinations.contains(item.destination_relative) else {
      fail("duplicate promotion mapping")
    }
    sources[item.source_relative] = true
    destinations[item.destination_relative] = true
  }
  request
}

///|
fn moondesk_promotion_moonfort_request(
  request : MoonDeskPromotionRequest,
) -> Json {
  {
    "protocol_version": 3,
    "retention_id": request.retention_id,
    "workspace_id": request.workspace_id,
    "approval_digest": request.approval_digest,
    "command_digest": request.command_digest,
    "items": request.items.map(item => {
      "source_relative_path": item.source_relative,
      "destination_relative_path": item.destination_relative,
    }),
  }
}

///|
fn moondesk_promotion_validate_response(
  request : MoonDeskPromotionRequest,
  response : MoonFortPromotionResponse,
) -> Array[String] raise {
  let expected = request.items.map(item => item.destination_relative)
  guard response.protocol_version == 3 &&
    response.retention_id == request.retention_id &&
    response.workspace_id == request.workspace_id &&
    response.approval_digest == request.approval_digest &&
    response.command_digest == request.command_digest &&
    response.completed &&
    response.error is None &&
    response.promoted_paths == expected &&
    response.promoted_paths.all(moondesk_promotion_safe_relative_path) else {
    fail("MoonFort promotion response did not match the reviewed request")
  }
  response.promoted_paths
}

///|
async fn execute_moondesk_promotion(
  request : MoonDeskPromotionRequest,
  route_config : @moondesk_sandbox_config.Config,
) -> Json {
  guard request.instance_id == route_config.instance_id &&
    request.workspace_id == route_config.workspace_id else {
    fail("promotion request binding does not match the configured instance")
  }
  let launcher = @moonfort_config.load_promotion_adapter_config()
  guard launcher is Some(launcher) else {
    fail("MoonFort promotion adapter is unavailable")
  }
  let client = @execution_sandbox_adapter.PromotionClient::new(
    launcher.promotion_path,
    launcher.promotion_args,
    launcher.executor_config_path,
    launcher.receipt_root,
  )
  let body = moondesk_promotion_moonfort_request(request).stringify()
  let process = client.promote_retention(body)
  guard process.status == 0 else { fail("MoonFort promotion process failed") }
  let response : MoonFortPromotionResponse = @json.from_json(
    @json.parse(process.stdout.trim().to_owned()),
  ) catch {
    _ => fail("MoonFort promotion response is invalid")
  }
  let promoted_paths = moondesk_promotion_validate_response(request, response)
  {
    "protocol_version": 1,
    "instance_id": request.instance_id,
    "request_id": request.request_id,
    "workspace_id": request.workspace_id,
    "retention_id": request.retention_id,
    "approval_digest": request.approval_digest,
    "command_digest": request.command_digest,
    "completed": true,
    "promoted_paths": promoted_paths,
    "evidence": {
      "moonfort_protocol_version": response.protocol_version,
      "retention_id": response.retention_id,
      "workspace_id": response.workspace_id,
      "approval_digest": response.approval_digest,
      "command_digest": response.command_digest,
      "completed": response.completed,
      "promoted_paths": response.promoted_paths,
    },
  }
}

///|
async fn Daemon::moondesk_promote_retention(
  self : Daemon,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  ignore(self)
  let route_config = @moondesk_sandbox_config.load() catch {
    _ =>
      raise json_error(503, "ServiceUnavailable", {
        "error": {
          "code": "sandbox_unavailable",
          "message": "execution sandbox route is unavailable",
        },
      })
  }
  guard route_config is Some(route_config) else {
    raise json_error(503, "ServiceUnavailable", {
      "error": {
        "code": "sandbox_unavailable",
        "message": "execution sandbox route is unavailable",
      },
    })
  }
  let provided_token = r.headers.get("x-moonclaw-execution-token").unwrap_or("")
  guard moondesk_sandbox_constant_time_equal(
    provided_token,
    route_config.auth_token,
  ) else {
    raise json_error(401, "Unauthorized", {
      "error": {
        "code": "unauthorized",
        "message": "sandbox route authentication failed",
      },
    })
  }
  let request = moondesk_promotion_parse_request(
    moondesk_sandbox_read_request_bounded(r, MoonDeskPromotionRequestBytes),
  ) catch {
    _ =>
      raise json_error(422, "UnprocessableContent", {
        "error": {
          "code": "invalid_request",
          "message": "typed promotion request was rejected",
        },
      })
  }
  let result = execute_moondesk_promotion(request, route_config) catch {
    _ =>
      raise json_error(503, "ServiceUnavailable", {
        "error": {
          "code": "promotion_refused",
          "message": "MoonFort promotion failed closed",
        },
      })
  }
  w.header().set("Content-Type", "application/json")
  w.write_header(200)
  w.write(result.stringify())
}
