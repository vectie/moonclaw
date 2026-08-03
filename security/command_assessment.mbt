///|
pub enum CommandRiskLevel {
  Low
  Medium
  High
  Blocked
} derive(ToJson, @json.FromJson, Show, Eq)

///|
pub enum CommandIntent {
  Binary
  Shell
  PackageManager
  Vcs
  Unknown
} derive(ToJson, @json.FromJson, Show, Eq)

///|
pub struct CommandAssessment {
  command : String
  cwd : String
  workspace : String?
  intent : CommandIntent
  risk_level : CommandRiskLevel
  reasons : Array[String]
  predicted_effects : Array[String]
  requires_approval : Bool
  allowed_by_policy : Bool
} derive(ToJson, @json.FromJson, Show)

///|
fn contains_any(text : String, patterns : Array[String]) -> Bool {
  for pattern in patterns {
    if text.contains(pattern) {
      return true
    }
  }
  false
}

///|
fn first_token(command : String) -> String {
  let trimmed = command.trim()
  if trimmed.is_blank() {
    ""
  } else {
    trimmed.split(" ").collect().get(0).unwrap_or("").trim().to_string()
  }
}

///|
fn classify_intent(command : String) -> CommandIntent {
  let trimmed = command.trim().to_string()
  if trimmed.is_blank() {
    return Unknown
  }
  if contains_any(trimmed, ["&&", "||", ";", "|", ">", ">>", "<", "$(", "`"]) {
    return Shell
  }
  match first_token(trimmed) {
    "git" => Vcs
    "npm"
    | "pnpm"
    | "yarn"
    | "bun"
    | "pip"
    | "pip3"
    | "uv"
    | "cargo"
    | "go"
    | "brew"
    | "apt"
    | "apt-get" => PackageManager
    "" => Unknown
    _ => Binary
  }
}

///|
fn detect_reasons(command : String) -> Array[String] {
  let normalized = command.trim().to_string().to_lower()
  let reasons = []
  if normalized.is_blank() {
    reasons.push("Empty command.")
    return reasons
  }
  if contains_any(normalized, ["sudo ", " doas "]) ||
    normalized.has_prefix("sudo ") {
    reasons.push("Privilege escalation requested.")
  }
  if contains_any(normalized, [
      "rm -rf /", "rm -fr /", "mkfs", "shutdown", "reboot",
    ]) {
    reasons.push("Host-destructive command pattern detected.")
  }
  if contains_any(normalized, [
      "rm ", "mv ", "cp ", "touch ", "mkdir ", "rmdir ", "tee ", "sed -i", "chmod ",
      "chown ",
    ]) ||
    contains_any(normalized, [" >", ">>"]) {
    reasons.push("Command may modify files.")
  }
  if contains_any(normalized, [
      "curl ", "wget ", "npm install", "pnpm add", "yarn add", "pip install", "uv pip install",
      "cargo add", "go get", "brew install", "apt install", "apt-get install",
    ]) {
    reasons.push("Command may fetch code or packages from the network.")
  }
  if contains_any(normalized, ["&&", "||", ";", "|", "$(", "`"]) {
    reasons.push("Shell composition or expansion detected.")
  }
  if reasons.is_empty() {
    reasons.push("Command appears read-only.")
  }
  reasons
}

///|
fn detect_effects(command : String) -> Array[String] {
  let normalized = command.trim().to_string().to_lower()
  let effects = []
  if contains_any(normalized, [
      "curl ", "wget ", "npm install", "pnpm add", "yarn add", "pip install", "uv pip install",
      "cargo add", "go get", "brew install", "apt install", "apt-get install",
    ]) {
    effects.push("network")
  }
  if contains_any(normalized, [
      "rm ", "mv ", "cp ", "touch ", "mkdir ", "rmdir ", "tee ", "sed -i", "chmod ",
      "chown ",
    ]) ||
    contains_any(normalized, [" >", ">>"]) {
    effects.push("write-files")
  }
  if contains_any(normalized, ["&&", "||", ";", "|", "$(", "`"]) {
    effects.push("shell-expansion")
    effects.push("process-fan-out")
  }
  if effects.is_empty() {
    effects.push("read-files")
  }
  effects
}

///|
fn classify_risk(command : String, reasons : Array[String]) -> CommandRiskLevel {
  let normalized = command.trim().to_string().to_lower()
  if normalized.is_blank() {
    return Blocked
  }
  if reasons.contains("Privilege escalation requested.") ||
    reasons.contains("Host-destructive command pattern detected.") {
    return Blocked
  }
  if reasons.contains("Command may modify files.") {
    return High
  }
  if reasons.contains("Command may fetch code or packages from the network.") ||
    reasons.contains("Shell composition or expansion detected.") {
    return Medium
  }
  Low
}

///|
pub fn assess_shell_command(
  command : String,
  cwd : String,
  workspace : String?,
) -> CommandAssessment {
  let reasons = detect_reasons(command)
  let risk_level = classify_risk(command, reasons)
  CommandAssessment::{
    command: command.trim().to_string(),
    cwd,
    workspace,
    intent: classify_intent(command),
    risk_level,
    reasons,
    predicted_effects: detect_effects(command),
    requires_approval: risk_level == High,
    allowed_by_policy: risk_level != Blocked,
  }
}
