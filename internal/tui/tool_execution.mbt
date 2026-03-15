///|
pub enum ToolStatus {
  Pending
  Running
  Success
  Error
}

///|
pub(all) struct ToolExecution {
  tool_name : String
  mut args : String
  mut result : String
  mut status : ToolStatus
  mut expanded : Bool
  mut start_time : Int
}

///|
pub fn ToolExecution::new(tool_name : String, args : String) -> ToolExecution {
  ToolExecution::{
    tool_name,
    args,
    result: "",
    status: ToolStatus::Pending,
    expanded: false,
    start_time: 0,
  }
}

///|
pub fn ToolExecution::set_args(self : ToolExecution, args : String) -> Unit {
  self.args = args
}

///|
pub fn ToolExecution::set_result(
  self : ToolExecution,
  result : String,
  is_error? : Bool = false,
) -> Unit {
  self.result = result
  self.status = if is_error { ToolStatus::Error } else { ToolStatus::Success }
}

///|
pub fn ToolExecution::set_partial_result(
  self : ToolExecution,
  result : String,
) -> Unit {
  self.result = result
}

///|
pub fn ToolExecution::set_status(
  self : ToolExecution,
  status : ToolStatus,
) -> Unit {
  self.status = status
}

///|
pub fn ToolExecution::set_expanded(
  self : ToolExecution,
  expanded : Bool,
) -> Unit {
  self.expanded = expanded
}

///|
pub fn ToolExecution::set_start_time(self : ToolExecution, time : Int) -> Unit {
  self.start_time = time
}

///|
pub fn ToolExecution::tool_name(self : ToolExecution) -> String {
  self.tool_name
}

///|
pub fn ToolExecution::args(self : ToolExecution) -> String {
  self.args
}

///|
pub fn ToolExecution::result(self : ToolExecution) -> String {
  self.result
}

///|
pub fn ToolExecution::status(self : ToolExecution) -> ToolStatus {
  self.status
}

///|
pub fn ToolExecution::expanded(self : ToolExecution) -> Bool {
  self.expanded
}

///|
pub fn ToolExecution::get_preferred_height(
  self : ToolExecution,
  width : Int,
) -> Int {
  let mut height = 3
  if self.expanded {
    let inner_width = width - 4
    let args_lines = self.args.split("\n").collect()
    for line in args_lines {
      let line_width = @unicode/width.string(line)
      let wrapped = if inner_width > 0 {
        (line_width + inner_width - 1) / inner_width
      } else {
        1
      }
      height += wrapped.max(1)
    }
    if self.result.length() > 0 {
      height += 1
      let result_lines = self.result.split("\n").collect()
      for line in result_lines {
        let line_width = @unicode/width.string(line)
        let wrapped = if inner_width > 0 {
          (line_width + inner_width - 1) / inner_width
        } else {
          1
        }
        height += wrapped.max(1)
      }
    }
  }
  height
}

///|
pub fn ToolExecution::render(
  self : ToolExecution,
  output : RenderOutput,
  x : Int,
  y : Int,
  width : Int,
  height : Int,
) -> Unit {
  let theme = Theme::default()
  output.write(cursor_to(x, y))
  output.write(ClearLineRight)
  let status_icon = match self.status {
    Pending => theme.dim_style("○")
    Running => theme.accent_style("◐")
    Success => theme.success_style("●")
    Error => theme.error_style("✗")
  }
  output.write(status_icon)
  output.write(" ")
  output.write(theme.tool_title_style(self.tool_name))
  let expand_hint = if self.expanded { " [collapse]" } else { " [expand]" }
  output.write(theme.dim_style(expand_hint))
  if !self.expanded {
    let args_preview = truncate_to_width(self.args, width - 20)
    if args_preview.length() > 0 {
      output.write(" ")
      output.write(theme.dim_style(args_preview))
    }
    return
  }
  let mut current_y = y + 1
  let inner_width = width - 4
  let max_lines = height - 2
  let mut line_idx = 0
  output.write(cursor_to(x + 2, current_y))
  output.write(ClearLineRight)
  output.write(theme.dim_style("Args:"))
  current_y += 1
  let args_lines = self.args.split("\n").collect()
  for line in args_lines {
    if line_idx >= max_lines - 2 {
      break
    }
    output.write(cursor_to(x + 2, current_y))
    output.write(ClearLineRight)
    output.write(
      theme.tool_output_style(truncate_to_width(line.to_string(), inner_width)),
    )
    current_y += 1
    line_idx += 1
  }
  if self.result.length() > 0 && line_idx < max_lines - 1 {
    output.write(cursor_to(x + 2, current_y))
    output.write(ClearLineRight)
    output.write(theme.dim_style("Result:"))
    current_y += 1
    line_idx += 1
    let result_lines = self.result.split("\n").collect()
    for line in result_lines {
      if line_idx >= max_lines {
        break
      }
      output.write(cursor_to(x + 2, current_y))
      output.write(ClearLineRight)
      let is_error = match self.status {
        Error => true
        _ => false
      }
      let styled = if is_error {
        theme.error_style(truncate_to_width(line.to_string(), inner_width))
      } else {
        theme.tool_output_style(
          truncate_to_width(line.to_string(), inner_width),
        )
      }
      output.write(styled)
      current_y += 1
      line_idx += 1
    }
  }
}
