///|
pub(all) struct TUI {
  terminal : Terminal
  mut chat_log : ChatLog
  mut editor : Editor
  mut status_loader : Loader
  mut status_text : Text
  mut header : Text
  mut footer : Text
  mut state : TuiState
  mut running : Bool
  mut on_submit : ((String) -> Unit)?
  mut on_command : ((String) -> Unit)?
  mut on_escape : (() -> Unit)?
  mut on_ctrl_c : (() -> Unit)?
  mut on_ctrl_d : (() -> Unit)?
  mut on_ctrl_o : (() -> Unit)?
  mut render_needed : Bool
  mut last_render_at : Int64
  mut last_width : Int
  mut last_height : Int
  mut needs_full_redraw : Bool
  mut last_body_frame : String
  mut last_editor_line : String
  mut last_cursor_col : Int
  mut last_cursor_row : Int
}

///|
const EditorRenderIntervalMs : Int64 = 16L

///|
const BodyRenderIntervalMs : Int64 = 90L

///|
fn spaces(count : Int) -> String {
  let mut result = ""
  for _ in 0..<count.max(0) {
    result = "\{result} "
  }
  result
}

///|
fn frame_line(text : String, width : Int) -> String {
  let truncated = truncate_styled(text, width.max(0))
  "\{truncated}\{spaces((width.max(0) - visible_width(truncated)).max(0))}"
}

///|
fn editor_frame_line(editor : Editor, width : Int) -> (String, Int) {
  let prompt_text = editor.prompt_text()
  let prompt = colorize(prompt_text, Color::BrightGreen)
  let display_text = if editor.text().length() == 0 {
    dim(editor.placeholder_text())
  } else {
    editor.text()
  }
  let prompt_width = @unicode/width.string(prompt_text)
  let available_width = (width - prompt_width).max(0)
  let visible_text = truncate_styled(display_text, available_width)
  let line = "\{prompt}\{visible_text}"
  let cursor_col = (prompt_width +
  @unicode/width.string(editor.text()[:editor.cursor()]).min(available_width)).min(
    width.max(0),
  )
  (frame_line(line, width), cursor_col)
}

///|
fn write_repainted_lines(
  output : RenderOutput,
  start_row : Int,
  lines : Array[String],
) -> Unit {
  for i in 0..<lines.length() {
    output.write(cursor_to(0, start_row + i))
    output.write(ClearLineRight)
    output.write(lines[i])
  }
}

///|
fn write_changed_lines(
  output : RenderOutput,
  start_row : Int,
  current_lines : Array[String],
  previous_lines : Array[String],
) -> Unit {
  let line_count = current_lines.length().max(previous_lines.length())
  for i in 0..<line_count {
    let current = current_lines.get(i).unwrap_or("")
    let previous = previous_lines.get(i).unwrap_or("")
    if current != previous {
      output.write(cursor_to(0, start_row + i))
      output.write(ClearLineRight)
      output.write(current)
    }
  }
}

///|
fn TUI::build_frame(
  self : TUI,
  width : Int,
  height : Int,
) -> (String, String, Int, Int) {
  let header_height = 1
  let footer_height = 1
  let status_height = 1
  let editor_height = 1
  let chat_height = height -
    header_height -
    footer_height -
    status_height -
    editor_height
  let chat_lines = self.chat_log.visible_lines(width, chat_height.max(1))
  let body_lines : Array[String] = [frame_line(self.header.text(), width)]
  for line in chat_lines {
    body_lines.push(frame_line(line, width))
  }
  body_lines.push(frame_line(self.status_text.text(), width))
  body_lines.push(frame_line(self.footer.text(), width))
  let (editor_line, cursor_col) = editor_frame_line(self.editor, width)
  while body_lines.length() < height - 1 {
    body_lines.push(spaces(width))
  }
  (body_lines.join("\n"), editor_line, cursor_col, height - 1)
}

///|
pub fn TUI::new() -> TUI raise {
  let terminal = Terminal::new()
  let chat_log = ChatLog::new()
  let editor = Editor::with_prompt("> ")
  let status_loader = Loader::new()
  let status_text = Text::new("")
  let header = Text::new("")
  let footer = Text::new("")
  let state = TuiState::new()
  let tui = TUI::{
    terminal,
    chat_log,
    editor,
    status_loader,
    status_text,
    header,
    footer,
    state,
    running: false,
    on_submit: None,
    on_command: None,
    on_escape: None,
    on_ctrl_c: None,
    on_ctrl_d: None,
    on_ctrl_o: None,
    render_needed: false,
    last_render_at: 0,
    last_width: 0,
    last_height: 0,
    needs_full_redraw: true,
    last_body_frame: "",
    last_editor_line: "",
    last_cursor_col: -1,
    last_cursor_row: -1,
  }
  tui.editor.set_on_submit(fn(text : String) { tui.submit(text) })
  tui
}

