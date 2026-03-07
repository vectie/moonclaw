# 模型类型对比

本文档介绍项目中支持的六种模型类型：Qwen、Kimi、KimiCoding、OpenRouter、Codex (CodexOAuth) 和 Copilot。

## 概览

| 特性 | Qwen | Kimi | KimiCoding | OpenRouter | Codex (CodexOAuth) | Copilot |
|------|------|------|------------|------------|-------------------|---------|
| **提供商** | 阿里云 DashScope | 月之暗面 Moonshot AI | 月之暗面 Moonshot AI | OpenRouter (第三方聚合) | OpenAI | GitHub |
| **认证方式** | API Key | API Key | API Key | API Key | OAuth (OpenAI账户) | OAuth (GitHub账户) |
| **Base URL** | `https://dashscope.aliyuncs.com/compatible-mode/v1` | `https://api.moonshot.cn/v1` | `https://api.moonshot.cn/v1` | `https://openrouter.ai/api/v1` | `https://chatgpt.com/backend-api` | `https://api.githubcopilot.com` |
| **凭证存储** | `~/.moonclaw/moonclaw.json` 或环境变量 | `~/.moonclaw/moonclaw.json` 或环境变量 | `~/.moonclaw/moonclaw.json` 或环境变量 | `~/.moonclaw/moonclaw.json` 或环境变量 | `~/.moonclaw/codex-credentials.json` | `~/.moonclaw/copilot-credentials.json` |
| **国内可用** | ✅ 是 | ✅ 是 | ✅ 是 | ❌ 否 | ❌ 否 | ❌ 否 |

## 详细说明

### 1. Qwen

- **定位**: 阿里云通义千问 API
- **特点**: 
  - 阿里云 DashScope 平台提供的模型服务
  - 支持 OpenAI 兼容 API 格式
  - 需要阿里云 API Key
- **适用场景**: 国内用户，需要使用通义千问系列模型
- **支持的模型**:
  - `qwen/qwen3-coder-plus` - 通义千问3代码增强版
  - `qwen/qwen3-coder-flash` - 通义千问3代码快速版
  - `qwen/qwen3-235b-a22b` - 通义千问3 235B
  - `qwen/qwen3-32b` - 通义千问3 32B
  - `qwen/qwen-max` - 通义千问Max
  - `qwen/qwen-plus` - 通义千问Plus
  - `qwen/qwen-turbo` - 通义千问Turbo
  - `qwen/qwen-long` - 通义千问长文本版

### 2. Kimi

- **定位**: 月之暗面 (Moonshot AI) Kimi API
- **特点**: 
  - Moonshot AI 提供的模型服务
  - 支持 OpenAI 兼容 API 格式
  - 需要 Moonshot AI API Key
  - 支持超长上下文 (最高 262K tokens)
- **适用场景**: 国内用户，需要使用 Kimi 系列模型
- **支持的模型**:
  - `kimi/kimi-k2-0905` - Kimi K2 (2025年9月版本)
  - `kimi/kimi-k2.5` - Kimi K2.5
  - `kimi/moonshot-v1-8k` - Moonshot V1 8K 上下文
  - `kimi/moonshot-v1-32k` - Moonshot V1 32K 上下文
  - `kimi/moonshot-v1-128k` - Moonshot V1 128K 上下文

### 3. KimiCoding

- **定位**: 月之暗面 (Moonshot AI) Kimi Coding API
- **特点**: 
  - Moonshot AI 提供的代码专用模型服务
  - 支持 OpenAI 兼容 API 格式
  - 需要 Kimi Coding API Key
  - 支持超长上下文 (262K tokens)
- **适用场景**: 国内用户，代码生成和编程辅助
- **支持的模型**:
  - `kimi-coding/k2p5` - Kimi K2.5 编码版
  - `kimi-coding/k2-0905` - Kimi K2 (2025年9月版本) 编码版

### 4. OpenRouter

- **定位**: 第三方 API 聚合服务
- **特点**: 
  - 一个 API Key 访问多种模型 (Claude、GPT、Qwen、Grok、DeepSeek 等)
  - 按使用量付费，价格透明
  - 需要自己购买 API Key
