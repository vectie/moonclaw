# Model Loader 调用链

## 概述

`Loader` 是模型加载的核心组件，负责从多种来源加载 AI 模型配置。它支持从配置文件、环境变量、OAuth 认证等多种方式获取模型凭证。

## 核心结构

```
struct Loader {
  home : StringView    // 用户主目录路径
  cwd : StringView     // 当前工作目录路径
  models : Array[Model] // 已加载的模型缓存
}
```

## 调用流程图

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              入口函数                                        │
│                                                                             │
│   load(home?, cwd?, name?) ────────────────────────────────────────────────►│
│           │                                                                 │
│           ▼                                                                 │
│   Loader::new(home?, cwd?)                                                  │
│           │                                                                 │
│           ├──► @os.home()        // 获取用户主目录                           │
│           ├──► @os.cwd()         // 获取当前工作目录                         │
│           └──► loader.load()     // 加载模型配置文件                         │
│                       │                                                     │
│                       ▼                                                     │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │                    Loader::load()                                    │   │
│   │                                                                     │   │
│   │   1. 清空 models 缓存                                                │   │
│   │   2. 读取 {cwd}/.moonsuite/products/moonclaw/models/models.json     │   │
│   │   3. 读取 {home}/.moonsuite/products/moonclaw/models/models.json    │   │
│   │   4. 将模型追加到缓存                                                │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         Loader::get_model(name?)                            │
│                                                                             │
│   1. 调用 self.load() 刷新模型缓存                                          │
│                                                                             │
│   2. 根据模型名称前缀路由:                                                   │
│      ┌─────────────────┬────────────────────────────────────────────────┐   │
│      │ 前缀            │ 处理函数                                         │   │
│      ├─────────────────┼────────────────────────────────────────────────┤   │
│      │ qwen/           │ load_qwen_model()        → 通义千问 API        │   │
│      │ kimi/           │ load_kimi_model()        → Kimi API            │   │
│      │ kimi-coding/    │ load_kimi_coding_model() → Kimi Coding API     │   │
│      │ codex/          │ load_codex_model()       → Codex OAuth 认证    │   │
│      │ copilot/        │ load_copilot_model()     → GitHub Copilot 认证 │   │
│      │ 其他            │ 继续查找缓存或 OpenRouter                        │   │
│      └─────────────────┴────────────────────────────────────────────────┘   │
│                                                                             │
│   3. 在缓存中查找匹配的模型                                                  │
│                                                                             │
│   4. 自动检测流程 (当未指定模型名或缓存未命中时):                             │
│      ┌──────────────────────────────────────────────────────────────────┐   │
│      │ 优先级 │ 来源                                                    │   │
│      ├────────┼─────────────────────────────────────────────────────────┤   │
│      │ 1      │ load_qwen_model() - Qwen/DashScope API Key              │   │
│      │ 2      │ load_kimi_model() - Kimi/Moonshot API Key               │   │
│      │ 3      │ load_kimi_coding_model() - Kimi Coding API Key          │   │
│      │ 4      │ load_openrouter_model() - OpenRouter/OpenAI API Key     │   │
│      │ 5      │ load_codex_model() - Codex OAuth (allow_auto_login=false)│   │
│      │ 6      │ load_copilot_model() - Copilot (allow_auto_login=false) │   │
│      └────────┴─────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## API Key 加载优先级

