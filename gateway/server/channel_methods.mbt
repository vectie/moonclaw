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

  let channel_id : String = match @json.from_json(params) {
    Ok(id) => id
    Err(e) =>
      return self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: false,
        payload: None,
        error: Some(@protocol.ErrorShape::{
          code: "invalid_params",
          message: "Invalid channel_id: \{e}",
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
    Ok(_) =>
      self.send_response(w, @protocol.Response::{
        id: request.id,
        ok: true,
        payload: Some({ "status": "configured", "channel_id": channel_id }),
        error: None,
      })
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
    Ok(_) =>
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
    Ok(_) =>
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
