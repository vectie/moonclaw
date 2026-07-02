# Agent 交互链路

本文档详细描述用户与 Moonclaw Agent 的完整交互链路，包括事件流、消息处理和工具调用流程。

## 架构概览

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              用户交互层                                      │
│                                                                             │
│   用户输入 ────────────────────────────────────────────────────────────────►│
│       │                                                                     │
│       ▼                                                                     │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │                    Interactive (交互式入口)                          │   │
│   │                                                                     │   │
│   │   - 解析命令行参数                                                   │   │
│   │   - 加载模型配置                                                     │   │
│   │   - 创建 Moonclaw 实例                                               │   │
│   │   - 注册事件监听器                                                   │   │
│   │   - 启动 Readline 循环                                               │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 核心组件

### 1. Moonclaw 结构体

```moonbit
pub struct Moonclaw {
  logger : @pino.Logger      // 日志记录器
  agent : @agent.Agent       // 核心代理实例
}
```

### 2. Agent 结构体

```moonbit
pub(all) struct Agent {
  uuid : @uuid.Generator                    // UUID 生成器
  cwd : String                              // 当前工作目录
  model : @model.Model                      // AI 模型配置
  logger : @pino.Logger                     // 日志记录器
  priv tools : Map[String, Tool]            // 已注册的工具
  priv history : @conversation.Conversation // 对话历史
  priv input_queue : Array[@ai.Message]     // 待发送消息队列
  priv pending_queue : @deque.Deque[QueuedMessage] // 待处理消息队列
  event_target : @broadcast.Broadcast[@event.Event] // 事件广播器
  priv token_counter : @token_counter.Counter // Token 计数器
  priv context_pruner : @context_pruner.Pruner // 上下文修剪器
  priv session_manager : @conversation.Manager // 会话管理器
  priv rules : @rules.Loader                // 规则加载器
  priv skills : @skills.Loader              // 技能加载器
  mut web_search : Bool                     // 是否启用网络搜索
  priv external_events : @event.ExternalEventQueue // 外部事件队列
}
```

## 完整交互流程

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           1. 初始化阶段                                      │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   interactive(args)                                                         │
│       │                                                                     │
│       ├──► 解析命令行参数                                                    │
│       │    ├── --prompt / -p : 初始提示                                     │
│       │    ├── --model / -m : 模型名称                                      │
│       │    ├── --web-search : 启用网络搜索                                  │
│       │    ├── --log-file : 日志文件路径                                    │
│       │    └── --resume / -r : 恢复会话 ID                                  │
│       │                                                                     │
│       ├──► @model.load(name?=model)                                         │
│       │    └──► 从配置文件/环境变量加载模型                                   │
│       │                                                                     │
│       └──► Moonclaw::new(model~, web_search~, logger?)                      │
│            │                                                                │
│            ├──► 生成系统提示词                                               │
│            │    └── [prelude, todo.prompt, search_files.prompt].join()      │
│            │                                                                │
│            ├──► Agent::new(model~, cwd~, system_message~, ...)              │
│            │    ├── 初始化 UUID 生成器                                       │
│            │    ├── 创建会话管理器                                           │
│            │    ├── 创建规则加载器                                           │
│            │    ├── 创建事件广播器                                           │
│            │    ├── 创建 Token 计数器                                        │
│            │    ├── 创建上下文修剪器                                         │
│            │    └── 创建外部事件队列                                         │
│            │                                                                │
│            └──► setup_agent(agent, cwd~)                                    │
│                 ├── 添加工具: execute_command, list_files, read_file        │
│                 ├── 添加工具: todo, search_files                            │
│                 └── 根据 model.supports_apply_patch 添加:                   │
│                      ├── apply_patch (GPT 5.1+)                             │
│                      └── write_to_file (其他模型)                            │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                           2. 事件监听注册                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   moonclaw.agent.add_listener(event => {                                    │
│     match event.desc {                                                      │
│       AssistantMessage(content, ..) =>                                      │
│         if !content.is_blank() { println(content) }                         │
│                                                                             │
│       PreToolCall(tool_call) =>                                             │
│         println("% \{tool_call.name} \{arguments}")                         │
│                                                                             │
│       PostToolCall(_, rendered~, ..) =>                                     │
│         println("> \{rendered}")                                            │
│                                                                             │
│       _ => ()                                                               │
│     }                                                                       │
│   })                                                                        │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                           3. 对话循环                                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   moonclaw.start(prompt?)                                                   │
│       │                                                                     │
│       ├──► queue_message(user_message)                                      │
│       │    └──► emit(MessageQueued(id~))                                    │
│       │                                                                     │
│       └──► agent.start()                                                    │
│            │                                                                │
│            ├──► emit(PreConversation)                                       │
│            │                                                                │
│            └──► while true {                                                │
│                 │                                                           │
│                 ├──► poll_external_events()                                 │
│                 │    ├── Cancelled → break                                  │
│                 │    └── UserMessage → push to input_queue                  │
│                 │                                                           │
│                 ├──► 从 pending_queue 取出消息                              │
│                 │    └──► emit(MessageUnqueued, UserMessage)                │
│                 │                                                           │
│                 ├──► prepare_messages_for_request()                         │
│                 │    ├── 计算需要修剪的事件                                  │
│                 │    ├── emit(TokenCounted)                                 │
│                 │    ├── emit(Pruned) for each pruned event                 │
│                 │    ├── emit(ContextPruned)                                │
│                 │    ├── 加载 skills 和 rules                               │
│                 │    └── 应用 prompt caching                                │
│                 │                                                           │
│                 ├──► @openai.chat(model, messages, tools)                   │
│                 │    └──► 调用 AI API                                        │
│                 │                                                           │
│                 ├──► emit(AssistantMessage(usage, tool_calls, content))     │
│                 │                                                           │
│                 ├──► token_counter.calibrate()                              │
│                 │                                                           │
│                 ├──► session_manager.save(history)                          │
│                 │                                                           │
│                 └──► for call in tool_calls {                               │
│                      execute_tool(call)                                     │
│                      └──► push result to input_queue                        │
│                    }                                                        │
│               }                                                             │
│                                                                             │
│            emit(PostConversation)                                           │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 事件生命周期

