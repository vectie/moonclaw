///|
pub enum MessageComponent {
  UserMsg(UserMessage)
  AssistantMsg(AssistantMessage)
  SystemMsg(SystemMessage)
  ToolExec(ToolExecution)
  SpacerComp(Spacer)
}

///|
pub fn MessageComponent::get_preferred_height(
  self : MessageComponent,
  width : Int,
) -> Int {
  match self {
    UserMsg(m) => m.get_preferred_height(width)
    AssistantMsg(m) => m.get_preferred_height(width)
    SystemMsg(m) => m.get_preferred_height(width)
    ToolExec(t) => t.get_preferred_height(width)
    SpacerComp(s) => s.get_preferred_height(width)
  }
}

///|
pub fn MessageComponent::render(
  self : MessageComponent,
  output : RenderOutput,
  x : Int,
  y : Int,
  width : Int,
  height : Int,
) -> Unit {
  match self {
    UserMsg(m) => m.render(output, x, y, width, height)
    AssistantMsg(m) => m.render(output, x, y, width, height)
    SystemMsg(m) => m.render(output, x, y, width, height)
    ToolExec(t) => t.render(output, x, y, width, height)
    SpacerComp(s) => s.render(output, x, y, width, height)
  }
}

///|
pub(all) struct ChatLog {
  mut components : Array[MessageComponent]
  mut tool_by_id : Map[String, Int]
  mut streaming_by_id : Map[String, Int]
  mut tools_expanded : Bool
  mut follow_output : Bool
  mut scroll_offset : Int // Line offset, not component index
  max_components : Int
}

///|
pub fn ChatLog::new() -> ChatLog {
  ChatLog::{
    components: [],
    tool_by_id: {},
    streaming_by_id: {},
    tools_expanded: false,
    follow_output: true,
    scroll_offset: 0,
    max_components: 180,
  }
}

///|
pub fn ChatLog::with_max_components(max : Int) -> ChatLog {
  ChatLog::{
    components: [],
    tool_by_id: {},
    streaming_by_id: {},
    tools_expanded: false,
    follow_output: true,
    scroll_offset: 0,
    max_components: max.max(20),
  }
}

///|
fn ChatLog::prune_overflow(self : ChatLog) -> Unit {
  while self.components.length() > self.max_components {
    ignore(self.components.remove(0))
    let new_tool_by_id : Map[String, Int] = {}
    let new_streaming_by_id : Map[String, Int] = {}
    for id, idx in self.tool_by_id {
      if idx > 0 {
        new_tool_by_id[id] = idx - 1
      }
    }
    for id, idx in self.streaming_by_id {
      if idx > 0 {
        new_streaming_by_id[id] = idx - 1
      }
    }
    self.tool_by_id = new_tool_by_id
    self.streaming_by_id = new_streaming_by_id
  }
}

///|
fn ChatLog::append(self : ChatLog, component : MessageComponent) -> Unit {
  self.components.push(component)
  self.prune_overflow()
  // scroll_to_bottom will be called by the caller with proper dimensions
}

///|
pub fn ChatLog::clear_all(self : ChatLog) -> Unit {
  self.components.clear()
  self.tool_by_id.clear()
  self.streaming_by_id.clear()
  self.follow_output = true
  self.scroll_offset = 0
}

///|
pub fn ChatLog::add_user(
  self : ChatLog,
  text : String,
  width : Int,
  viewport_height : Int,
) -> Unit {
  self.append(SpacerComp(Spacer::new(height=1)))
  self.append(UserMsg(UserMessage::new(text)))
  self.scroll_to_bottom(width, viewport_height)
}

///|
pub fn ChatLog::add_system(
  self : ChatLog,
  text : String,
  width : Int,
  viewport_height : Int,
) -> Unit {
  self.append(SpacerComp(Spacer::new(height=1)))
  self.append(SystemMsg(SystemMessage::new(text)))
  self.scroll_to_bottom(width, viewport_height)
}

///|
pub fn ChatLog::start_assistant(
  self : ChatLog,
  text : String,
  run_id? : String = "default",
) -> AssistantMessage {
  let component = AssistantMessage::new(text)
  component.set_streaming(true)
  let idx = self.components.length()
  self.streaming_by_id[run_id] = idx
  self.append(AssistantMsg(component))
  component
}

///|
pub fn ChatLog::update_assistant(
  self : ChatLog,
  text : String,
  run_id? : String = "default",
) -> Unit {
  match self.streaming_by_id.get(run_id) {
    Some(i) =>
      if i >= 0 && i < self.components.length() {
        match self.components[i] {
          AssistantMsg(m) => {
            m.set_text(text)
            return
          }
          _ => ()
        }
      }
    None => ()
  }
  // No streaming message found, create a new one
  ignore(self.start_assistant(text, run_id~))
}

///|
pub fn ChatLog::finalize_assistant(
  self : ChatLog,
  text : String,
  run_id? : String = "default",
) -> Unit {
  match self.streaming_by_id.get(run_id) {
    Some(i) =>
      if i >= 0 && i < self.components.length() {
        match self.components[i] {
          AssistantMsg(m) => {
            m.set_text(text)
            m.set_streaming(false)
          }
          _ => ()
        }
        self.streaming_by_id.remove(run_id) |> ignore()
      }
    None => self.append(AssistantMsg(AssistantMessage::new(text)))
  }
}

