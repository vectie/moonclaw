///|
fn parse_json_body(body : Bytes) -> Result[Json, @protocol.ErrorShape] {
  let text : String = @encoding/utf8.decode(body) catch {
    _ =>
      return Err(@protocol.ErrorShape::{
        code: "invalid_utf8",
        message: "Invalid UTF-8 in request body",
        details: None,
        retryable: None,
        retry_after_ms: None,
      })
  }
  let json = @json.parse(text) catch {
    e =>
      return Err(@protocol.ErrorShape::{
        code: "parse_error",
        message: "Invalid JSON: \{e}",
        details: None,
        retryable: None,
        retry_after_ms: None,
      })
  }
  Ok(json)
}

///|
fn parse_http_channel_configure_params(
  channel_id : String,
  json : Json,
) -> Result[@protocol.Request, @protocol.ErrorShape] {
  match json {
    Object(obj) =>
      Ok(@protocol.Request::{
        id: "http:channels.configure:\{channel_id}",
        rpc_method: "channels.configure",
        params: Some({ "channel_id": channel_id, "config": obj }),
      })
    _ =>
      Err(@protocol.ErrorShape::{
        code: "invalid_params",
        message: "Channel configure body must be a JSON object",
        details: None,
        retryable: None,
        retry_after_ms: None,
      })
  }
}

///|
fn parse_http_channel_start_params(
  channel_id : String,
  json : Json,
) -> Result[@protocol.Request, @protocol.ErrorShape] {
  match json {
    Object({ "account_id": String(account_id), "config": config, .. }) =>
      Ok(@protocol.Request::{
        id: "http:channels.start:\{channel_id}:\{account_id}",
        rpc_method: "channels.start",
        params: Some({
          "channel_id": channel_id,
          "account_id": account_id,
          "config": config,
        }),
      })
    Object(_) =>
      Err(@protocol.ErrorShape::{
        code: "invalid_params",
        message: "Channel start body must include account_id and config",
        details: None,
        retryable: None,
        retry_after_ms: None,
      })
    _ =>
      Err(@protocol.ErrorShape::{
        code: "invalid_params",
        message: "Channel start body must be a JSON object",
        details: None,
        retryable: None,
        retry_after_ms: None,
      })
  }
}

///|
fn parse_http_channel_stop_params(
  channel_id : String,
  json : Json,
) -> Result[@protocol.Request, @protocol.ErrorShape] {
  match json {
    Object({ "account_id": String(account_id), .. }) =>
      Ok(@protocol.Request::{
        id: "http:channels.stop:\{channel_id}:\{account_id}",
        rpc_method: "channels.stop",
        params: Some({ "channel_id": channel_id, "account_id": account_id }),
      })
    Object(_) =>
      Err(@protocol.ErrorShape::{
        code: "invalid_params",
        message: "Channel stop body must include account_id",
        details: None,
        retryable: None,
        retry_after_ms: None,
      })
    _ =>
      Err(@protocol.ErrorShape::{
        code: "invalid_params",
        message: "Channel stop body must be a JSON object",
        details: None,
        retryable: None,
        retry_after_ms: None,
      })
  }
}

///|
async fn Gateway::handle_channels_list(
  self : Gateway,
  request : @protocol.Request,
  w : @httpx.ResponseWriter,
) -> Unit {
  let channels = self.channel_manager.list_channels()
  self.send_response(w, @protocol.Response::{
    id: request.id,
    ok: true,
    payload: Some({ "channels": channels.map(fn(ch) { ch.to_json() }) }),
    error: None,
  })
}