### 事件类型 (EventDesc)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           事件类型详解                                       │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   会话生命周期事件:                                                          │
│   ├── PreConversation     - 会话开始                                        │
│   └── PostConversation    - 会话结束                                        │
│                                                                             │
│   消息事件:                                                                  │
│   ├── MessageQueued(id)   - 消息加入待处理队列                               │
│   ├── MessageUnqueued(id) - 消息从待处理队列取出                             │
│   ├── UserMessage(content)- 用户发送即时消息                                 │
│   └── AssistantMessage(usage, tool_calls, content) - AI 响应消息            │
│                                                                             │
│   工具事件:                                                                  │
│   ├── ToolAdded(desc)     - 工具被添加到 Agent                               │
│   ├── PreToolCall(call)   - 工具调用前                                       │
│   └── PostToolCall(call, result, rendered) - 工具调用后                     │
│                                                                             │
│   Token 管理事件:                                                            │
│   ├── TokenCounted(count) - Token 计数完成                                  │
│   ├── ContextPruned(origin, pruned) - 上下文修剪                            │
│   └── Pruned(id)          - 事件被修剪                                       │
│                                                                             │
│   系统事件:                                                                  │
│   ├── ModelLoaded(name)   - 模型加载完成                                    │
│   ├── SystemPromptSet(prompt) - 系统提示词设置                              │
│   ├── Cancelled           - 用户取消                                        │
│   └── Failed(error)       - 发生错误                                        │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 事件流程图

```
用户输入
    │
    ▼
MessageQueued ──────────────────────────────────────────────────────────────►
    │
    ▼
PreConversation ─────────────────────────────────────────────────────────────►
    │
    ▼
MessageUnqueued ─────────────────────────────────────────────────────────────►
    │
    ▼
UserMessage ──────────────────────────────────────────────────────────────────►
    │
    ▼
TokenCounted ─────────────────────────────────────────────────────────────────►
    │
    ▼
ContextPruned (如果需要) ─────────────────────────────────────────────────────►
    │
    ▼
[API 调用] ───────────────────────────────────────────────────────────────────►
    │
    ▼
AssistantMessage ─────────────────────────────────────────────────────────────►
    │
    ├──► 无工具调用 ──► PostConversation
    │
    └──► 有工具调用 ──► PreToolCall ──► [执行工具] ──► PostToolCall ──► 循环
```

