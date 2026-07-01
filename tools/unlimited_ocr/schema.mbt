///|
let schema : @tool.JsonSchema = {
  "type": "object",
  "properties": {
    "pdf_path": {
      "type": "string",
      "description": "Path to the PDF to OCR. Relative paths are resolved from the MoonClaw working directory.",
    },
    "output_dir": {
      "type": "string",
      "description": "Directory where Unlimited-OCR should write extracted output. Defaults to raw/extracted.",
      "default": "raw/extracted",
    },
    "unlimited_ocr_root": {
      "type": "string",
      "description": "Path to the Unlimited-OCR checkout. If omitted, UNLIMITED_OCR_ROOT is used.",
    },
    "infer_script": {
      "type": "string",
      "description": "Path to Unlimited-OCR infer.py. Overrides unlimited_ocr_root.",
    },
    "python": {
      "type": "string",
      "description": "Python executable used to run infer.py.",
      "default": "python3",
    },
    "timeout_ms": {
      "type": "number",
      "description": "OCR timeout in milliseconds.",
      "default": 1800000,
    },
    "extra_args": {
      "type": "array",
      "items": { "type": "string" },
      "description": "Additional arguments passed after --pdf and --output_dir.",
      "default": [],
    },
  },
  "required": ["pdf_path"],
}
