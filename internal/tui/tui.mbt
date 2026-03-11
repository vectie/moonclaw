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
  if self.needs_full_redraw || resized {
    self.terminal.clear_screen()
    self.needs_full_redraw = false
  } else {
    self.terminal.move_to(0, 0)
  }
  self.last_width = width
  self.last_height = height
  let header_height = 1
  let footer_height = 1
  let status_height = 1
  let editor_height = 1
  let chat_height = height -
    header_height -
    footer_height -
    status_height -
    editor_height
  self.chat_log.normalize_scroll(width, chat_height.max(1))
  let output = RenderOutput::new()
  self.header.render(output, 0, 0, width, header_height)
  self.chat_log.render(output, 0, header_height, width, chat_height.max(1))
  self.status_text.render(
    output,
    0,
    header_height + chat_height,
    width,
    status_height,
  )
  self.footer.render(
    output,
    0,
    height - footer_height - editor_height,
    width,
    footer_height,
  )
  self.editor.render(output, 0, height - editor_height, width, editor_height)
  self.terminal.write_bytes(output.to_bytes())
  self.terminal.flush()
  self.last_render_at = @async.now()
  self.render_needed = false
}

///|
async fn TUI::render_if_due(self : TUI, force? : Bool = false) -> Unit {
  if !self.render_needed {
    return
  }
  let now = @async.now()
  if force || now - self.last_render_at >= 33L {
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
          self.render_if_due(force=true)
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
