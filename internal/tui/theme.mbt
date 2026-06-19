///|
pub(all) struct Theme {
  text : Color
  dim : Color
  accent : Color
  accent_soft : Color
  border : Color
  user_bg : Color
  user_text : Color
  system_text : Color
  tool_pending_bg : Color
  tool_success_bg : Color
  tool_error_bg : Color
  tool_title : Color
  tool_output : Color
  quote : Color
  quote_border : Color
  code : Color
  code_block_bg : Color
  code_border : Color
  link : Color
  error : Color
  success : Color
}

///|
pub fn Theme::default() -> Theme {
  {
    text: Rgb(232, 227, 213),
    dim: Rgb(123, 127, 135),
    accent: Rgb(246, 196, 83),
    accent_soft: Rgb(242, 166, 90),
    border: Rgb(60, 65, 75),
    user_bg: Rgb(43, 47, 54),
    user_text: Rgb(243, 238, 224),
    system_text: Rgb(155, 163, 178),
    tool_pending_bg: Rgb(31, 42, 47),
    tool_success_bg: Rgb(30, 45, 35),
    tool_error_bg: Rgb(47, 31, 31),
    tool_title: Rgb(246, 196, 83),
    tool_output: Rgb(225, 218, 203),
    quote: Rgb(140, 200, 255),
    quote_border: Rgb(59, 77, 107),
    code: Rgb(240, 201, 135),
    code_block_bg: Rgb(30, 35, 42),
    code_border: Rgb(52, 58, 69),
    link: Rgb(125, 211, 165),
    error: Rgb(249, 112, 102),
    success: Rgb(125, 211, 165),
  }
}

///|
pub fn Theme::text_style(self : Theme, text : String) -> String {
  colorize(text, self.text)
}

///|
pub fn Theme::dim_style(self : Theme, text : String) -> String {
  colorize(text, self.dim)
}

///|
pub fn Theme::accent_style(self : Theme, text : String) -> String {
  colorize(text, self.accent)
}

///|
pub fn Theme::accent_soft_style(self : Theme, text : String) -> String {
  colorize(text, self.accent_soft)
}

///|
pub fn Theme::bold_accent(self : Theme, text : String) -> String {
  styled(text, fg=self.accent, styles=[StyleBold])
}

///|
pub fn Theme::bold_accent_soft(self : Theme, text : String) -> String {
  styled(text, fg=self.accent_soft, styles=[StyleBold])
}

///|
pub fn Theme::header(self : Theme, text : String) -> String {
  styled(text, fg=self.accent, styles=[StyleBold])
}

///|
pub fn Theme::system(self : Theme, text : String) -> String {
  colorize(text, self.system_text)
}

///|
pub fn Theme::user_style(self : Theme, text : String) -> String {
  styled(text, fg=self.user_text, bg=self.user_bg)
}

///|
pub fn Theme::tool_title_style(self : Theme, text : String) -> String {
  colorize(text, self.tool_title)
}

///|
pub fn Theme::tool_output_style(self : Theme, text : String) -> String {
  colorize(text, self.tool_output)
}

///|
pub fn Theme::error_style(self : Theme, text : String) -> String {
  colorize(text, self.error)
}

///|
pub fn Theme::success_style(self : Theme, text : String) -> String {
  colorize(text, self.success)
}

///|
pub fn Theme::border_style(self : Theme, text : String) -> String {
  colorize(text, self.border)
}

///|
pub fn Theme::code_style(self : Theme, text : String) -> String {
  colorize(text, self.code)
}

///|
pub fn Theme::link_style(self : Theme, text : String) -> String {
  colorize(text, self.link)
}

///|
pub fn Theme::quote_style(self : Theme, text : String) -> String {
  colorize(text, self.quote)
}

///|
pub fn Theme::bold(_self : Theme, text : String) -> String {
  bold(text)
}

///|
pub fn Theme::italic(_self : Theme, text : String) -> String {
  italic(text)
}

///|
pub fn Theme::underline(_self : Theme, text : String) -> String {
  underline(text)
}
