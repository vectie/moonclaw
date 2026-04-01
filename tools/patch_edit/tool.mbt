///|
pub enum PatchEditMode {
  Preview
  Apply
} derive(ToJson, FromJson, Show)

///|
pub struct PatchEditResult {
  mode : PatchEditMode
  patch_valid : Bool
  changed : Bool
  summary : String
  added : Array[String]
  modified : Array[String]
  deleted : Array[String]
  file_count : Int
} derive(ToJson, FromJson, Show)

///|
priv struct Params {
  patch : String
  mode : String?
} derive(FromJson)

///|
fn preview_patch_edit_result(
  parsed : @apply_patch.ParsedPatch,
) -> PatchEditResult {
  let added : Array[String] = []
  let modified : Array[String] = []
  let deleted : Array[String] = []
  for hunk in parsed.hunks {
    match hunk {
      AddFile(path~, ..) => added.push(path)
      DeleteFile(path~) => deleted.push(path)
      UpdateFile(path~, move_path~, ..) =>
        modified.push(move_path.unwrap_or(path))
    }
  }
  let file_count = added.length() + modified.length() + deleted.length()
  PatchEditResult::{
    mode: Preview,
    patch_valid: true,
    changed: false,
    summary: "Patch is valid. Planned changes: \{file_count} file(s) (\{added.length()} added, \{modified.length()} modified, \{deleted.length()} deleted).",
    added,
    modified,
    deleted,
    file_count,
  }
}

///|
fn apply_patch_edit_result(
  result : @apply_patch.ApplyResult,
) -> PatchEditResult {
  let file_count = result.added.length() +
    result.modified.length() +
    result.deleted.length()
  PatchEditResult::{
    mode: Apply,
    patch_valid: true,
    changed: file_count > 0,
    summary: result.summary(),
    added: result.added,
    modified: result.modified,
    deleted: result.deleted,
    file_count,
  }
}

///|
fn patch_edit_description() -> String {
  [
    "Validate or apply a structured V4A patch with an explicit preview/apply contract.",
    "Use `mode=preview` to validate a patch and report the exact files that would change.",
    "Use `mode=apply` to apply the patch and get a structured change report.",
  ].join(" ")
}

///|
pub fn new(cwd : String) -> @tool.Tool[PatchEditResult] {
  @tool.new(
    name="patch_edit",
    description=patch_edit_description(),
    schema={
      "type": "object",
      "properties": {
        "patch": { "type": "string", "description": "V4A patch content" },
        "mode": {
          "type": "string",
          "enum": ["preview", "apply"],
          "description": "Validate only or apply the patch",
        },
      },
      "required": ["patch"],
    },
    async fn(args) -> @tool.ToolResult[PatchEditResult] noraise {
      let params : Params = @json.from_json(args) catch {
        err => return @tool.error("Invalid arguments: \{err}")
      }
      let parsed = @apply_patch.parse_patch(params.patch) catch {
        InvalidPatch(msg) => return @tool.error("Invalid patch: \{msg}")
        InvalidHunk(message~, line_number~) =>
          return @tool.error("Invalid hunk at line \{line_number}: \{message}")
      }
      match params.mode.unwrap_or("preview").trim().to_string() {
        "preview" => @tool.ok(preview_patch_edit_result(parsed))
        "apply" => {
          let result = @apply_patch.apply_hunks(parsed.hunks[:], cwd) catch {
            ApplyError(msg) =>
              return @tool.error("Failed to apply patch: \{msg}")
          }
          @tool.ok(apply_patch_edit_result(result))
        }
        mode =>
          @tool.error("Unsupported mode '\{mode}'. Expected preview or apply.")
      }
    },
  )
}