### Qwen 模型 (load_qwen_model)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      Qwen API Key 获取优先级                                 │
│                                                                             │
│   1. .moonsuite/products/moonclaw/moonclaw.json 中的配置                    │
│      ├── {cwd}/.moonsuite/products/moonclaw/moonclaw.json   (项目级配置)    │
│      └── {home}/.moonsuite/products/moonclaw/moonclaw.json  (用户级配置)    │
│      支持的字段:                                                             │
│      ├── qwen_api_key (直接指定)                                            │
│      └── env.QWEN_API_KEY / env.DASHSCOPE_API_KEY (环境变量配置)            │
│                                                                             │
│   2. 环境变量 QWEN_API_KEY                                                  │
│                                                                             │
│   3. 环境变量 DASHSCOPE_API_KEY                                             │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Kimi 模型 (load_kimi_model)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      Kimi API Key 获取优先级                                 │
│                                                                             │
│   1. .moonsuite/products/moonclaw/moonclaw.json 中的配置                    │
│      ├── {cwd}/.moonsuite/products/moonclaw/moonclaw.json   (项目级配置)    │
│      └── {home}/.moonsuite/products/moonclaw/moonclaw.json  (用户级配置)    │
│      支持的字段:                                                             │
│      ├── kimi_api_key (直接指定)                                            │
│      └── env.KIMI_API_KEY / env.MOONSHOT_API_KEY (环境变量配置)             │
│                                                                             │
│   2. 环境变量 KIMI_API_KEY                                                  │
│                                                                             │
│   3. 环境变量 MOONSHOT_API_KEY                                              │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### KimiCoding 模型 (load_kimi_coding_model)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      KimiCoding API Key 获取优先级                           │
│                                                                             │
│   1. .moonsuite/products/moonclaw/moonclaw.json 中的配置                    │
│      ├── {cwd}/.moonsuite/products/moonclaw/moonclaw.json   (项目级配置)    │
│      └── {home}/.moonsuite/products/moonclaw/moonclaw.json  (用户级配置)    │
│      支持的字段:                                                             │
│      ├── kimi_coding_api_key (直接指定)                                     │
│      └── env.KIMI_CODING_API_KEY (环境变量配置)                             │
│                                                                             │
│   2. 环境变量 KIMI_CODING_API_KEY                                           │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### OpenRouter 模型 (load_openrouter_model)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      API Key 获取优先级                                      │
│                                                                             │
│   1. .moonsuite/products/moonclaw/moonclaw.json 中的配置                    │
│      ├── {cwd}/.moonsuite/products/moonclaw/moonclaw.json   (项目级配置)    │
│      └── {home}/.moonsuite/products/moonclaw/moonclaw.json  (用户级配置)    │
│      支持的字段:                                                             │
│      ├── api_key (直接指定)                                                 │
│      └── env.OPEN_ROUTER_API_KEY / env.OPENROUTER_API_KEY (环境变量配置)    │
│                                                                             │
│   2. 环境变量 OPENROUTER_API_KEY                                            │
│                                                                             │
│   3. 环境变量 OPENAI_API_KEY                                                │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Codex 模型 (load_codex_model)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      Codex OAuth 认证流程                                    │
│                                                                             │
│   1. 调用 @codex.load_credentials() 加载已保存的凭证                         │
│      ├── 成功: 使用凭证创建模型                                              │
│      └── 失败:                                                              │
│          ├── allow_auto_login=true  → 启动 OAuth 登录流程                   │
│          └── allow_auto_login=false → 返回 None                             │
│                                                                             │
│   凭证存储位置: .moonsuite/products/moonclaw/credentials/codex-credentials.json │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Copilot 模型 (load_copilot_model)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      Copilot OAuth 认证流程                                  │
│                                                                             │
│   1. 调用 @copilot.get_valid_credentials() 获取有效凭证                      │
│      ├── 成功: 使用凭证创建模型                                              │
│      └── 失败:                                                              │
│          ├── allow_auto_login=true  → 启动 GitHub OAuth 登录流程            │
│          └── allow_auto_login=false → 返回 None                             │
│                                                                             │
│   凭证存储位置: .moonsuite/products/moonclaw/credentials/copilot-credentials.json │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 配置文件格式

### .moonsuite/products/moonclaw/models/models.json

```json
[
  {
    "name": "my-custom-model",
    "model_name": "anthropic/claude-sonnet-4.5",
    "model_type": "saas/openai",
    "api_key": "sk-xxx",
    "base_url": "https://openrouter.ai/api/v1",
    "safe_zone_tokens": 200000,
    "supports_anthropic_prompt_caching": true
  }
]
```

### .moonsuite/products/moonclaw/moonclaw.json

```json
{
  "api_key": "sk-or-xxx",
  "qwen_api_key": "sk-xxx",
  "kimi_api_key": "sk-xxx",
  "kimi_coding_api_key": "sk-xxx",
  "env": {
    "OPEN_ROUTER_API_KEY": "sk-or-xxx",
    "QWEN_API_KEY": "sk-xxx",
    "DASHSCOPE_API_KEY": "sk-xxx",
    "KIMI_API_KEY": "sk-xxx",
    "MOONSHOT_API_KEY": "sk-xxx",
    "KIMI_CODING_API_KEY": "sk-xxx"
  }
}
```

## 模型类型 (model_type)

| 值 | 说明 |
|---|---|
| `saas/openai` | OpenAI 兼容 API (OpenRouter, OpenAI 等) |
| `saas/qwen` | 通义千问 (阿里云 DashScope) |
| `saas/kimi` | Kimi (月之暗面 Moonshot AI) |
| `saas/kimi_coding` | Kimi Coding (月之暗面代码专用) |
| `saas/codex_oauth` | Codex OAuth 认证 |
| `saas/copilot` | GitHub Copilot 认证 |

## 公开 API

| 函数 | 说明 |
|---|---|
| `Loader::new(home?, cwd?)` | 创建新的 Loader 实例 |
| `Loader::get_model(name?)` | 获取模型配置 |
| `Loader::models()` | 获取所有已加载的模型 |
| `load(home?, cwd?, name?)` | 便捷函数，一次性加载模型 |

## 使用示例

```moonbit
// 使用便捷函数
let model = @model.load(name="anthropic/claude-sonnet-4.5")

// 使用 Qwen 模型
let model = @model.load(name="qwen/qwen3-coder-plus")

// 使用 Kimi 模型
let model = @model.load(name="kimi/kimi-k2.5")

// 使用 KimiCoding 模型
let model = @model.load(name="kimi-coding/k2p5")

// 使用 Loader 实例
let loader = @model.Loader::new()
let model = loader.get_model(name="copilot/gpt-5.2")

// 获取所有可用模型
let models = loader.models()
```
