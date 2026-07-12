///|
let schema : @tool.JsonSchema = {
  "type": "object",
  "properties": {
    "content": {
      "type": "string",
      "description": "The content to write to the file.",
    },
    "path": {
      "type": "string",
      "description": "The path of the file to write to, relative to the current working directory.",
    },
    "separator": {
      "type": "string",
      "description": "Optional separator to add between existing content and new content (default: newline).",
      "default": "\n",
    },
  },
  "required": ["path", "content"],
}

///|
priv struct Params {
  content : String // required
  path : String // required
  separator : String?
} derive(ToJson, FromJson)

///|
fn params(content~ : String, path~ : String, separator? : String) -> Params {
  { content, path, separator }
}

///|
pub fn json_input(
  content~ : String,
  path~ : String,
  separator? : String,
) -> Json {
  params(content~, path~, separator?).to_json()
}

///|
fn has_parent_escape(path : String) -> Bool {
  let normalized = path.replace(old="\\", new="/")
  for segment in normalized.split("/") {
    if segment == ".." {
      return true
    }
  }
  false
}

///|
fn path_is_within_workspace(cwd : String, path : String) -> Bool {
  path == cwd || path.has_prefix(cwd + "/")
}

///|
fn resolve_tool_path(cwd : String, path : String) -> String? {
  if @pathx.is_absolute(path) {
    if path_is_within_workspace(cwd, path) {
      Some(path)
    } else {
      None
    }
  } else if has_parent_escape(path) {
    None
  } else {
    Some(@pathx.join(cwd, path))
  }
}

///|
test {
  json_inspect(
    params(content="Hello, World!", path="example.txt", separator="\n"),
    content={
      "content": "Hello, World!",
      "path": "example.txt",
      "separator": "\n",
    },
  )
}

///|
struct Result {
  path : String
} derive(FromJson, ToJson)

///|
pub impl Show for Result with fn output(self : Result, logger : &Logger) -> Unit {
  logger.write_string("Content written to file at path: \{self.path}")
}

///|
pub fn new(cwd : String) -> @tool.Tool[Result] {
  @tool.new(
    description=(
      $|Write content to a file at the specified path. 
      $|If the file doesn't exist, it will be created. 
      $|If the file exists, the content will be appended. 
      $|This tool will automatically create any directories needed to write the file.
      $|
      $|When writing a MoonBit source file:
      $|- Remember: all files in a package are concatenated.
      $|- Do NOT create “god files”; prefer multiple small files.
      $|- You MAY create new files instead of expanding existing ones.
      $|- You MAY move declarations between files within a package.
      $|
    ),
    name="write_to_file",
    schema~,
    args => {
      let { path, separator, content } : Params = @json.from_json(args) catch {
        error => return @tool.error("Invalid arguments: \{error}")
      }
      let path = match resolve_tool_path(cwd, path) {
        Some(path) => path
        None =>
          return @tool.error(
            "Path must stay inside the current workspace: \{path}",
          )
      }
      let separator = separator.unwrap_or("\n")
      let content_to_append = if (@fsx.exists(path) catch {
          error =>
            return @tool.error("Failed to check if file exists: \{error}")
        }) {
        let existing_content = @fsx.read_file(path) catch {
          error => return @tool.error("Failed to read existing file: \{error}")
        }
        if existing_content.is_empty() {
          content
        } else {
          existing_content + separator + content
        }
      } else {
        content
      }
      let parent = @pathx.dirname(path)
      let _ = @fsx.make_directory(parent, recursive=true, exists_ok=true) catch {
        error =>
          return @tool.error(
            "Failed to create parent directories for file: \{error}",
          )
      }
      let _ = @fsx.write_to_file(path, content_to_append) catch {
        @os_error.OSError(_, ..) as error if error.is_EACCES() =>
          return @tool.error(
            "Permission denied: Cannot write to file \{path}. The file does not have write permissions.",
          )
        error => return @tool.error("Failed to write to file: \{error}")
      }
      let result = Result::{ path, }
      @tool.ok(result)
    },
  )
}
