# MoonClaw 系统架构分析

## 一、系统概述

MoonClaw 是一个用 MoonBit 编写的 **AI 编程助手框架**，提供交互式对话、工具执行、多模型支持等功能。

## 二、核心模块结构

```
┌─────────────────────────────────────────────────────────────────────┐
│                         cmd/main/main.mbt                            │
│                         (命令行入口)                                  │
└─────────────────────────────────────────────────────────────────────┘
                                  │
        ┌───────────┬─────────────┼─────────────┬───────────┐
        ▼           ▼             ▼             ▼           ▼
┌───────────┐ ┌───────────┐ ┌───────────┐ ┌───────────┐ ┌───────────┐
│interactive│ │    tui    │ │  daemon   │ │  gateway  │ │   server  │
│ (简单CLI) │ │ (终端UI)  │ │(全功能服务)│ │(轻量服务) │ │ (HTTP API)│
└───────────┘ └───────────┘ └───────────┘ └───────────┘ └───────────┘
        │           │             │             │
        └───────────┴──────┬──────┴─────────────┘
                           ▼
┌─────────────────────────────────────────────────────────────────────┐
│                         moonclaw.mbt                                 │
│                       (Moonclaw 主类)                                │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  setup_agent() → 配置工具集                                   │   │
│  │  new() / resume_() → 创建/恢复 Agent                         │   │
│  │  start() → 启动对话循环                                       │   │
│  └─────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────────┐
│                         agent/agent.mbt                              │
│                         (Agent 核心)                                 │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  消息队列: input_queue, pending_queue                        │   │
│  │  对话历史: history (@conversation.Conversation)              │   │
│  │  工具注册: tools (Map[String, Tool])                         │   │
│  │  事件广播: event_target (@broadcast.Broadcast)               │   │
│  │  Token 管理: token_counter, context_pruner                   │   │
│  └─────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
        │
        ├──────────────────┬──────────────────┬──────────────────┐
        ▼                  ▼                  ▼                  ▼
┌───────────────┐  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐
│ model/loader  │  │  tool/tool    │  │  ai/message   │  │ event/event   │
│  (模型加载)    │  │  (工具定义)    │  │  (消息类型)    │  │  (事件系统)    │
└───────────────┘  └───────────────┘  └───────────────┘  └───────────────┘
```

## 三、运行模式对比

MoonClaw 提供五种运行模式，适用于不同场景：

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           运行模式架构图                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │                        本地使用模式                                   │  │
│   │  ┌─────────────────┐          ┌─────────────────────────────────┐   │  │
│   │  │   interactive   │          │              tui                │   │  │
│   │  │   (简单 CLI)    │          │         (终端 UI)               │   │  │
│   │  │                 │          │                                 │   │  │
│   │  │ - 快速测试      │          │ - 实时状态显示                   │   │  │
│   │  │ - 脚本集成      │          │ - 工具调用折叠/展开              │   │  │
│   │  │ - 管道输入      │          │ - 活动状态指示                   │   │  │
│   │  │                 │          │ - 命令支持 (/clear, /help)       │   │  │
│   │  └─────────────────┘          └─────────────────────────────────┘   │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │                        服务模式                                       │  │
│   │  ┌─────────────────┐          ┌─────────────────────────────────┐   │  │
│   │  │     daemon      │          │            gateway              │   │  │
│   │  │  (全功能服务)   │          │         (轻量服务)              │   │  │
│   │  │                 │          │                                 │   │  │
│   │  │ - OAuth 认证    │          │ - SSE 事件流                    │   │  │
│   │  │ - 会话持久化    │          │ - 幂等请求                      │   │  │
│   │  │ - 进程管理      │          │ - 简单架构                      │   │  │
│   │  │ - 生产就绪      │          │ - 适合自定义客户端              │   │  │
│   │  │                 │          │                                 │   │  │
│   │  │ 端口: 8090      │          │ 端口: 18789                     │   │  │
│   │  └─────────────────┘          └─────────────────────────────────┘   │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │                        HTTP API 模式                                 │  │
│   │  ┌─────────────────────────────────────────────────────────────┐   │  │
│   │  │                      server                                  │   │  │
│   │  │                   (HTTP API 服务)                            │   │  │
│   │  │                                                              │   │  │
│   │  │ - RESTful API                                                │   │  │
│   │  │ - WebSocket 支持                                             │   │  │
│   │  │ - 适合 Web 前端集成                                          │   │  │
│   │  └─────────────────────────────────────────────────────────────┘   │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 模式对比表

