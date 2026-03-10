# 多 Agent 协作设计方案

## 一、当前能力分析

### 1.1 已有功能

| 功能 | 实现位置 | 说明 |
|------|---------|------|
| 异步执行 | `handler.mbt::handle_agent` | 返回 202 Accepted，后台执行 |
| 并发执行 | `@async.spawn_bg` | 多个 Agent 可同时运行 |
| 状态追踪 | `agent_runs: Map[String, AgentRun]` | 记录所有运行状态 |
| 事件流 | `agent_events: Broadcast` | SSE 订阅所有 Agent 事件 |
| 幂等性 | `dedupe: DedupeCache` | 防止重复执行 |

### 1.2 缺失功能

| 功能 | 说明 | 优先级 |
|------|------|--------|
| Agent 间通信 | Agent 之间发送/接收消息 | 高 |
| 任务协调 | 主 Agent 分配任务给子 Agent | 高 |
| 结果汇总 | 收集多个 Agent 的结果 | 高 |
| 并发限制 | 最大并发数控制 | 中 |
| 优先级队列 | 任务优先级排序 | 低 |

## 二、多 Agent 协作场景设计

### 2.1 场景一：并行任务执行

```
┌─────────────────────────────────────────────────────────────┐
│                        Gateway                               │
│                                                              │
│  POST /v1/agent  ──────────────────────────────────────────┐│
│  { "message": "分析这三个文件", "files": ["a.py", "b.py", "c.py"] }
│                                                             ││
│                              ▼                              ││
│  ┌─────────────────────────────────────────────────────┐   ││
│  │              Coordinator Agent                       │   ││
│  │  1. 解析任务：拆分为 3 个子任务                       │   ││
│  │  2. 创建 3 个子 Agent                                │   ││
│  │  3. 分配任务                                         │   ││
│  │  4. 等待结果                                         │   ││
│  │  5. 汇总结果                                         │   ││
│  └─────────────────────────────────────────────────────┘   ││
│                              │                              ││
│              ┌───────────────┼───────────────┐             ││
│              ▼               ▼               ▼             ││
│        ┌─────────┐     ┌─────────┐     ┌─────────┐        ││
│        │ Agent A │     │ Agent B │     │ Agent C │        ││
│        │ 分析a.py│     │ 分析b.py│     │ 分析c.py│        ││
│        └─────────┘     └─────────┘     └─────────┘        ││
│              │               │               │             ││
│              └───────────────┼───────────────┘             ││
│                              ▼                              ││
│                    汇总结果返回                             ││
└─────────────────────────────────────────────────────────────┘
```

### 2.2 场景二：流水线处理

```
┌─────────────────────────────────────────────────────────────┐
│                        Gateway                               │
│                                                              │
│  POST /v1/pipeline                                          │
│  {                                                          │
│    "stages": [                                              │
│      { "agent": "reader", "input": "read file" },          │
│      { "agent": "analyzer", "input": "$stage1.output" },   │
│      { "agent": "writer", "input": "$stage2.output" }      │
│    ]                                                        │
│  }                                                          │
│                                                              │
│  ┌──────────┐     ┌──────────┐     ┌──────────┐           │
│  │  Reader  │ ──▶ │ Analyzer │ ──▶ │  Writer  │           │
│  │  Agent   │     │  Agent   │     │  Agent   │           │
│  └──────────┘     └──────────┘     └──────────┘           │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 2.3 场景三：Agent 间通信

```
┌─────────────────────────────────────────────────────────────┐
│                        Gateway                               │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Agent Communication Bus                 │   │
│  │                                                      │   │
│  │   Agent A ◄────────────────────────► Agent B        │   │
│  │      │                                │              │   │
│  │      │         Message Queue          │              │   │
│  │      │    ┌──────────────────┐        │              │   │
│  │      └───▶│  topic: "chat"   │◀───────┘              │   │
│  │           │  topic: "tasks"  │                       │   │
│  │           │  topic: "results"│                       │   │
│  │           └──────────────────┘                       │   │
│  │                    │                                 │   │
│  │                    ▼                                 │   │
│  │              Agent C (订阅所有)                       │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## 三、实现方案

### 3.1 新增数据结构