///|
pub fn ChatLog::finalize_current_assistant(
  self : ChatLog,
  run_id? : String = "default",
) -> Unit {
  match self.streaming_by_id.get(run_id) {
    Some(i) =>
      if i >= 0 && i < self.components.length() {
        match self.components[i] {
          AssistantMsg(m) => m.set_streaming(false)
          _ => ()
        }
        self.streaming_by_id.remove(run_id) |> ignore()
      }
    None => ()
  }
}

///|
pub fn ChatLog::drop_assistant(
  self : ChatLog,
  run_id? : String = "default",
) -> Unit {
  match self.streaming_by_id.get(run_id) {
    Some(i) =>
      if i >= 0 && i < self.components.length() {
        ignore(self.components.remove(i))
        self.streaming_by_id.remove(run_id) |> ignore()
        let new_streaming_by_id : Map[String, Int] = {}
        for id, idx in self.streaming_by_id {
          if idx > i {
            new_streaming_by_id[id] = idx - 1
          } else {
            new_streaming_by_id[id] = idx
          }
        }
        self.streaming_by_id = new_streaming_by_id
      }
    None => ()
  }
}

///|
pub fn ChatLog::start_tool(
  self : ChatLog,
  tool_call_id : String,
  tool_name : String,
  args : String,
) -> ToolExecution {
  match self.tool_by_id.get(tool_call_id) {
    Some(i) =>
      if i >= 0 && i < self.components.length() {
        match self.components[i] {
          ToolExec(t) => {
            t.set_args(args)
            return t
          }
          _ => ()
        }
      }
    None => ()
  }
  let component = ToolExecution::new(tool_name, args)
  component.set_status(ToolStatus::Running)
  component.set_expanded(self.tools_expanded)
  let idx = self.components.length()
  self.tool_by_id[tool_call_id] = idx
  self.append(ToolExec(component))
  component
}

///|
pub fn ChatLog::update_tool_args(
  self : ChatLog,
  tool_call_id : String,
  args : String,
) -> Unit {
  match self.tool_by_id.get(tool_call_id) {
    Some(i) =>
      if i >= 0 && i < self.components.length() {
        match self.components[i] {
          ToolExec(t) => t.set_args(args)
          _ => ()
        }
      }
    None => ()
  }
}

///|
pub fn ChatLog::update_tool_result(
  self : ChatLog,
  tool_call_id : String,
  result : String,
  is_error? : Bool = false,
) -> Unit {
  match self.tool_by_id.get(tool_call_id) {
    Some(i) =>
      if i >= 0 && i < self.components.length() {
        match self.components[i] {
          ToolExec(t) => t.set_result(result, is_error~)
          _ => ()
        }
      }
    None => ()
  }
}

///|
pub fn ChatLog::set_tools_expanded(self : ChatLog, expanded : Bool) -> Unit {
  self.tools_expanded = expanded
  for component in self.components {
    match component {
      ToolExec(t) => t.set_expanded(expanded)
      _ => ()
    }
  }
}

///|
pub fn ChatLog::scroll_to_bottom(
  self : ChatLog,
  width : Int,
  viewport_height : Int,
) -> Unit {
  // Calculate total rendered height and scroll to show bottom
  let total_height = self.get_preferred_height(width)
  if total_height > viewport_height {
    self.scroll_offset = total_height - viewport_height
  } else {
    self.scroll_offset = 0
  }
  self.follow_output = true
}

///|
pub fn ChatLog::scroll_up(self : ChatLog, lines : Int) -> Unit {
  self.scroll_offset = (self.scroll_offset - lines).max(0)
  self.follow_output = false
}

///|
pub fn ChatLog::scroll_down(
  self : ChatLog,
  lines : Int,
  width : Int,
  viewport_height : Int,
) -> Unit {
  let total_height = self.get_preferred_height(width)
  let max_scroll = (total_height - viewport_height).max(0)
  self.scroll_offset = (self.scroll_offset + lines).min(max_scroll)
  self.follow_output = self.scroll_offset >= max_scroll
}

///|
pub fn ChatLog::maybe_scroll_to_bottom(
  self : ChatLog,
  width : Int,
  viewport_height : Int,
) -> Unit {
  if self.follow_output {
    self.scroll_to_bottom(width, viewport_height)
  }
}

///|
pub fn ChatLog::normalize_scroll(
  self : ChatLog,
  width : Int,
  viewport_height : Int,
) -> Unit {
  let max_scroll = (self.get_preferred_height(width) - viewport_height).max(0)
  if self.follow_output {
    self.scroll_offset = max_scroll
  } else {
    self.scroll_offset = self.scroll_offset.min(max_scroll)
  }
}

///|
pub fn ChatLog::get_preferred_height(self : ChatLog, width : Int) -> Int {
  let mut total = 0
  for component in self.components {
    total += component.get_preferred_height(width)
  }
  total
}