| 特性 | interactive | tui | daemon | gateway | server |
|------|-------------|-----|--------|---------|--------|
| **用途** | 简单 CLI | 终端 UI | 全功能服务 | 轻量服务 | HTTP API |
| **实时状态** | ❌ | ✅ | ❌ | ✅ (SSE) | ✅ |
| **OAuth 认证** | ❌ | ❌ | ✅ | ❌ | ❌ |
| **会话持久化** | ✅ | ✅ | ✅ | 基础 | ❌ |
| **进程管理** | ❌ | ❌ | ✅ | ❌ | ❌ |
| **外部客户端** | ❌ | ❌ | ✅ | ✅ | ✅ |
| **复杂度** | 低 | 中 | 高 | 中 | 中 |
| **默认端口** | - | - | 8090 | 18789 | 8080 |

### 使用场景

| 场景 | 推荐模式 |
|------|---------|
| 快速测试、脚本集成 | `interactive` |
| 本地开发、日常使用 | `tui` |
| 生产环境、需要 OAuth | `daemon` |
| 自定义客户端、Web UI | `gateway` |
| Web 前端集成 | `server` |

## 四、完整调用链

```
用户输入
    │
    ▼
cmd/main/main.mbt::main()
    │
    ├── 解析命令行参数
    │
    └── 调用对应子命令
            │
            ├── interactive ──────────────────────────────────────────┐
            │       │                                                   │
            │       ├── model::load() → 加载模型配置                    │
            │       │       │                                           │
            │       │       └── model/loader.mbt::Loader::get_model()  │
            │       │               ├── 从 ~/.moonclaw/models/models.json 加载
            │       │               ├── 从 ./.moonclaw/models/models.json 加载
            │       │               ├── 支持 providers 配置
            │       │               └── 自动检测 API 密钥
            │       │                                                   │
            │       ├── Moonclaw::new() → 创建实例                      │
            │       │       │                                           │
            │       │       ├── 加载 system prompt                      │
            │       │       │       ├── @prompt.prelude                 │
            │       │       │       ├── @todo.prompt                    │
            │       │       │       └── @search_files.prompt            │
            │       │       │                                           │
            │       │       ├── Agent::new() → 初始化 Agent             │
            │       │       │       ├── Conversation::new()             │
            │       │       │       ├── TokenCounter::new()             │
            │       │       │       ├── ContextPruner::new()            │
            │       │       │       └── EventTarget::new()              │
            │       │       │                                           │
            │       │       └── setup_agent() → 注册工具                │
            │       │               ├── @execute_command.new()          │
            │       │               ├── @list_files.new()               │
            │       │               ├── @read_file.new()                │
            │       │               ├── @todo.new_tool()                │
            │       │               ├── @search_files.new()             │
            │       │               └── @write_to_file / @apply_patch   │
            │       │                                                   │
            │       └── moonclaw.start(prompt)                          │
            │               │                                           │
            │               └── Agent::start()                          │
            │                                                           │
            ├── tui ───────────────────────────────────────────────────┤
            │       │                                                   │
            │       ├── 同 interactive 创建 Moonclaw 实例              │
            │       │                                                   │
            │       ├── TUI::new() → 初始化终端 UI                      │
            │       │       ├── terminal (终端管理)                     │
            │       │       ├── chat_log (聊天记录组件)                 │
            │       │       ├── editor (输入编辑器)                     │
            │       │       └── state (状态管理)                        │
            │       │                                                   │
            │       ├── 注册事件监听器 → 更新 UI                        │
            │       │       ├── AssistantMessage → 更新助手消息         │
            │       │       ├── PreToolCall → 显示工具调用开始          │
            │       │       ├── PostToolCall → 显示工具调用结果         │
            │       │       └── TokenCounted → 显示 token 计数          │
            │       │                                                   │
            │       └── tui.run_event_loop() → 运行事件循环             │
            │                                                           │
            ├── daemon ────────────────────────────────────────────────┤
            │       │                                                   │
            │       ├── Daemon::new() → 创建守护进程                   │
            │       │       ├── HTTP Server (@httpx.Server)            │
            │       │       ├── Process Manager (@spawn.Manager)       │
            │       │       ├── Conversation Manager                   │
            │       │       └── OAuth Providers (Codex, Copilot)       │
            │       │                                                   │
            │       ├── 获取锁文件 (~/.moonclaw/daemon.json)           │
            │       │                                                   │
            │       └── daemon.serve() → 启动 HTTP 服务                 │
            │               ├── POST /rpc → RPC 端点                   │
            │               ├── OAuth 端点                             │
            │               └── 任务管理端点                           │
            │                                                           │
            ├── gateway ───────────────────────────────────────────────┤
            │       │                                                   │
            │       ├── Gateway::new() → 创建网关服务                  │
            │       │       ├── HTTP Server (@httpx.Server)            │
            │       │       ├── Agent Runs Map (后台任务)              │
            │       │       ├── Session Manager                        │
            │       │       └── Dedupe Cache (幂等性)                  │
            │       │                                                   │
            │       └── gateway.start() → 启动服务                      │
            │               ├── GET / → 信息面板                        │
            │               ├── GET /health → 健康检查                 │
            │               ├── GET /v1/events → SSE 事件流            │
            │               ├── GET /v1/runs → 列出运行                 │
            │               ├── POST /v1/agent → 提交任务              │
            │               └── POST /v1/rpc → RPC 端点                │
            │                                                           │
            └── server ────────────────────────────────────────────────┘
                    │
                    ├── HTTP Server 创建
                    │
                    └── RESTful API 端点
```