```moonbit
// Agent 通信消息
pub struct AgentMessage {
  from_agent : String
  to_agent : String?
  topic : String
  payload : Json
  timestamp : Int
} derive(ToJson, FromJson)

// Agent 邮箱
pub struct AgentMailbox {
  agent_id : String
  messages : @aqueue.Queue[AgentMessage]
}

// 协调任务
pub struct CoordinationTask {
  task_id : String
  parent_agent : String
  child_agents : Array[String]
  status : String
  results : Map[String, Json]
  created_at : Int
  completed_at : Int?
} derive(ToJson, FromJson)

// 流水线
pub struct Pipeline {
  pipeline_id : String
  stages : Array[PipelineStage]
  current_stage : Int
  status : String
  results : Array[Json]
} derive(ToJson, FromJson)

pub struct PipelineStage {
  name : String
  agent_config : AgentConfig
  input_template : String
} derive(ToJson, FromJson)
```

### 3.2 Gateway 扩展

```moonbit
pub struct Gateway {
  // ... 现有字段 ...
  
  // 新增：Agent 通信
  mailboxes : Map[String, AgentMailbox]
  message_bus : @broadcast.Broadcast[AgentMessage]
  
  // 新增：协调管理
  coordinations : Map[String, CoordinationTask]
  pipelines : Map[String, Pipeline]
  
  // 新增：并发控制
  max_concurrent_agents : Int
  active_agents : Int
}
```

### 3.3 新增 API 端点

```
POST /v1/agent/message     # Agent 发送消息
GET  /v1/agent/:id/messages # Agent 接收消息

POST /v1/coordinate         # 创建协调任务
GET  /v1/coordinate/:id     # 获取协调状态

POST /v1/pipeline           # 创建流水线
GET  /v1/pipeline/:id       # 获取流水线状态
```

## 四、实现步骤

### 阶段一：Agent 间通信（1 周）

1. 实现 `AgentMailbox` 和 `AgentMessage`
2. 在 Gateway 中添加 `message_bus`
3. 实现 `/v1/agent/message` 端点
4. Agent 可以订阅/发布消息

### 阶段二：协调任务（1 周）

1. 实现 `CoordinationTask`
2. 添加任务分配逻辑
3. 实现结果汇总
4. 添加 `/v1/coordinate` 端点

### 阶段三：流水线（1 周）

1. 实现 `Pipeline` 和 `PipelineStage`
2. 实现阶段间数据传递
3. 添加 `/v1/pipeline` 端点
4. 支持模板变量替换

## 五、测试场景

### 5.1 并行分析测试

```bash
# 启动 Gateway
moon run cmd/main -- gateway start --port 18789

# 发送并行任务
curl -X POST http://localhost:18789/v1/coordinate \
  -H "Content-Type: application/json" \
  -d '{
    "task_id": "analyze-1",
    "type": "parallel",
    "subtasks": [
      {"message": "分析文件 a.py", "model": "qwen/qwen3-coder-plus"},
      {"message": "分析文件 b.py", "model": "qwen/qwen3-coder-plus"},
      {"message": "分析文件 c.py", "model": "qwen/qwen3-coder-plus"}
    ]
  }'

# 获取结果
curl http://localhost:18789/v1/coordinate/analyze-1
```

### 5.2 流水线测试

```bash
# 创建流水线
curl -X POST http://localhost:18789/v1/pipeline \
  -H "Content-Type: application/json" \
  -d '{
    "pipeline_id": "code-review-1",
    "stages": [
      {"name": "read", "message": "读取文件 main.py"},
      {"name": "analyze", "message": "分析代码质量: $read.output"},
      {"name": "report", "message": "生成报告: $analyze.output"}
    ]
  }'

# 获取流水线状态
curl http://localhost:18789/v1/pipeline/code-review-1
```

## 六、文件结构

```
gateway/server/
├── gateway.mbt           # 主结构（扩展）
├── handler.mbt           # HTTP 处理器（扩展）
├── methods.mbt           # RPC 方法（扩展）
├── mailbox.mbt           # 新增：Agent 邮箱
├── message_bus.mbt       # 新增：消息总线
├── coordinator.mbt       # 新增：任务协调
├── pipeline.mbt          # 新增：流水线
└── concurrency.mbt       # 新增：并发控制
```
