///|
pub async fn Gateway::new(
  uuid? : @uuid.Generator,
  port? : Int = @protocol.DEFAULT_PORT,
  cwd? : StringView,
  home? : StringView,
  auth? : AuthConfig,
) -> Gateway {
  let home = match home {
    None => @path.Path(@os.home()).join(@path.Path(".moonclaw")).to_string()
    Some(home) => home.to_string()
  }
  let cwd = match cwd {
    Some(cwd) => cwd.to_string()
    None => @os.cwd()
  }
  let uuid = match uuid {
    Some(uuid) => uuid
    None => @uuid.generator(@rand.chacha8())
  }
  let httpx_server = @httpx.Server::new("[::1]", port, reuse_addr=true)
  let actual_port = httpx_server.port()
  let gateway_dir = @path.Path(home).join(@path.Path("gateway")).to_string()
  let session_dir = @path.Path(gateway_dir)
    .join(@path.Path("sessions"))
    .to_string()
  let channel_state_file = @path.Path(gateway_dir)
    .join(@path.Path("channels.json"))
    .to_string()
  let jobs_dir = @path.Path(home).join(@path.Path("jobs")).to_string()
  @fsx.make_directory(session_dir, recursive=true) catch {
    _ => ()
  }
  let auth = match auth {
    Some(auth) => auth
    None => {
      let token_file = @path.Path(gateway_dir)
        .join(@path.Path("token"))
        .to_string()
      let token_result : Result[String, Error] = try? @fsx.read_file(token_file)
      let token = match token_result {
        Ok(content) => Some(content.trim().to_string())
        Err(_) => {
          let new_token = generate_token(uuid~)
          @fsx.make_directory(gateway_dir, recursive=true) catch {
            _ => ()
          }
          @fsx.write_to_file(token_file, new_token)
          Some(new_token)
        }
      }
      AuthConfig::{ token, _password: None }
    }
  }
  let channel_manager = ChannelManager::new(
    @pino.logger("channel_manager", @pino.Transport::console()),
  )
  let extension_registry = @channel.ExtensionRegistry::new()
  let extension_websocket_runtime_manager = @channel.WebSocketClientRuntimeManager::new()
  let extension_websocket_runtime = extension_websocket_runtime_manager.controller()
  let security_runtime = @security.SecurityRuntime::new(home~, cwd~)
  let workspace_runtime = @workspace.WorkspaceRuntime::new(home~, cwd~)
  let plugin_runtime = @plugin.PluginRuntime::new(home~, cwd~)
  let acp_runtime = @acp.AcpRuntime::new(home~, cwd~)
  let acp_process_manager = @spawn.Manager::new(cwd~)
  let job_app = @job.GatewayJobApp::new(
    root=jobs_dir,
    cwd~,
    home~,
    workspace=workspace_runtime,
    next_id=fn() { uuid.v4().to_string() },
    now=current_time_ms,
  )
  let gateway = Gateway::{
    clock: @clock.epoch,
    uuid,
    httpx: httpx_server,
    port: actual_port,
    events: @broadcast.Broadcast::new(),
    auth,
    sessions: SessionManager::{ sessions: {}, session_dir },
    dedupe: DedupeCache::{ entries: {}, ttl_ms: 60000 },
    logger: @pino.logger("gateway", @pino.Transport::console()),
    home,
    cwd,
    models: @model.Loader::new(home~, cwd~),
    started_at: 0,
    pending_requests: 0,
    agent_runs: {},
    active_channel_sessions: {},
    shutdown_requested: false,
    agent_events: @broadcast.Broadcast::new(),
    channel_manager,
    extension_registry,
    extension_websocket_runtime_manager,
    extension_websocket_runtime,
    mailbox_manager: mailbox_manager(),
    coordinator: coordinator(uuid~),
    pipeline_manager: pipeline_manager(uuid~),
    channel_state: ChannelStateStore::{ path: channel_state_file, states: {} },
    job_app,
    security_runtime,
    workspace_runtime,
    plugin_runtime,
    acp_runtime,
    acp_process_manager,
    active_acp_runs: {},
    active_acp_output: {},
    cancelled_acp_runs: {},
  }
  gateway.sessions.load() catch {
    error => gateway.logger.warn("Failed to load gateway sessions: \{error}")
  }
  gateway.channel_state.load() catch {
    error => gateway.logger.warn("Failed to load channel state: \{error}")
  }
  gateway.job_app.load() catch {
    error => gateway.logger.warn("Failed to load job runtime state: \{error}")
  }
  gateway.security_runtime.load() catch {
    error => gateway.logger.warn("Failed to load security runtime: \{error}")
  }
  gateway.workspace_runtime.load() catch {
    error => gateway.logger.warn("Failed to load workspace runtime: \{error}")
  }
  gateway.plugin_runtime.load() catch {
    error => gateway.logger.warn("Failed to load plugin runtime: \{error}")
  }
  gateway.acp_runtime.load() catch {
    error => gateway.logger.warn("Failed to load ACP runtime: \{error}")
  }
  gateway.seed_channel_state_from_moonclaw_config() catch {
    error =>
      gateway.logger.warn(
        "Failed to seed channel state from .moonclaw/moonclaw.json: \{error}",
      )
  }
  let feishu_channel = @feishu.FeishuChannel::new()
  let handler : &@channel.MessageHandler = gateway
  feishu_channel.set_message_handler(handler)
  feishu_channel.with_extension(extension => {
    gateway.register_extension(extension)
  }) catch {
    error =>
      gateway.logger.warn("Failed to register Feishu extension: \{error}")
  }
  let weixin_channel = @weixin.WeixinChannel::new()
  weixin_channel.set_message_handler(handler)
  weixin_channel.with_extension(extension => {
    gateway.register_extension(extension)
  }) catch {
    error =>
      gateway.logger.warn("Failed to register Weixin extension: \{error}")
  }
  gateway.restore_channel_runtime() catch {
    error => gateway.logger.warn("Failed to restore channel runtime: \{error}")
  }
  gateway
}