## 五、Agent 核心执行循环

```moonbit
// agent/agent.mbt::Agent::start()
pub async fn Agent::start(agent : Agent) -> Unit {
  @async.with_task_group(group => {
    // 1. 启动事件处理
    let session = agent.event_target.spawn_in(group)
    
    // 2. 发出对话开始事件
    agent.emit(PreConversation)
    
    while true {
      // 3. 轮询外部事件（取消、即时消息等）
      guard agent.poll_external_events() else { break }
      
      // 4. 从队列获取消息
      if agent.pending_queue.pop_front() is Some(msg) {
        agent.input_queue.push(msg.message)
        agent.emit(MessageUnqueued(id=msg.id))
      }
      
      if agent.input_queue.is_empty() { break }
      
      // 5. 准备 API 请求
      let (cache_messages, estimated_tokens) = agent.prepare_messages_for_request(tools~)
      
      // 6. 调用 LLM API
      let response = @openai.chat(
        model=agent.model,
        messages=cache_messages,
        tools=tools.map(x => x.to_openai()),
      )
      
      // 7. 发出助手消息事件
      agent.emit(AssistantMessage(...))
      
      // 8. 校准 token 计数器
      agent.token_counter.calibrate(...)
      
      // 9. 执行工具调用
      for call in message.tool_calls {
        agent.input_queue.push(
          agent.execute_tool(@ai.ToolCall::from_openai_tool_call(call))
        )
      }
    }
    
    // 10. 发出对话结束事件
    agent.emit(PostConversation)
  })
}
```

## 六、模块交互图

```
┌─────────────────────────────────────────────────────────────────────┐
│                              Agent                                   │
│  ┌───────────────────────────────────────────────────────────────┐ │
│  │                        消息处理流程                             │ │
│  │                                                                 │ │
│  │   User Message ──► input_queue ──► prepare_messages()          │ │
│  │                                              │                  │ │
│  │                                              ▼                  │ │
│  │                                    context_pruner              │ │
│  │                                    (token 裁剪)                │ │
│  │                                              │                  │ │
│  │                                              ▼                  │ │
│  │                                    @openai.chat()              │ │
│  │                                    (调用 LLM API)              │ │
│  │                                              │                  │ │
│  │                              ┌───────────────┴───────────────┐ │ │
│  │                              ▼                               ▼ │ │
│  │                        text response                   tool_calls │
│  │                              │                               │   │ │
│  │                              ▼                               ▼   │ │
│  │                        emit event                    execute_tool()│
│  │                                                          │     │ │
│  │                                                          ▼     │ │
│  │                                                    Tool Result │ │
│  │                                                          │     │ │
│  │                                                          ▼     │ │
│  │                                                    input_queue │ │
│  │                                                    (继续循环)  │ │
│  └───────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
        │
        │ 交互
        ▼
┌───────────────┐  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐
│    Model      │  │    Tool       │  │ Conversation  │  │    Event      │
│               │  │               │  │               │  │               │
│ - api_key     │  │ - desc        │  │ - history     │  │ - EventTarget │
│ - base_url    │  │ - f (执行函数) │  │ - session_mgr │  │ - Broadcast   │
│ - model_name  │  │ - schema      │  │ - save/load   │  │ - listeners   │
│ - model_type  │  │               │  │               │  │               │
└───────────────┘  └───────────────┘  └───────────────┘  └───────────────┘
        │                  │
        │                  │
        ▼                  ▼
┌───────────────┐  ┌───────────────┐
│    Loader     │  │    Tools      │
│               │  │               │
│ - load()      │  │ - execute_cmd │
│ - providers   │  │ - read_file   │
│ - models      │  │ - write_file  │
│ - api_keys    │  │ - search      │
└───────────────┘  │ - todo        │
                   └───────────────┘
```

## 七、关键数据结构

### 1. Agent 结构