///|
pub fn ChatLog::render(
  self : ChatLog,
  output : RenderOutput,
  x : Int,
  y : Int,
  width : Int,
  height : Int,
) -> Unit {
  let mut current_y = y
  let mut lines_rendered = 0

  // Skip lines based on scroll_offset
  for component in self.components {
    let comp_height = component.get_preferred_height(width)
    let skip_lines = self.scroll_offset - lines_rendered

    if skip_lines >= comp_height {
      // Skip this entire component
      lines_rendered += comp_height
    } else if skip_lines > 0 {
      // Skip partial component
      let remaining_height = comp_height - skip_lines
      if current_y < y + height {
        let available_height = (y + height - current_y).min(remaining_height)
        component.render(output, x, current_y, width, available_height)
        current_y += remaining_height
        lines_rendered += comp_height
      }
      // Render full component
    } else if current_y < y + height {
      let available_height = (y + height - current_y).min(comp_height)
      component.render(output, x, current_y, width, available_height)
      current_y += comp_height
      lines_rendered += comp_height
    }

    if lines_rendered > self.scroll_offset + height {
      break
    }
  }
}

///|
fn render_component_lines(
  component : MessageComponent,
  width : Int,
) -> Array[String] {
  let theme = Theme::default()
  match component {
    UserMsg(m) => {
      let lines = [theme.user_style(" You ")]
      let inner_width = (width - 4).max(1)
      for line in wrap_text(m.text(), inner_width) {
        lines.push("  \{theme.text_style(line)}")
      }
      lines.push("")
      lines
    }
    AssistantMsg(m) => {
      let assistant_title = theme.accent_style(" Assistant")
      let streaming_suffix = theme.dim_style(" (streaming...)")
      let header = if m.is_streaming() {
        "\{assistant_title}\{streaming_suffix}"
      } else {
        assistant_title
      }
      let lines : Array[String] = [header]
      let inner_width = (width - 2).max(1)
      for line in wrap_text(m.text(), inner_width) {
        lines.push(" \{theme.text_style(line)}")
      }
      if lines.length() < 2 {
        lines.push("")
      }
      lines
    }
    SystemMsg(m) => {
      let text_lines = m
        .text()
        .split("\n")
        .map(fn(v) { v.to_string() })
        .collect()
      let system_prefix = theme.system(" System: ")
      let lines : Array[String] = []
      if text_lines.length() == 0 {
        lines.push(system_prefix)
        return lines
      }
      lines.push("\{system_prefix}\{theme.dim_style(text_lines[0])}")
      for i in 1..<text_lines.length() {
        lines.push(theme.dim_style(text_lines[i]))
      }
      lines
    }
    ToolExec(t) => {
      let status_icon = match t.status() {
        Pending => theme.dim_style("○")
        Running => theme.accent_style("◐")
        Success => theme.success_style("●")
        Error => theme.error_style("✗")
      }
      let expand_hint = if t.expanded() { " [collapse]" } else { " [expand]" }
      let lines : Array[String] = [
        "\{status_icon} \{theme.tool_title_style(t.tool_name())}\{theme.dim_style(expand_hint)}",
      ]
      if !t.expanded() {
        let preview = truncate_to_width(t.args(), (width - 20).max(1))
        if preview.length() > 0 {
          lines[0] = "\{lines[0]} \{theme.dim_style(preview)}"
        }
        return lines
      }
      lines.push(theme.dim_style("  Args:"))
      let inner_width = (width - 4).max(1)
      for line in t.args().split("\n") {
        for wrapped in wrap_text(line.to_string(), inner_width) {
          lines.push("  \{theme.tool_output_style(wrapped)}")
        }
      }
      if t.result().length() > 0 {
        lines.push(theme.dim_style("  Result:"))
        let is_error = match t.status() {
          Error => true
          _ => false
        }
        for line in t.result().split("\n") {
          for wrapped in wrap_text(line.to_string(), inner_width) {
            let styled = if is_error {
              theme.error_style(wrapped)
            } else {
              theme.tool_output_style(wrapped)
            }
            lines.push("  \{styled}")
          }
        }
      }
      lines
    }
    SpacerComp(s) => {
      let lines : Array[String] = []
      for _ in 0..<s.get_preferred_height(width) {
        lines.push("")
      }
      lines
    }
  }
}

///|
pub fn ChatLog::visible_lines(
  self : ChatLog,
  width : Int,
  height : Int,
) -> Array[String] {
  let visible : Array[String] = []
  let mut consumed = 0
  for component in self.components {
    let lines = render_component_lines(component, width)
    let next_consumed = consumed + lines.length()
    if next_consumed <= self.scroll_offset {
      consumed = next_consumed
      continue
    }
    let start = (self.scroll_offset - consumed).max(0)
    for i in start..<lines.length() {
      if visible.length() >= height {
        return visible
      }
      visible.push(lines[i])
    }
    consumed = next_consumed
    if visible.length() >= height {
      return visible
    }
  }
  while visible.length() < height {
    visible.push("")
  }
  visible
}