///|
pub fn Gateway::port(self : Gateway) -> Int {
  self.port
}

///|
pub fn Gateway::auth_token(self : Gateway) -> String? {
  self.auth.token
}

///|
pub fn Gateway::register_extension(
  self : Gateway,
  extension : &@channel.ChannelExtension,
) -> Unit raise {
  let context = @channel.ExtensionContext::new(
    gateway_url="http://localhost:\{self.port}",
    gateway_token=self.auth.token,
    home_dir=self.home,
    cwd=self.cwd,
    logger=Some(
      @channel.LoggerFuncs::new(
        info=message => println("[gateway][info] \{message}"),
        warn=message => println("[gateway][warn] \{message}"),
        error=message => println("[gateway][error] \{message}"),
        debug=message => println("[gateway][debug] \{message}"),
      ),
    ),
    websocket_connector=Some(gateway_websocket_connector()),
    websocket_runtime=Some(self.extension_websocket_runtime),
  )
  self.extension_registry.register_with_context(extension, context)
  self.channel_manager.register_channel(extension)
}

///|
pub fn Gateway::unregister_extension(
  self : Gateway,
  channel_id : String,
) -> Unit {
  self.extension_registry.unregister(channel_id)
}

///|
fn generate_token(uuid~ : @uuid.Generator) -> String raise {
  ignore(uuid)
  let random_bytes = @rand.bytes(32)
  @base64.encode(random_bytes)
}

///|
pub async fn Gateway::start(self : Gateway) -> Unit {
  self.started_at = current_time_ms()
  self.logger.info("Gateway server starting on port \{self.port}")
  self.logger.info("Visit http://localhost:\{self.port}/")
  if self.auth.token is Some(token) {
    self.logger.info("Auth token: \{token}")
  }
  @async.with_task_group(group => {
    gateway_root_groups[self.port] = group
    self.resume_pending_job_runs() catch {
      error => self.logger.warn("Failed to resume pending job runs: \{error}")
    }
    let session = self.events.spawn_in(group)
    let agent_session = self.agent_events.spawn_in(group)
    group.spawn_bg(() => self.run_tick_interval())
    group.spawn_bg(
      () => self.extension_websocket_runtime_manager.start(),
      no_wait=true,
      allow_failure=true,
    )
    group.spawn_bg(
      () => self.acp_process_manager.start(),
      no_wait=true,
      allow_failure=true,
    )
    group.spawn_bg(() => {
      self.httpx.serve(@httpx.cors((r, w) => self.handle_request(r, w)))
    })
    group.spawn_bg(() => {
      self.events.listen_forever(include_history=false, event => {
        match event {
          Tick => {
            let _ = self.schedule_due_jobs() catch {
              error => {
                self.logger.warn("Failed to schedule due jobs: \{error}")
                []
              }
            }
            self.maybe_notify_active_jobs() catch {
              error =>
                self.logger.warn(
                  "Failed to send job status notifications: \{error}",
                )
            }
          }
          Shutdown => {
            self.logger.info("Shutdown requested, stopping gateway...")
            self.extension_websocket_runtime.stop_all()
            self.httpx.close()
            session.stop()
            agent_session.stop()
            group.return_immediately(())
          }
        }
      })
    })
  })
  gateway_root_groups.remove(self.port) |> ignore()
}

///|
async fn Gateway::run_tick_interval(self : Gateway) -> Unit {
  let tick_interval_ms = @protocol.TICK_INTERVAL_MS
  for ;; {
    @async.sleep(tick_interval_ms)
    self.events.put(GatewayEvent::Tick)
    self.dedupe.clear_expired(current_time_ms())
  }
}

///|
pub fn current_time_ms() -> Int {
  let ts = @clock.epoch.now()
  ts.ms().to_int()
}