```moonbit
pub(all) struct Agent {
  uuid : @uuid.Generator
  cwd : String
  model : @model.Model
  logger : @pino.Logger
  priv tools : Map[String, Tool]
  priv history : @conversation.Conversation
  priv mut input_queue : Array[@ai.Message]
  priv pending_queue : @deque.Deque[QueuedMessage]
  event_target : @broadcast.Broadcast[@event.Event]
  priv token_counter : @token_counter.Counter
  priv context_pruner : @context_pruner.Pruner
  priv session_manager : @conversation.Manager
  priv rules : @rules.Loader
  priv skills : @skills.Loader
  mut web_search : Bool
  priv external_events : @event.ExternalEventQueue
}
```

### 2. Model 结构

```moonbit
pub struct Model {
  name : String
  model_name : String
  model_type : Type
  api_key : String
  base_url : String
  safe_zone_tokens : Int
  supports_anthropic_prompt_caching : Bool
  supports_apply_patch : Bool
  // OAuth credentials
  access_token : String?
  refresh_token : String?
  ...
}
```

### 3. Tool 结构

```moonbit
pub struct Tool[Output] {
  desc : ToolDesc
  priv f : ToolFn[Output]
}

pub struct ToolDesc {
  description : String
  name : String
  schema : JsonSchema
}
```

## 八、使用方式

### 1. 命令行模式

```bash
# 简单交互模式
moonclaw
moonclaw --model qwen/qwen3-coder-plus --prompt "帮我分析这个项目"

# TUI 模式 (推荐本地使用)
moonclaw --tui
moonclaw --tui --model qwen/qwen3-coder-plus

# Daemon 模式 (生产环境)
moonclaw daemon --port 8090 --detach
moonclaw daemon --serve /path/to/workspace

# Gateway 模式 (自定义客户端)
moonclaw gateway start --port 18789
moonclaw gateway connect --url http://localhost:18789
moonclaw gateway agent --message "Hello" --wait

# Server 模式 (HTTP API)
moonclaw server --port 8080
```

### 2. 编程接口

```moonbit
// 创建 Agent
let moonclaw = @moonclaw.Moonclaw::new(
  model~,
  cwd~,
  web_search~=false,
)

// 添加事件监听
moonclaw.agent.add_listener(event => {
  match event.desc {
    AssistantMessage(content, ..) => println(content)
    PreToolCall(tool_call) => println("% \{tool_call.name}")
    PostToolCall(_, rendered~, ..) => println("> \{rendered}")
    _ => ()
  }
})

// 启动对话
moonclaw.start(prompt~)
```

## 九、与 RL 改造的关系

当前系统结构对 RL 改造的影响：

| 当前组件 | RL 改造需求 | 改造难度 |
|---------|-----------|---------|
| `Agent::start()` | 需要记录轨迹 | 中等 - 需要在关键点注入记录逻辑 |
| `execute_tool()` | 需要记录奖励 | 低 - 已有事件系统 |
| `Conversation` | 需要扩展为 `Trajectory` | 中等 - 需要添加 reward/logprob 字段 |
| `Event` 系统 | 可以复用 | 低 - 已有完整的事件广播机制 |
| `Model` | 需要支持 logprob 返回 | 低 - OpenAI API 已支持 |

### 关键改造点

1. 在 `Agent::start()` 循环中注入轨迹记录
2. 扩展 `Step` 数据结构以包含 reward/logprob
3. 实现奖励函数注入机制
4. 添加轨迹导出功能

这些改造可以在不破坏现有架构的前提下完成，因为 MoonClaw 已经有良好的模块化设计和事件系统。

## 十、文件路径参考

| 模块 | 文件路径 | 说明 |
|------|---------|------|
| 入口 | `cmd/main/main.mbt` | 命令行入口 |
| 主类 | `moonclaw.mbt` | Moonclaw 主类 |
| Agent | `agent/agent.mbt` | Agent 核心实现 |
| 模型加载 | `model/loader.mbt` | 模型配置加载 |
| 模型定义 | `model/model.mbt` | Model 数据结构 |
| 工具定义 | `tool/tool.mbt` | Tool 数据结构 |
| 消息类型 | `ai/message.mbt` | Message 数据结构 |
| 事件系统 | `event/event.mbt` | Event 定义 |
| 交互模式 | `cmd/main/interactive/interactive.mbt` | 简单 CLI |
| TUI 模式 | `cmd/main/tui/tui.mbt` | 终端 UI |
| 守护进程 | `cmd/daemon/daemon.mbt` | 全功能服务 |
| 网关服务 | `cmd/gateway/main.mbt` | 轻量服务 |
| HTTP 服务 | `cmd/server/main.mbt` | HTTP API |
| TUI 组件 | `internal/tui/tui.mbt` | TUI 组件实现 |
| Gateway 服务端 | `gateway/server/gateway.mbt` | Gateway 服务实现 |
| Gateway 客户端 | `gateway/client/client.mbt` | Gateway 客户端 |
| Gateway 协议 | `gateway/protocol/payloads.mbt` | Gateway 协议定义 |
