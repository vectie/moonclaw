///|
pub struct SlashCommand {
  name : String
  description : String
  mut handler : ((TUI, String) -> Unit)?
}

///|
pub fn SlashCommand::new(name : String, description : String) -> SlashCommand {
  SlashCommand::{ name, description, handler: None }
}

///|
pub fn SlashCommand::with_handler(
  self : SlashCommand,
  handler : (TUI, String) -> Unit,
) -> SlashCommand {
  self.handler = Some(handler)
  self
}

///|
pub fn SlashCommand::name(self : SlashCommand) -> String {
  self.name
}

///|
pub fn SlashCommand::description(self : SlashCommand) -> String {
  self.description
}

///|
pub fn SlashCommand::execute(
  self : SlashCommand,
  tui : TUI,
  args : String,
) -> Unit {
  if self.handler is Some(cb) {
    cb(tui, args)
  }
}

///|
pub(all) struct CommandRegistry {
  commands : Map[String, SlashCommand]
}

///|
pub fn CommandRegistry::new() -> CommandRegistry {
  let registry = CommandRegistry::{ commands: {} }
  registry.register_builtin_commands()
  registry
}

///|
fn CommandRegistry::register_builtin_commands(self : CommandRegistry) -> Unit {
  self.register(SlashCommand::new("help", "Show slash command help"))
  self.register(SlashCommand::new("status", "Show current status"))
  self.register(SlashCommand::new("model", "Set or show current model"))
  self.register(SlashCommand::new("agent", "Set or show current agent"))
  self.register(SlashCommand::new("session", "Set or show current session"))
  self.register(SlashCommand::new("new", "Start a new session"))
  self.register(SlashCommand::new("reset", "Reset the current session"))
  self.register(SlashCommand::new("clear", "Clear the chat log"))
  self.register(SlashCommand::new("exit", "Exit the TUI"))
  self.register(SlashCommand::new("quit", "Exit the TUI"))
}

///|
pub fn CommandRegistry::register(
  self : CommandRegistry,
  command : SlashCommand,
) -> Unit {
  self.commands[command.name()] = command
}

///|
pub fn CommandRegistry::get(
  self : CommandRegistry,
  name : String,
) -> SlashCommand? {
  self.commands.get(name)
}

///|
pub fn CommandRegistry::list(self : CommandRegistry) -> Array[SlashCommand] {
  let result : Array[SlashCommand] = []
  for _, cmd in self.commands {
    result.push(cmd)
  }
  result
}

///|
pub fn CommandRegistry::help_text(self : CommandRegistry) -> String {
  let lines : Array[String] = ["Slash commands:"]
  for _, cmd in self.commands {
    lines.push("  /\{cmd.name()} - \{cmd.description()}")
  }
  lines.join("\n")
}

///|
pub fn parse_command(input : String) -> (String, String) {
  let trimmed = input.trim()
  if !trimmed.has_prefix("/") {
    return ("", "")
  }
  let without_slash = trimmed[1:]
  let parts = without_slash.split(" ").collect()
  if parts.length() == 0 {
    return ("", "")
  }
  let name = parts[0].to_string()
  let args = if parts.length() > 1 {
    parts[1:].join(" ").to_string()
  } else {
    ""
  }
  (name, args)
}

///|
pub fn CommandRegistry::execute(
  self : CommandRegistry,
  tui : TUI,
  input : String,
) -> Bool {
  let (name, args) = parse_command(input)
  if name.length() == 0 {
    return false
  }
  match self.commands.get(name) {
    Some(cmd) => {
      cmd.execute(tui, args)
      true
    }
    None => {
      let (width, height) = tui.terminal().size()
      let chat_height = height - 4
      tui.chat_log().add_system("Unknown command: /\{name}", width, chat_height)
      true
    }
  }
}