///|
pub fn TUI::set_on_submit(self : TUI, callback : (String) -> Unit) -> Unit {
  self.on_submit = Some(callback)
}

///|
pub fn TUI::set_on_command(self : TUI, callback : (String) -> Unit) -> Unit {
  self.on_command = Some(callback)
}

///|
pub fn TUI::set_on_escape(self : TUI, callback : () -> Unit) -> Unit {
  self.on_escape = Some(callback)
}

///|
pub fn TUI::set_on_ctrl_c(self : TUI, callback : () -> Unit) -> Unit {
  self.on_ctrl_c = Some(callback)
}

///|
pub fn TUI::set_on_ctrl_d(self : TUI, callback : () -> Unit) -> Unit {
  self.on_ctrl_d = Some(callback)
}

///|
pub fn TUI::set_on_ctrl_o(self : TUI, callback : () -> Unit) -> Unit {
  self.on_ctrl_o = Some(callback)
}

///|
pub fn TUI::chat_log(self : TUI) -> ChatLog {
  self.chat_log
}

///|
pub fn TUI::state(self : TUI) -> TuiState {
  self.state
}

///|
pub fn TUI::editor(self : TUI) -> Editor {
  self.editor
}

///|
pub fn TUI::terminal(self : TUI) -> Terminal {
  self.terminal
}

///|
pub fn TUI::update_header(self : TUI) -> Unit {
  let theme = Theme::default()
  let text = "moonclaw tui - agent \{self.state.agent_id()} - session \{self.state.session_key()}"
  self.header.set_text(theme.header(text))
}

///|
pub fn TUI::update_footer(self : TUI) -> Unit {
  let theme = Theme::default()
  let parts = [
    "agent \{self.state.agent_id()}",
    "session \{self.state.session_key()}",
    self.state.model(),
  ]
  self.footer.set_text(theme.dim_style(parts.join(" | ")))
}

///|
pub fn TUI::update_status(self : TUI) -> Unit {
  let theme = Theme::default()
  let state = if self.state.is_busy() { "working" } else { "idle" }
  let activity = if self.state.activity_status().length() > 0 {
    self.state.activity_status()
  } else {
    "idle"
  }
  let text = "[\{state}] \{activity} | \{self.state.connection_status()}"
  self.status_loader.stop()
  self.status_text.set_text(theme.dim_style(text))
}

///|
pub async fn TUI::start(self : TUI) -> Unit {
  self.terminal.start()
  self.running = true
  self.render()
}

///|
pub async fn TUI::stop(self : TUI) -> Unit {
  self.terminal.stop()
  self.running = false
}

///|
pub fn TUI::request_stop(self : TUI) -> Unit {
  self.running = false
}

///|
pub fn TUI::is_running(self : TUI) -> Bool {
  self.running
}

///|
pub fn TUI::request_render(self : TUI) -> Unit {
  self.render_needed = true
}

///|
pub fn TUI::scroll_chat_to_bottom(self : TUI) -> Unit {
  let (width, height) = self.terminal.size()
  let chat_height = height - 4
  self.chat_log.maybe_scroll_to_bottom(width, chat_height)
}