## 工具执行流程

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           工具执行流程                                       │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   1. AI 返回 tool_calls                                                     │
│      │                                                                      │
│      ▼                                                                      │
│   2. emit(PreToolCall(tool_call))                                          │
│      │                                                                      │
│      ▼                                                                      │
│   3. execute_tool(tool_call)                                               │
│      │                                                                      │
│      ├──► execute_command  - 执行 shell 命令                                │
│      ├──► list_files       - 列出目录文件                                   │
│      ├──► read_file        - 读取文件内容                                   │
│      ├──► write_to_file    - 写入文件                                       │
│      ├──► apply_patch      - 应用补丁                                       │
│      ├──► search_files     - 搜索文件                                       │
│      └──► todo             - 任务管理                                       │
│      │                                                                      │
│      ▼                                                                      │
│   4. emit(PostToolCall(tool_call, result, rendered))                       │
│      │                                                                      │
│      ▼                                                                      │
│   5. 将结果加入 input_queue，等待下一轮 API 调用                            │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 外部事件处理

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           外部事件处理                                       │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   external_events.poll()                                                    │
│       │                                                                     │
│       ├──► Cancelled                                                        │
│       │    └──► agent.cancel() → 清空 input_queue → 结束会话                │
│       │                                                                     │
│       ├──► UserMessage(msg)                                                 │
│       │    └──► push 到 input_queue (高优先级，立即处理)                     │
│       │                                                                     │
│       └──► Diagnostics                                                      │
│            └──► 添加诊断信息到上下文                                         │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Readline 交互

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           Readline 交互循环                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   // 后台任务: 处理用户输入                                                  │
│   group.spawn_bg(() => {                                                    │
│     for {                                                                   │
│       rl.start() catch {                                                    │
│         CtrlC =>                                                            │
│           if task is Some(round) {                                          │
│             round.cancel()           // 取消当前任务                        │
│             clear_inputs_and_prompt() // 恢复输入                           │
│           } else {                                                          │
│             println("")                                                     │
│             rl.set_prompt("$ ")                                             │
│             rl.prompt()              // 重新提示                             │
│           }                                                                 │
│         error => raise error                                                │
│       }                                                                     │
│     }                                                                       │
│   })                                                                        │
│                                                                             │
│   // 主循环: 处理消息                                                        │
│   while true {                                                              │
│     rl.set_prompt("$ ")                                                     │
│     rl.prompt()                                                             │
│     let prompt = rl.read_line()                                             │
│     let round = group.spawn(() => {                                         │
│       moonclaw.start(prompt~)                                               │
│     })                                                                      │
│     round.wait()                                                            │
│   }                                                                         │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 输出格式

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           输出格式说明                                       │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   $ 用户输入                                                                │
│                                                                             │
│   AI 响应内容...                                                            │
│                                                                             │
│   % tool_name {"arg1": "value1", "arg2": "value2"}  // 工具调用前           │
│                                                                             │
│   > 工具执行结果...                                  // 工具调用后           │
│                                                                             │
│   ! 错误信息                                         // 错误输出             │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 数据持久化

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           数据持久化                                         │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   .moonsuite/products/moonclaw/                                             │
│   ├── logs/log.jsonl               // Agent 日志                            │
│   ├── moonclaw.json                // 配置文件 (API Keys 等)                │
│   ├── credentials/codex-credentials.json    // Codex OAuth 凭证             │
│   ├── credentials/copilot-credentials.json  // Copilot OAuth 凭证           │
│   └── conversations/                                                       │
│       └── {uuid}.json              // 会话历史                              │
│                                                                             │
│   .moonsuite/products/moonclaw/models/                                      │
│   └── models.json                  // 工作区模型配置                        │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 总结

用户与 Agent 的交互链路可以概括为以下步骤：

1. **初始化**: 加载配置、创建 Agent 实例、注册工具
2. **事件监听**: 注册事件处理器，用于输出 AI 响应和工具执行结果
3. **消息队列**: 用户输入被加入待处理队列
4. **对话循环**:
   - 轮询外部事件
   - 准备消息 (Token 计数、上下文修剪)
   - 调用 AI API
   - 处理响应 (输出内容或执行工具)
5. **工具执行**: 执行工具调用，返回结果给 AI
6. **持久化**: 保存会话历史和日志

整个交互过程是异步的，支持取消、中断和恢复，具有良好的用户体验。
