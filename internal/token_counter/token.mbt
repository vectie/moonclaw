///|
struct Counter {
  logger : @pino.Logger
  overhead : Int
  // mut tools : Bool
  encoding : @tiktoken.Encoding
  /// Per-model calibration factors. Maps model name to calibration factor.
  /// Factor > 1.0 means our estimates are low, < 1.0 means estimates are high.
  calibration : Map[String, Double]
  /// EMA smoothing factor (0.0-1.0). Higher = more weight to recent observations.
  calibration_alpha : Double
}

///|
const DefaultCalibrationAlpha : Double = 0.3

///|
const SystemOverhead : Int = 7

///|
const ToolsOverhead : Int = 320

///|
const ToolOverhead : Int = 20

///|
/// Creates a new token counter with the cl100k\_base encoding.
///
/// Returns a new `Counter` instance configured with the tiktoken cl100k\_base
/// encoding, which is commonly used for OpenAI's GPT models.
///
/// Throws an error if the cl100k\_base encoding cannot be initialized.
pub fn Counter::new(
  logger~ : @pino.Logger,
  calibration_alpha? : Double = DefaultCalibrationAlpha,
) -> Counter raise {
  {
    logger,
    overhead: SystemOverhead,
    // tools: false,
    encoding: @tiktoken.cl100k_base(),
    calibration: {},
    calibration_alpha,
  }
}

///|
fn Counter::_count_string(self : Counter, text : String) -> Int {
  self.encoding.encode(text).length()
}

///|
pub fn Counter::count_string(self : Counter, text : String) -> Int {
  self.overhead + self._count_string(text)
}

///|
fn Counter::decode_prefix(
  self : Counter,
  tokens : Array[Int],
  end : Int,
) -> String {
  if end <= 0 {
    return ""
  }
  self.encoding.decode(tokens[0:end]) catch {
    // A token boundary can bisect a multi-token UTF-8 scalar. Step back to the
    // nearest valid boundary rather than using unsafe character slicing.
    _ => self.decode_prefix(tokens, end - 1)
  }
}

///|
/// Truncate text at a tokenizer boundary. This is used for compact prompt
/// checkpoints where byte or UTF-16 slicing could corrupt non-ASCII content.
pub fn Counter::truncate_string(
  self : Counter,
  text : String,
  max_tokens : Int,
) -> String {
  if max_tokens <= 0 {
    return ""
  }
  let tokens = self.encoding.encode(text)
  if tokens.length() <= max_tokens {
    return text
  }
  self.decode_prefix(tokens, max_tokens) + " …"
}

///|
fn Counter::count_content_parts(
  self : Counter,
  parts : Array[@openai.ChatCompletionContentPartParam],
) -> Int {
  let mut count = 0
  for part in parts {
    match part {
      Text(text) => count += self._count_string(text.text)
      ImageUrl(image) => count += self._count_string(image.url) + 85
    }
  }
  count
}

///|
fn Counter::count_function(
  self : Counter,
  function : @openai.ChatCompletionMessageToolCallFunction,
) -> Int {
  self._count_string(function.name) +
  (match function.arguments {
    Some(arguments) => self._count_string(arguments)
    None => 0
  })
}

///|
pub fn Counter::count_message(
  self : Counter,
  message : @openai.ChatCompletionMessageParam,
) -> Int {
  match message {
    Assistant(assistant) => {
      let mut count = 0
      count += self.count_content_parts(assistant.content)
      for tool_call in assistant.tool_calls {
        count += self._count_string(tool_call.id)
        count += self.count_function(tool_call.function)
      }
      count
    }
    User(user) => self.count_content_parts(user.content)
    System(system) => self.count_content_parts(system.content)
    Tool(tool) => self.count_content_parts(tool.content)
  }
}

///|
fn Counter::count_messages(
  self : Counter,
  messages : Array[@openai.ChatCompletionMessageParam],
) -> Int {
  let mut count = 0
  for message in messages {
    count += self.count_message(message)
  }
  count
}

///|
fn Counter::count_tool(
  self : Counter,
  tool : @openai.ChatCompletionToolParam,
) -> Int {
  let mut count = 0
  count += ToolOverhead
  guard tool is Function(function)
  count += self._count_string(function.name)
  count += 2 * self._count_string(function.description)
  let parameters = function.parameters.to_json().stringify(indent=2)
  let parameters = self._count_string(parameters)
  count += (parameters.to_double() / 2.0.sqrt()).to_int()
  count
}

///|
#cfg(false)
fn Counter::add_tool(
  self : Counter,
  tool : @openai.ChatCompletionToolParam,
) -> Unit raise {
  if !self.tools {
    self.overhead += ToolsOverhead
    self.tools = true
  }
  self.overhead += self.count_tool(tool)
}

///|
/// Counts the total number of tokens required for a complete chat completion
/// request.
///
/// Parameters:
///
/// * `self` : The token counter instance.
/// * `param` : The chat completion parameters containing messages, tools, and
///   other configuration.
///
/// Returns the total token count including system overhead, tools overhead,
/// individual tool costs, and message content.
///
/// Throws an error if token encoding fails for any text content in the
/// parameters.
pub async fn Counter::count_param(
  self : Counter,
  messages~ : Array[@openai.ChatCompletionMessageParam],
  tools? : Array[@openai.ChatCompletionToolParam] = [],
) -> Int {
  let mut count = SystemOverhead
  if !tools.is_empty() {
    count += ToolsOverhead
  }
  for tool in tools {
    count += self.count_tool(tool)
  }
  count += self.count_messages(messages)
  self.logger.info("TokenCounted", data={ "token_count": count })
  count
}

///|
/// Updates calibration factor based on actual usage from model response.
/// Uses Exponential Moving Average (EMA) for smooth adaptation.
///
/// Parameters:
///
/// * `model_name` : The model identifier for per-model calibration
/// * `estimated_tokens` : Our estimated input token count before the request
/// * `actual_tokens` : The actual prompt_tokens from the model's usage response
pub fn Counter::calibrate(
  self : Counter,
  model_name~ : String,
  estimated_tokens~ : Int,
  actual_tokens~ : Int,
) -> Unit {
  // Avoid division by zero
  guard estimated_tokens > 0 && actual_tokens > 0 else { return }
  let ratio = actual_tokens.to_double() / estimated_tokens.to_double()
  let current_factor = self.calibration.get(model_name).unwrap_or(1.0)

  // EMA: new_factor = alpha * ratio + (1 - alpha) * old_factor
  let new_factor = self.calibration_alpha * ratio +
    (1.0 - self.calibration_alpha) * current_factor

  // Clamp to reasonable range [0.5, 2.0] to prevent extreme drift
  let clamped_factor = if new_factor < 0.5 {
    0.5
  } else if new_factor > 2.0 {
    2.0
  } else {
    new_factor
  }
  self.calibration[model_name] = clamped_factor
}

///|
/// Returns the calibrated token count for a given model.
pub fn Counter::apply_calibration(
  self : Counter,
  model_name~ : String,
  raw_count~ : Int,
) -> Int {
  let factor = self.calibration.get(model_name).unwrap_or(1.0)
  (raw_count.to_double() * factor).to_int()
}
