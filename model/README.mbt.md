# Model Package

The model package provides configuration and loading of AI model providers.

## Core Types

### `Model`

Configuration for connecting to an AI model.

```moonbit nocheck
///|
pub struct Model {
  name : String
  description : String?
  model_name : String
  model_type : Type
  api_key : String
  base_url : String
  safe_zone_tokens : Int
  supports_anthropic_prompt_caching : Bool
  supports_apply_patch : Bool
  access_token : String?
  account_id : String?
  refresh_token : String?
  id_token : String?
} derive(ToJson, Eq, Show)
```

**Key Fields:**
- `name`: Identifier for this configuration
- `model_name`: Provider-specific model identifier
- `model_type`: Provider type (OpenAI, Anthropic, etc.)
- `api_key`: API authentication key
- `base_url`: API endpoint URL
- `safe_zone_tokens`: Token budget for context management

### `Provider`

Supported AI providers.

```moonbit nocheck
///|
pub(all) enum Provider {
  OpenAI
  Anthropic
  CodexOAuth
  Copilot
  Qwen
  Kimi
  KimiCoding
}
```

### `Type`

Model deployment type.

```moonbit nocheck
///|
pub(all) enum Type {
  SaaS(Provider)
}
```

## Model Presets

### CommonModels (OpenRouter)

```moonbit nocheck
///|
pub(all) enum CommonModels {
  Qwen3CoderPlus
  Qwen3CoderFlash
  Grok4Fast
  GrokCodeFast1
  ClaudeHaiku4_5
  ClaudeSonnet4_5
  ClaudeOpus4_5
  Gpt5Codex
  Gpt5
  Gpt5Mini
  Gpt5Nano
  KimiK2_0905
  Glm4_6
  MinimaxM2
  DeepseekV3_2
}
```

### CopilotModels

```moonbit nocheck
///|
pub(all) enum CopilotModels {
  Gpt4_1
  Gpt4o
  Gpt5
  Gpt5Mini
  Gpt5Codex
  Gpt5_1
  Gpt5_1Codex
  Gpt5_1CodexMax
  Gpt5_1CodexMini
  Gpt5_4
  O3
  O3Mini
  O4Mini
  Claude3_5Sonnet
  Claude3_7Sonnet
  ClaudeHaiku4_5
  ClaudeOpus4_5
  Gemini2_0Flash
  Gemini2_5Pro
  GrokCodeFast1
  // ... more models
}
```

## Key APIs

### Model Creation

```moonbit nocheck
pub fn Model::new(
  api_key~ : String,
  base_url~ : String,
  name~ : String,
  safe_zone_tokens~ : Int,
  model_name? : String,
  model_type? : Type,
  description? : String,
  supports_anthropic_prompt_caching? : Bool,
  // OAuth fields for CodexOAuth provider
  access_token? : String,
  account_id? : String,
  refresh_token? : String,
  id_token? : String,
) -> Model
```

### Preset Model Constructors

```moonbit nocheck
// OpenRouter models
pub fn open_router_model(
  api_key~ : String,
  name? : CommonModels,
) -> Model

// GitHub Copilot models
pub fn copilot_model(
  copilot_token~ : String,
  github_token~ : String,
  name? : CopilotModels,
) -> Model

// Codex OAuth models
pub fn codex_oauth_model(
  access_token~ : String,
  account_id~ : String,
  refresh_token~ : String,
  id_token? : String,
  name? : CodexModels,
) -> Model

// Qwen models
pub fn qwen_model(
  api_key~ : String,
  name? : QwenModels,
) -> Model

// Kimi models
pub fn kimi_model(api_key~ : String, name? : KimiModels) -> Model
pub fn kimi_coding_model(api_key~ : String, name? : KimiCodingModels) -> Model
```

### Model Loading

```moonbit nocheck
pub async fn load(
  home? : StringView,
  cwd? : StringView,
  name? : String,
) -> Model?
```

Loads model configuration from `~/.moonclaw/models.json` or project-local configuration.

### Loader

```moonbit nocheck
type Loader

pub async fn Loader::new(
  home? : StringView,
  cwd? : StringView,
) -> Self

pub async fn Loader::get_model(Self, name? : String) -> Model?
pub async fn Loader::models(Self) -> ArrayView[Model]
```

## Usage Example

```moonbit nocheck
// Using OpenRouter

///|
let model = @model.open_router_model(
  api_key="sk-or-...",
  name=@model.CommonModels::ClaudeSonnet4_5,
)

// Using GitHub Copilot

///|
let model = @model.copilot_model(
  copilot_token="ghu_...",
  github_token="ghp_...",
  name=@model.CopilotModels::Gpt5_1,
)

// Custom model configuration

///|
let model = @model.Model::new(
  api_key="your-api-key",
  base_url="https://api.example.com/v1",
  name="custom-model",
  safe_zone_tokens=128000,
  model_name="custom-model-v1",
)

// Load from configuration file

///|
let model = @model.load(name="my-model")
```

## Configuration File Format

Models are configured in `~/.moonclaw/models.json`:

```json
{
  "providers": {
    "openrouter": {
      "baseUrl": "https://openrouter.ai/api/v1",
      "apiKey": "sk-or-...",
      "models": [
        { "id": "claude-sonnet", "name": "anthropic/claude-sonnet-4.5" }
      ]
    }
  }
}
```

## Dependencies

- `json`: JSON serialization
- `uuid`: Unique identifiers