- **适用场景**: 需要灵活切换不同模型的用户
- **支持的模型**:
  - `qwen/qwen3-coder-plus`
  - `qwen/qwen3-coder-flash`
  - `x-ai/grok-4-fast`
  - `x-ai/grok-code-fast-1`
  - `anthropic/claude-haiku-4.5`
  - `anthropic/claude-sonnet-4.5`
  - `anthropic/claude-opus-4.5`
  - `openai/gpt-5-codex`
  - `openai/gpt-5`
  - `openai/gpt-5-mini`
  - `openai/gpt-5-nano`
  - `moonshotai/kimi-k2-0905`
  - `z-ai/glm-4.6`
  - `minimax/minimax-m2`
  - `deepseek/deepseek-v3.2`

### 5. Codex (CodexOAuth)

- **定位**: ChatGPT 网页版的后端 API
- **特点**:
  - 使用 OpenAI 账户登录 (OAuth)
  - 相当于"免费"使用 ChatGPT 的后端
  - 目前只支持 `gpt-5.2` 模型
- **适用场景**: 有 ChatGPT Plus 订阅的用户
- **OAuth 配置**:
  - Client ID: `app_EMoamEEZ73f0CkXaXp7hrann`
  - OAuth Issuer: `https://auth.openai.com`
  - 回调端口: `1455`

### 6. Copilot

- **定位**: GitHub Copilot 的 AI API
- **特点**:
  - 使用 GitHub 账户登录 (OAuth)
  - 需要 GitHub Copilot 订阅
  - 支持多种模型 (OpenAI、Anthropic、Google、xAI)
- **适用场景**: 已有 GitHub Copilot 订阅的用户
- **支持的模型**:
  - OpenAI: `gpt-4.1`, `gpt-4o`, `gpt-5`, `gpt-5-mini`, `gpt-5-codex`, `gpt-5.1`, `gpt-5.2`, `o3`, `o3-mini`, `o4-mini`
  - Anthropic: `claude-3.5-sonnet`, `claude-3.7-sonnet`, `claude-haiku-4.5`, `claude-opus-4.5`, `claude-sonnet-4.5`
  - Google: `gemini-2.0-flash-001`, `gemini-2.5-pro`, `gemini-3-flash-preview`, `gemini-3-pro-preview`
  - xAI: `grok-code-fast-1`

## 关系图

```
┌─────────────────────────────────────────────────────────────────┐
│                        Model Loader                              │
│                                                                 │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │              get_model(name?)                            │   │
│   │                                                          │   │
│   │   name 前缀路由:                                          │   │
│   │   ├── "qwen/"        → Qwen API (阿里云 DashScope)       │   │
│   │   ├── "kimi/"        → Kimi API (月之暗面 Moonshot)      │   │
│   │   ├── "kimi-coding/" → Kimi Coding API (代码专用)        │   │
│   │   ├── "codex/"       → Codex OAuth (ChatGPT 后端)        │   │
│   │   ├── "copilot/"     → GitHub Copilot                    │   │
│   │   └── 其他           → OpenRouter 或配置文件中的模型      │   │
│   └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## 认证流程对比

### Qwen

```
API Key → 直接调用
└── 来源优先级:
    1. {cwd}/.moonclaw/moonclaw.json 中的配置
       - qwen_api_key 字段
       - env.QWEN_API_KEY
       - env.DASHSCOPE_API_KEY
    2. {home}/.moonclaw/moonclaw.json 中的配置
    3. 环境变量 QWEN_API_KEY
    4. 环境变量 DASHSCOPE_API_KEY
```

### Kimi

```
API Key → 直接调用
└── 来源优先级:
    1. {cwd}/.moonclaw/moonclaw.json 中的配置
       - kimi_api_key 字段
       - env.KIMI_API_KEY
       - env.MOONSHOT_API_KEY
    2. {home}/.moonclaw/moonclaw.json 中的配置
    3. 环境变量 KIMI_API_KEY
    4. 环境变量 MOONSHOT_API_KEY
```

### KimiCoding

```
API Key → 直接调用
└── 来源优先级:
    1. {cwd}/.moonclaw/moonclaw.json 中的配置
       - kimi_coding_api_key 字段
       - env.KIMI_CODING_API_KEY
    2. {home}/.moonclaw/moonclaw.json 中的配置
    3. 环境变量 KIMI_CODING_API_KEY
```

### OpenRouter

```
API Key → 直接调用
└── 来源优先级:
    1. {cwd}/.moonclaw/moonclaw.json 中的配置
       - api_key 字段
       - env.OPEN_ROUTER_API_KEY
       - env.OPENROUTER_API_KEY
    2. {home}/.moonclaw/moonclaw.json 中的配置
    3. 环境变量 OPENROUTER_API_KEY
    4. 环境变量 OPENAI_API_KEY