///|
async fn Gateway::handle_channels_get(
  self : Gateway,
  request : @protocol.Request,
  w : @httpx.ResponseWriter,
) -> Unit {
  let params = match request.params {
    Some(p) => p
    None =>
      return self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: false,
        payload: None,
        error: Some(@protocol.ErrorShape::{
          code: "missing_params",
          message: "Missing channel_id parameter",
          details: None,
          retryable: None,
          retry_after_ms: None,
        }),
      })
  }

  let channel_id : String = match params {
    String(id) => id
    Object(obj) =>
      match obj.get("channel_id") {
        Some(String(id)) => id
        _ =>
          return self.send_response(w, @protocol.Response::{
            id: request.id,
            ok: false,
            payload: None,
            error: Some(@protocol.ErrorShape::{
              code: "missing_channel_id",
              message: "Missing channel_id in params",
              details: None,
              retryable: None,
              retry_after_ms: None,
            }),
          })
      }
    _ =>
      return self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: false,
        payload: None,
        error: Some(@protocol.ErrorShape::{
          code: "invalid_params",
          message: "Invalid channel lookup parameters",
          details: None,
          retryable: None,
          retry_after_ms: None,
        }),
      })
  }

  match self.channel_manager.get_channel_dock(channel_id) {
    Some(dock) =>
      self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: true,
        payload: Some(dock.to_json()),
        error: None,
      })
    None =>
      self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: false,
        payload: None,
        error: Some(@protocol.ErrorShape::{
          code: "channel_not_found",
          message: "Channel not found: \{channel_id}",
          details: None,
          retryable: None,
          retry_after_ms: None,
        }),
      })
  }
}

///|
async fn Gateway::handle_channels_configure(
  self : Gateway,
  request : @protocol.Request,
  w : @httpx.ResponseWriter,
) -> Unit {
  let params : Json = match request.params {
    Some(p) => p
    None =>
      return self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: false,
        payload: None,
        error: Some(@protocol.ErrorShape::{
          code: "missing_params",
          message: "Missing configuration parameters",
          details: None,
          retryable: None,
          retry_after_ms: None,
        }),
      })
  }

  let channel_id : String = match params {
    Object({ "channel_id": String(id), .. }) => id
    _ =>
      return self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: false,
        payload: None,
        error: Some(@protocol.ErrorShape::{
          code: "missing_channel_id",
          message: "Missing channel_id in params",
          details: None,
          retryable: None,
          retry_after_ms: None,
        }),
      })
  }

  let config : Json = match params {
    Object({ "config": c, .. }) => c
    _ =>
      return self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: false,
        payload: None,
        error: Some(@protocol.ErrorShape::{
          code: "missing_config",
          message: "Missing config in params",
          details: None,
          retryable: None,
          retry_after_ms: None,
        }),
      })
  }

  let channel_config : @channel.ChannelConfig = @json.from_json(config) catch {
    e =>
      return self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: false,
        payload: None,
        error: Some(@protocol.ErrorShape::{
          code: "invalid_config",
          message: "Invalid config: \{e}",
          details: None,
          retryable: None,
          retry_after_ms: None,
        }),
      })
  }

  match self.channel_manager.configure_channel(channel_id, channel_config) {
    Ok(_) => {
      self.channel_state.save_config(channel_id, channel_config)
      self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: true,
        payload: Some({ "status": "configured", "channel_id": channel_id }),
        error: None,
      })
    }
    Err(e) =>
      self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: false,
        payload: None,
        error: Some(@protocol.ErrorShape::{
          code: "configure_failed",
          message: "Failed to configure channel: \{e.to_string()}",
          details: None,
          retryable: None,
          retry_after_ms: None,
        }),
      })
  }
}

///|
async fn Gateway::handle_channels_start(
  self : Gateway,
  request : @protocol.Request,
  w : @httpx.ResponseWriter,
) -> Unit {
  let params : Json = match request.params {
    Some(p) => p
    None =>
      return self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: false,
        payload: None,
        error: Some(@protocol.ErrorShape::{
          code: "missing_params",
          message: "Missing parameters",
          details: None,
          retryable: None,
          retry_after_ms: None,
        }),
      })
  }

  let channel_id : String = match params {
    Object({ "channel_id": String(id), .. }) => id
    _ =>
      return self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: false,
        payload: None,
        error: Some(@protocol.ErrorShape::{
          code: "missing_channel_id",
          message: "Missing channel_id in params",
          details: None,
          retryable: None,
          retry_after_ms: None,
        }),
      })
  }

  let account_id : String = match params {
    Object({ "account_id": String(id), .. }) => id
    _ =>
      return self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: false,
        payload: None,
        error: Some(@protocol.ErrorShape::{
          code: "missing_account_id",
          message: "Missing account_id in params",
          details: None,
          retryable: None,
          retry_after_ms: None,
        }),
      })
  }

  let config : Json = match params {
    Object({ "config": c, .. }) => c
    _ =>
      return self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: false,
        payload: None,
        error: Some(@protocol.ErrorShape::{
          code: "missing_config",
          message: "Missing config in params",
          details: None,
          retryable: None,
          retry_after_ms: None,
        }),
      })
  }

  match self.channel_manager.start_channel(channel_id, account_id, config) {
    Ok(_) => {
      self.channel_state.save_account_runtime(
        channel_id, account_id, config, true,
      )
      self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: true,
        payload: Some({
          "status": "started",
          "channel_id": channel_id,
          "account_id": account_id,
        }),
        error: None,
      })
    }
    Err(e) =>
      self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: false,
        payload: None,
        error: Some(@protocol.ErrorShape::{
          code: "start_failed",
          message: "Failed to start channel: \{e.to_string()}",
          details: None,
          retryable: None,
          retry_after_ms: None,
        }),
      })
  }
}