///|
pub async fn TUI::render(self : TUI) -> Unit {
  self.terminal.update_size() catch {
    _ => ()
  }
  self.update_header()
  self.update_footer()
  self.update_status()
  let (width, height) = self.terminal.size()
  let resized = width != self.last_width || height != self.last_height
  self.last_width = width
  self.last_height = height
  let chat_height = height - 4
  self.chat_log.normalize_scroll(width, chat_height.max(1))
  let (body_frame, editor_line, cursor_col, cursor_row) = self.build_frame(
    width,
    height.max(1),
  )
  let frame_unchanged = !self.needs_full_redraw &&
    !resized &&
    body_frame == self.last_body_frame &&
    editor_line == self.last_editor_line &&
    cursor_col == self.last_cursor_col &&
    cursor_row == self.last_cursor_row
  if frame_unchanged {
    self.last_render_at = @async.now()
    self.render_needed = false
    return
  }
  let output = RenderOutput::new()
  let body_unchanged = !self.needs_full_redraw &&
    !resized &&
    body_frame == self.last_body_frame
  if body_unchanged {
    output.write(cursor_to(0, cursor_row))
    output.write(ClearLineRight)
    output.write(editor_line)
  } else {
    let body_lines = body_frame
      .split("\n")
      .map(fn(v) { v.to_string() })
      .collect()
    let previous_body_lines = self.last_body_frame
      .split("\n")
      .map(fn(v) { v.to_string() })
      .collect()
    output.write(CursorHide)
    if self.needs_full_redraw || resized {
      write_repainted_lines(output, 0, body_lines)
    } else {
      write_changed_lines(output, 0, body_lines, previous_body_lines)
    }
    output.write(cursor_to(0, cursor_row))
    output.write(ClearLineRight)
    output.write(editor_line)
  }
  if !body_unchanged {
    self.needs_full_redraw = false
  }
  output.write(cursor_to(cursor_col, cursor_row))
  if !body_unchanged {
    output.write(CursorShow)
  }
  self.terminal.write_bytes(output.to_bytes())
  self.terminal.flush()
  self.last_body_frame = body_frame
  self.last_editor_line = editor_line
  self.last_cursor_col = cursor_col
  self.last_cursor_row = cursor_row
  self.last_render_at = @async.now()
  self.render_needed = false
}

///|
async fn TUI::render_if_due(self : TUI, force? : Bool = false) -> Unit {
  if !self.render_needed {
    return
  }
  let now = @async.now()
  let min_interval = if force {
    EditorRenderIntervalMs
  } else {
    BodyRenderIntervalMs
  }
  if force || now - self.last_render_at >= min_interval {
    self.render()
  }
}

///|
pub fn TUI::handle_key(self : TUI, key : Key) -> Bool {
  match key {
    Escape => {
      if self.on_escape is Some(cb) {
        cb()
      }
      true
    }
    Ctrl('c') => {
      if self.on_ctrl_c is Some(cb) {
        cb()
      }
      true
    }
    Ctrl('d') => {
      if self.on_ctrl_d is Some(cb) {
        cb()
      }
      true
    }
    Ctrl('o') => {
      if self.on_ctrl_o is Some(cb) {
        cb()
      }
      true
    }
    Up => {
      self.chat_log.scroll_up(3)
      self.render_needed = true
      true
    }
    Down => {
      let (_, height) = self.terminal.size()
      let chat_height = height - 4
      self.chat_log.scroll_down(3, self.terminal.width, chat_height)
      self.render_needed = true
      true
    }
    PageUp => {
      let (_, height) = self.terminal.size()
      self.chat_log.scroll_up(height - 2)
      self.render_needed = true
      true
    }
    PageDown => {
      let (_, height) = self.terminal.size()
      let chat_height = height - 4
      self.chat_log.scroll_down(height - 2, self.terminal.width, chat_height)
      self.render_needed = true
      true
    }
    _ => {
      // Let editor handle other keys, but request render afterwards
      let result = self.editor.handle_key(key)
      if result {
        self.render_needed = true
      }
      result
    }
  }
}

///|
pub fn TUI::submit(self : TUI, text : String) -> Unit {
  let trimmed = text.trim()
  if trimmed.length() == 0 {
    return
  }
  if trimmed.has_prefix("/") {
    if self.on_command is Some(cb) {
      cb(trimmed.to_string())
    }
  } else if self.on_submit is Some(cb) {
    cb(trimmed.to_string())
  }
  self.editor.add_to_history(text)
  self.editor.clear()
}

///|
pub async fn TUI::run_event_loop(self : TUI) -> Unit {
  while self.running {
    self.terminal.update_size() catch {
      _ => ()
    }
    let result : Result[Bytes, Error] = try? self.terminal.input.read_exactly(1)
    match result {
      Ok(bytes) =>
        if bytes.length() > 0 {
          let key = parse_key(bytes[:])
          ignore(self.handle_key(key))
          match key {
            Enter => self.render_if_due(force=true)
            _ => self.render_if_due(force=true)
          }
        } else if self.render_needed {
          self.render_if_due()
        }
      Err(_) => {
        if self.render_needed {
          self.render_if_due()
        }
        @async.sleep(10)
      }
    }
  }
}