```

### Codex

```
OAuth 登录 → 获取 access_token → 调用 ChatGPT 后端
└── 登录流程:
    1. 启动本地服务器监听端口 1455
    2. 打开浏览器访问 OpenAI 认证页面
    3. 用户登录 OpenAI 账户
    4. 回调获取 access_token, refresh_token
    5. 保存凭证到 ~/.moonclaw/codex-credentials.json
```

### Copilot

```
OAuth 登录 → 获取 copilot_token → 调用 Copilot API
└── 登录流程:
    1. 请求 GitHub 设备码
    2. 用户在浏览器中输入设备码并授权
    3. 获取 GitHub access_token
    4. 使用 GitHub token 获取 Copilot API token
    5. 保存凭证到 ~/.moonclaw/copilot-credentials.json
```

## 配置文件格式

### .moonclaw/moonclaw.json

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

### .moonclaw/models/models.json

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

## 使用示例

### Qwen

```moonbit
// 使用 qwen/ 前缀
let model = @model.load(name="qwen/qwen3-coder-plus")
let model = @model.load(name="qwen/qwen-max")

// 或在配置文件中指定
// ~/.moonclaw/moonclaw.json
{
  "qwen_api_key": "sk-xxx"
}
```

### Kimi

```moonbit
// 使用 kimi/ 前缀
let model = @model.load(name="kimi/kimi-k2.5")
let model = @model.load(name="kimi/moonshot-v1-128k")

// 或在配置文件中指定
// ~/.moonclaw/moonclaw.json
{
  "kimi_api_key": "sk-xxx"
}
```

### KimiCoding

```moonbit
// 使用 kimi-coding/ 前缀
let model = @model.load(name="kimi-coding/k2p5")
let model = @model.load(name="kimi-coding/k2-0905")

// 或在配置文件中指定
// ~/.moonclaw/moonclaw.json
{
  "kimi_coding_api_key": "sk-xxx",
  "env": {
    "KIMI_CODING_API_KEY": "sk-xxx"
  }
}
```

### OpenRouter

```moonbit
// 使用环境变量或配置文件中的 API Key
let model = @model.load(name="anthropic/claude-sonnet-4.5")

// 或在配置文件中指定
// .moonclaw/models/models.json
[
  {
    "name": "my-model",
    "model_name": "anthropic/claude-sonnet-4.5",
    "model_type": "saas/openai",
    "api_key": "sk-or-xxx",
    "base_url": "https://openrouter.ai/api/v1"
  }
]
```

### Codex

```moonbit
// 使用 codex/ 前缀
let model = @model.load(name="codex/gpt-5.2")

// 首次使用会自动启动 OAuth 登录流程
```

### Copilot

```moonbit
// 使用 copilot/ 前缀
let model = @model.load(name="copilot/gpt-5.2")
let model = @model.load(name="copilot/claude-sonnet-4.5")

// 首次使用会自动启动 GitHub OAuth 登录流程
```

## 总结

| 类型 | 费用 | 认证 | 模型选择 | 国内可用 |
|------|------|------|----------|----------|
| **Qwen** | 按量付费 | API Key | 通义千问系列 | ✅ 是 |
| **Kimi** | 按量付费 | API Key | Kimi/Moonshot 系列 | ✅ 是 |
| **KimiCoding** | 按量付费 | API Key | Kimi 编码版 | ✅ 是 |
| **OpenRouter** | 按量付费 | API Key | 最多 (15+ 模型) | ❌ 否 |
| **Codex** | ChatGPT 订阅 | OAuth | 最少 (仅 gpt-5.2) | ❌ 否 |
| **Copilot** | Copilot 订阅 | OAuth | 较多 (20+ 模型) | ❌ 否 |

- **Qwen**、**Kimi** 和 **KimiCoding** 是国内可用的 API 服务，适合国内用户
- **KimiCoding** 是专为代码生成优化的 Kimi 版本
- **OpenRouter** 是独立的付费 API 服务，适合需要灵活切换模型的用户
- **Codex** 是 ChatGPT 订阅用户的"福利"，适合已有 ChatGPT Plus 订阅的用户
- **Copilot** 是 GitHub Copilot 订阅用户的"福利"，适合已有 Copilot 订阅的用户

后两者本质上是通过 OAuth 认证来"借用"已有订阅服务，而前四者是独立的付费 API 服务。
