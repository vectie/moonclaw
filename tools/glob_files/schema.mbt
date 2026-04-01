///|
let schema : @tool.JsonSchema = {
  "type": "object",
  "properties": {
    "path": {
      "type": "string",
      "description": "Directory to search from, relative to the current working directory",
    },
    "pattern": {
      "type": "string",
      "description": "Glob pattern to match, supporting *, ?, and **",
    },
    "max_results": {
      "type": "integer",
      "description": "Maximum number of matching paths to return",
      "minimum": 1,
    },
    "respect_gitignore": {
      "type": "boolean",
      "description": "Whether to skip paths ignored by git",
    },
    "include_hidden": {
      "type": "boolean",
      "description": "Whether to include hidden files and directories",
    },
    "include_directories": {
      "type": "boolean",
      "description": "Whether matching directories should also be returned",
    },
  },
  "required": ["pattern"],
}

///|
priv struct GlobFilesInput {
  path : String?
  pattern : String
  max_results : Int?
  respect_gitignore : Bool?
  include_hidden : Bool?
  include_directories : Bool?
} derive(FromJson)
