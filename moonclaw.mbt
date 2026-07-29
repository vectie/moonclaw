///|
/// moonclaw is the main AI coding agent that provides intelligent assistance
/// for software development tasks. It integrates various tools for file management,
/// command execution, and code analysis.
pub struct Moonclaw {
  logger : @pino.Logger
  agent : @agent.Agent
}

///|
fn setup_agent(
  agent : @agent.Agent,
  cwd~ : String,
  restricted_workspace~ : Bool,
  web_search~ : Bool,
) -> Unit {
  let file_manager = @file.manager(cwd~)
  let todo_list = @todo.new(uuid=agent.uuid, cwd=agent.cwd)
  if restricted_workspace {
    // Flow capsules deliberately omit shell, search, OCR, and patch tools.
    // Their only filesystem capabilities are scoped reads/listing and a
    // traversal-rejecting writer rooted at the task capsule.
    agent.add_tools([
      @list_files.new(file_manager).to_agent_tool(),
      @read_file.new(file_manager).to_agent_tool(),
      @write_to_file.new(agent.cwd).to_agent_tool(),
    ])
    if web_search {
      agent.add_tools([
        @web_search.new().to_agent_tool(),
        @web_fetch.new().to_agent_tool(),
      ])
    }
  } else {
    agent.add_tools([
      @execute_command.new(agent.cwd).to_agent_tool(),
      @list_files.new(file_manager).to_agent_tool(),
      @read_file.new(file_manager).to_agent_tool(),
      @todo.new_tool(todo_list).to_agent_tool(),
      @search_files.new(agent.cwd).to_agent_tool(),
      @unlimited_ocr.new(agent.cwd).to_agent_tool(),
    ])
    // GPT 5.1+ uses apply_patch only, other models use meta_write_to_file
    if agent.model.supports_apply_patch {
      agent.add_tool(@apply_patch.new(agent.cwd))
    } else {
      agent.add_tool(@write_to_file.new(agent.cwd))
    }
  }
}

///|
/// Gives an agent bounded, read-only workspace discovery. This is intended for
/// retained Q&A and other Cowork sessions that must inspect durable artifacts
/// without acquiring shell or workspace-mutation authority.
pub fn setup_read_only_agent(agent : @agent.Agent, cwd~ : String) -> Unit {
  let file_manager = @file.manager(cwd~)
  agent.add_tools([
    @list_files.new(file_manager).to_agent_tool(),
    @read_file.new(file_manager).to_agent_tool(),
    @search_files.new(cwd).to_agent_tool(),
  ])
}

///|
fn default_log_path() -> String {
  @moonsuite.product_artifact_for_workspace_root(
    @os.home() catch {
      _ => "."
    },
    "moonclaw",
    "logs/moonclaw.jsonl",
  )
}

///|
/// Creates a new moonclaw agent instance.
///
/// Parameters:
/// - logger: Optional logger for recording agent activities (defaults to file-based logger)
/// - model: The AI model to use for the agent
/// - cwd: Optional working directory (defaults to current working directory)
/// - user_message: Optional initial user message to start the conversation
/// - web_search: Whether to enable web search capabilities (defaults to false)
///
/// Returns a configured moonclaw instance ready to assist with coding tasks.
#as_free_fn
pub async fn Moonclaw::new(
  name? : String,
  logger? : @pino.Logger = @pino.logger(
    "moonclaw",
    try! @pino.Transport::parse("file:\{default_log_path()}"),
  ),
  model~ : @model.Model,
  home? : String,
  cwd? : String,
  user_message? : String,
  web_search? : Bool = false,
  restricted_workspace? : Bool = false,
) -> Moonclaw {
  let cwd = match cwd {
    Some(cwd) => cwd
    None => @os.cwd()
  }
  let system_prompt = [@prompt.prelude, @todo.prompt, @search_files.prompt].join(
    "\n",
  )
  let agent = @agent.new(
    name?,
    model,
    logger~,
    home?=home.map(home => home),
    cwd~,
    system_message=system_prompt,
    user_message?,
    web_search~,
  )
  setup_agent(agent, cwd~, restricted_workspace~, web_search~)
  { logger, agent }
}

///|
/// Closes the moonclaw agent and releases associated resources.
/// Should be called when the agent is no longer needed (using `defer` ideally).
pub fn Moonclaw::close(self : Moonclaw) -> Unit {
  self.agent.close()
}

///|
/// Starts the moonclaw agent and begins processing tasks.
///
/// Parameters:
///
/// - prompt: Optional initial prompt to send to the agent before starting
///
/// The agent will process messages from its queue and respond to user requests,
/// and stops when there are no more messages to process.
pub async fn Moonclaw::start(self : Moonclaw, prompt? : String) -> Unit {
  if prompt is Some(prompt) {
    let user_message = @ai.user_message(content=prompt)
    self.agent.queue_message(user_message) |> ignore()
  }
  self.agent.start()
}

///|
/// Resumes a previously saved moonclaw agent session.
///
/// Parameters:
/// - logger: Optional logger for recording agent activities (defaults to file-based logger)
/// - model: The AI model to use for the agent
/// - cwd: Optional working directory (defaults to current working directory)
/// - id: The unique identifier of the conversation to resume
/// - user_message: Optional user message to add to the resumed conversation
/// - web_search: Whether to enable web search capabilities (defaults to false)
///
/// Returns a moonclaw instance with the conversation history restored.
/// Fails if the conversation with the given id cannot be found.
#as_free_fn
pub async fn Moonclaw::resume_(
  logger? : @pino.Logger = @pino.logger(
    "moonclaw",
    try! @pino.Transport::parse("file:\{default_log_path()}"),
  ),
  model~ : @model.Model,
  home? : String,
  id : @uuid.Uuid,
  user_message? : String,
  web_search? : Bool,
) -> Moonclaw {
  let home = match home {
    Some(home) => home
    None => @os.home()
  }
  let uuid = @uuid.generator(@rand.chacha8())
  let session_manager = @conversation.Manager::new(home~, uuid~)
  guard session_manager.load(id) is Some(conversation) else {
    fail("Conversation with id '\{id}' not found.")
  }
  // Use the conversation's web_search setting if not explicitly overridden.
  let web_search = web_search.unwrap_or(conversation.web_search())
  let agent = @agent.load(
    model,
    conversation,
    logger~,
    home~,
    user_message?,
    web_search~,
  )
  setup_agent(
    agent,
    cwd=conversation.cwd(),
    restricted_workspace=false,
    web_search~,
  )
  { logger, agent }
}