///|
async fn Gateway::handle_channels_stop(
  self : Gateway,
  request : @protocol.Request,
  w : @httpx.ResponseWriter,
) -> Unit {
  let params : Json = match request.params {
    Some(p) => p
    None =>
      return self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: false,
        payload: None,
        error: Some(@protocol.ErrorShape::{
          code: "missing_params",
          message: "Missing parameters",
          details: None,
          retryable: None,
          retry_after_ms: None,
        }),
      })
  }

  let channel_id : String = match params {
    Object({ "channel_id": String(id), .. }) => id
    _ =>
      return self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: false,
        payload: None,
        error: Some(@protocol.ErrorShape::{
          code: "missing_channel_id",
          message: "Missing channel_id in params",
          details: None,
          retryable: None,
          retry_after_ms: None,
        }),
      })
  }

  let account_id : String = match params {
    Object({ "account_id": String(id), .. }) => id
    _ =>
      return self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: false,
        payload: None,
        error: Some(@protocol.ErrorShape::{
          code: "missing_account_id",
          message: "Missing account_id in params",
          details: None,
          retryable: None,
          retry_after_ms: None,
        }),
      })
  }

  match self.channel_manager.stop_channel(channel_id, account_id) {
    Ok(_) => {
      self.channel_state.save_account_runtime(channel_id, account_id, {}, false)
      self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: true,
        payload: Some({
          "status": "stopped",
          "channel_id": channel_id,
          "account_id": account_id,
        }),
        error: None,
      })
    }
    Err(e) =>
      self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: false,
        payload: None,
        error: Some(@protocol.ErrorShape::{
          code: "stop_failed",
          message: "Failed to stop channel: \{e.to_string()}",
          details: None,
          retryable: Option::None,
          retry_after_ms: None,
        }),
      })
  }
}

///|
async fn Gateway::handle_configure_channel(
  self : Gateway,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
  channel_id : String,
) -> Unit {
  let body = r.body.read_all().binary()
  let json = match parse_json_body(body) {
    Ok(json) => json
    Err(error) =>
      raise json_error(400, "BadRequest", { "error": error.to_json() })
  }
  let request = match parse_http_channel_configure_params(channel_id, json) {
    Ok(request) => request
    Err(error) =>
      raise json_error(400, "BadRequest", { "error": error.to_json() })
  }
  self.handle_channels_configure(request, w)
}

///|
async fn Gateway::handle_start_channel(
  self : Gateway,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
  channel_id : String,
) -> Unit {
  let body = r.body.read_all().binary()
  let json = match parse_json_body(body) {
    Ok(json) => json
    Err(error) =>
      raise json_error(400, "BadRequest", { "error": error.to_json() })
  }
  let request = match parse_http_channel_start_params(channel_id, json) {
    Ok(request) => request
    Err(error) =>
      raise json_error(400, "BadRequest", { "error": error.to_json() })
  }
  self.handle_channels_start(request, w)
}

///|
async fn Gateway::handle_stop_channel(
  self : Gateway,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
  channel_id : String,
) -> Unit {
  let body = r.body.read_all().binary()
  let json = match parse_json_body(body) {
    Ok(json) => json
    Err(error) =>
      raise json_error(400, "BadRequest", { "error": error.to_json() })
  }
  let request = match parse_http_channel_stop_params(channel_id, json) {
    Ok(request) => request
    Err(error) =>
      raise json_error(400, "BadRequest", { "error": error.to_json() })
  }
  self.handle_channels_stop(request, w)
}
