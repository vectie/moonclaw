# 多 Agent 协作端到端测试用例

## 测试环境准备

```bash
# 启动 Gateway
moon run cmd/main -- gateway start --port 18789

# 验证 Gateway 启动
curl http://localhost:18789/health
# 预期: {"status": "ok"}
```

---

## 一、Agent 间通信测试

### 1.1 创建邮箱

**请求**：
```bash
curl -X POST http://localhost:18789/v1/mailbox \
  -H "Content-Type: application/json" \
  -d '{"agent_id": "agent-alice"}'
```

**预期响应** (201)：
```json
{
  "agent_id": "agent-alice",
  "config": {
    "max_size": 1000,
    "timeout_ms": 30000
  },
  "created_at": 1700000000000,
  "last_read_at": null,
  "message_count": 0
}
```

### 1.2 创建多个邮箱

**请求**：
```bash
curl -X POST http://localhost:18789/v1/mailbox -H "Content-Type: application/json" -d '{"agent_id": "agent-bob"}'
curl -X POST http://localhost:18789/v1/mailbox -H "Content-Type: application/json" -d '{"agent_id": "agent-carol"}'
```

**预期响应** (201)：类似 1.1

### 1.3 列出所有邮箱

**请求**：
```bash
curl http://localhost:18789/v1/mailboxes
```

**预期响应** (200)：
```json
{
  "mailbox_count": 3,
  "agents": ["agent-alice", "agent-bob", "agent-carol"]
}
```

### 1.4 发送点对点消息

**请求**：
```bash
curl -X POST http://localhost:18789/v1/agent/message \
  -H "Content-Type: application/json" \
  -d '{
    "from_agent": "agent-alice",
    "to_agent": "agent-bob",
    "topic": "task_request",
    "payload": {"task": "analyze_file", "file": "main.py"}
  }'
```

**预期响应** (200)：
```json
{
  "message_id": "uuid-xxx",
  "delivered": 1
}
```

### 1.5 接收消息

**请求**：
```bash
curl http://localhost:18789/v1/agent/agent-bob/messages
```

**预期响应** (200)：
```json
{
  "agent_id": "agent-bob",
  "messages": [
    {
      "message_id": "uuid-xxx",
      "from_agent": "agent-alice",
      "to_agent": "agent-bob",
      "topic": "task_request",
      "payload": {"task": "analyze_file", "file": "main.py"},
      "timestamp": 1700000001000
    }
  ]
}
```

### 1.6 发送广播消息

**请求**：
```bash
curl -X POST http://localhost:18789/v1/agent/message \
  -H "Content-Type: application/json" \
  -d '{
    "from_agent": "agent-alice",
    "topic": "broadcast",
    "payload": {"message": "Hello everyone!"}
  }'
```

**预期响应** (200)：
```json
{
  "message_id": "uuid-yyy",
  "delivered": 2
}
```

**验证**：
```bash
# agent-bob 应收到消息
curl http://localhost:18789/v1/agent/agent-bob/messages

# agent-carol 应收到消息
curl http://localhost:18789/v1/agent/agent-carol/messages
```

### 1.7 删除邮箱

**请求**：
```bash
curl -X DELETE http://localhost:18789/v1/mailbox/agent-carol
```

**预期响应** (200)：
```json
{
  "deleted": true,
  "agent_id": "agent-carol"
}
```

### 1.8 错误场景测试

**重复创建邮箱**：
```bash
curl -X POST http://localhost:18789/v1/mailbox \
  -H "Content-Type: application/json" \
  -d '{"agent_id": "agent-alice"}'
```
**预期响应** (409)：
```json
{
  "error": {
    "code": "mailbox_exists",
    "message": "Mailbox already exists for agent: agent-alice"
  }
}
```

**获取不存在的邮箱消息**：
```bash
curl http://localhost:18789/v1/agent/unknown-agent/messages
```
**预期响应** (404)：
```json
{
  "error": {
    "code": "mailbox_not_found",
    "message": "Mailbox not found for agent: unknown-agent"
  }
}
```

---

## 二、协调任务测试

### 2.1 创建协调任务

**请求**：
```bash
curl -X POST http://localhost:18789/v1/coordination \
  -H "Content-Type: application/json" \
  -d '{
    "parent_agent": "coordinator-1",
    "subtasks": [
      {"task_id": "task-a", "message": "分析文件 a.py"},
      {"task_id": "task-b", "message": "分析文件 b.py"},
      {"task_id": "task-c", "message": "分析文件 c.py"}
    ]
  }'
```

**预期响应** (201)：
```json
{
  "coordination_id": "uuid-coord-1",
  "parent_agent": "coordinator-1",
  "subtasks": [
    {
      "task_id": "task-a",
      "message": "分析文件 a.py",
      "model": null,
      "cwd": null,
      "status": "Pending",
      "result": null,
      "error": null,
      "created_at": 1700000000000,
      "started_at": null,
      "completed_at": null
    },
    {
      "task_id": "task-b",
      "message": "分析文件 b.py",
      "model": null,
      "cwd": null,
      "status": "Pending",
      "result": null,
      "error": null,
      "created_at": 1700000000000,
      "started_at": null,
      "completed_at": null
    },
    {
      "task_id": "task-c",
      "message": "分析文件 c.py",
      "model": null,
      "cwd": null,
      "status": "Pending",
      "result": null,
      "error": null,
      "created_at": 1700000000000,
      "started_at": null,
      "completed_at": null
    }
  ],
  "status": "Pending",
  "results": {},
  "created_at": 1700000000000,
  "started_at": null,
  "completed_at": null,
  "metadata": {}
}
```

### 2.2 列出协调任务

**请求**：
```bash
curl http://localhost:18789/v1/coordination
```

**预期响应** (200)：
```json
{
  "total": 1,
  "coordinations": [
    {
      "coordination_id": "uuid-coord-1",
      "parent_agent": "coordinator-1",
      "status": "Pending",
      ...
    }
  ]
}
```

### 2.3 启动协调任务

**请求**：
```bash
curl -X POST http://localhost:18789/v1/coordination/uuid-coord-1/start
```

**预期响应** (200)：
```json
{
  "coordination_id": "uuid-coord-1",
  "status": "Running",
  "started_at": 1700000001000,
  ...
}
```

### 2.4 更新子任务状态 - Running

**请求**：
```bash
curl -X POST http://localhost:18789/v1/coordination/uuid-coord-1/subtask/task-a \
  -H "Content-Type: application/json" \
  -d '{"status": "Running"}'
```

**预期响应** (200)：
```json
{
  "coordination_id": "uuid-coord-1",
  "subtasks": [
    {
      "task_id": "task-a",
      "status": "Running",
      "started_at": 1700000002000,
      ...
    },
    {
      "task_id": "task-b",
      "status": "Pending",
      ...
    },
    {
      "task_id": "task-c",
      "status": "Pending",
      ...
    }
  ],
  "status": "Running",
  ...
}
```

### 2.5 更新子任务状态 - Completed

**请求**：
```bash
curl -X POST http://localhost:18789/v1/coordination/uuid-coord-1/subtask/task-a \
  -H "Content-Type: application/json" \
  -d '{
    "status": "Completed",
    "result": {"analysis": "文件 a.py 包含 100 行代码", "issues": 3}
  }'
```

**预期响应** (200)：
```json
{
  "coordination_id": "uuid-coord-1",
  "subtasks": [
    {
      "task_id": "task-a",
      "status": "Completed",
      "result": {"analysis": "文件 a.py 包含 100 行代码", "issues": 3},
      "completed_at": 1700000003000,
      ...
    },
    ...
  ],
  "results": {
    "task-a": {"analysis": "文件 a.py 包含 100 行代码", "issues": 3}
  },
  "status": "Running",
  ...
}
```

### 2.6 完成所有子任务

**请求**：
```bash
# 完成 task-b
curl -X POST http://localhost:18789/v1/coordination/uuid-coord-1/subtask/task-b \
  -H "Content-Type: application/json" \
  -d '{"status": "Completed", "result": {"analysis": "文件 b.py 包含 200 行代码", "issues": 5}}'

# 完成 task-c
curl -X POST http://localhost:18789/v1/coordination/uuid-coord-1/subtask/task-c \
  -H "Content-Type: application/json" \
  -d '{"status": "Completed", "result": {"analysis": "文件 c.py 包含 150 行代码", "issues": 2}}'
```

**预期响应** (200) - 最后一个子任务完成后：
```json
{
  "coordination_id": "uuid-coord-1",
  "status": "Completed",
  "completed_at": 1700000005000,
  "results": {
    "task-a": {"analysis": "文件 a.py 包含 100 行代码", "issues": 3},
    "task-b": {"analysis": "文件 b.py 包含 200 行代码", "issues": 5},
    "task-c": {"analysis": "文件 c.py 包含 150 行代码", "issues": 2}
  },
  ...
}
```

### 2.7 获取汇总结果

**请求**：
```bash
curl http://localhost:18789/v1/coordination/uuid-coord-1/results
```

**预期响应** (200)：
```json
{
  "coordination_id": "uuid-coord-1",
  "status": "Completed",
  "total_subtasks": 3,
  "completed": 3,
  "failed": 0,
  "results": {
    "task-a": {"analysis": "文件 a.py 包含 100 行代码", "issues": 3},
    "task-b": {"analysis": "文件 b.py 包含 200 行代码", "issues": 5},
    "task-c": {"analysis": "文件 c.py 包含 150 行代码", "issues": 2}
  }
}
```

### 2.8 测试失败场景

**创建新协调任务**：
```bash
curl -X POST http://localhost:18789/v1/coordination \
  -H "Content-Type: application/json" \
  -d '{
    "parent_agent": "coordinator-2",
    "subtasks": [
      {"task_id": "task-x", "message": "任务 X"},
      {"task_id": "task-y", "message": "任务 Y"}
    ]
  }'
```

**启动并标记一个失败**：
```bash
# 启动
curl -X POST http://localhost:18789/v1/coordination/uuid-coord-2/start

# 完成 task-x
curl -X POST http://localhost:18789/v1/coordination/uuid-coord-2/subtask/task-x \
  -H "Content-Type: application/json" \
  -d '{"status": "Completed", "result": {"data": "success"}}'

# 失败 task-y
curl -X POST http://localhost:18789/v1/coordination/uuid-coord-2/subtask/task-y \
  -H "Content-Type: application/json" \
  -d '{"status": "Failed", "error": "文件不存在"}'
```

**预期响应** (200) - 失败后协调任务状态：
```json
{
  "coordination_id": "uuid-coord-2",
  "status": "Failed",
  "completed_at": 1700000006000,
  "subtasks": [
    {
      "task_id": "task-x",
      "status": "Completed",
      ...
    },
    {
      "task_id": "task-y",
      "status": "Failed",
      "error": "文件不存在",
      ...
    }
  ],
  ...
}
```

### 2.9 取消协调任务

**请求**：
```bash
curl -X POST http://localhost:18789/v1/coordination/uuid-coord-1/cancel
```

**预期响应** (200)：
```json
{
  "coordination_id": "uuid-coord-1",
  "status": "Cancelled",
  "completed_at": 1700000007000,
  ...
}
```

---

## 三、流水线测试

### 3.1 创建流水线

**请求**：
```bash
curl -X POST http://localhost:18789/v1/pipeline \
  -H "Content-Type: application/json" \
  -d '{
    "name": "code-review-pipeline",
    "stages": [
      {"name": "read", "message": "读取文件 main.py"},
      {"name": "analyze", "message": "分析代码质量", "input_template": "$read.output"},
      {"name": "report", "message": "生成报告", "input_template": "$analyze.output"}
    ]
  }'
```

**预期响应** (201)：
```json
{
  "pipeline_id": "uuid-pipeline-1",
  "name": "code-review-pipeline",
  "stages": [
    {
      "name": "read",
      "message": "读取文件 main.py",
      "model": null,
      "cwd": null,
      "input_template": null,
      "status": "Pending",
      "result": null,
      "error": null,
      "started_at": null,
      "completed_at": null
    },
    {
      "name": "analyze",
      "message": "分析代码质量",
      "model": null,
      "cwd": null,
      "input_template": "$read.output",
      "status": "Pending",
      "result": null,
      "error": null,
      "started_at": null,
      "completed_at": null
    },
    {
      "name": "report",
      "message": "生成报告",
      "model": null,
      "cwd": null,
      "input_template": "$analyze.output",
      "status": "Pending",
      "result": null,
      "error": null,
      "started_at": null,
      "completed_at": null
    }
  ],
  "current_stage": 0,
  "status": "Pending",
  "results": {},
  "created_at": 1700000000000,
  "started_at": null,
  "completed_at": null,
  "metadata": {}
}
```

### 3.2 列出流水线

**请求**：
```bash
curl http://localhost:18789/v1/pipeline
```

**预期响应** (200)：
```json
{
  "total": 1,
  "pipelines": [
    {
      "pipeline_id": "uuid-pipeline-1",
      "name": "code-review-pipeline",
      "status": "Pending",
      "current_stage": 0,
      ...
    }
  ]
}
```

### 3.3 启动流水线

**请求**：
```bash
curl -X POST http://localhost:18789/v1/pipeline/uuid-pipeline-1/start
```

**预期响应** (200)：
```json
{
  "pipeline_id": "uuid-pipeline-1",
  "status": "Running",
  "started_at": 1700000001000,
  ...
}
```

### 3.4 获取下一个任务

**请求**：
```bash
curl http://localhost:18789/v1/pipeline/uuid-pipeline-1/next
```

**预期响应** (200)：
```json
{
  "has_next": true,
  "stage_name": "read",
  "input": "读取文件 main.py",
  "progress": 0.0
}
```

### 3.5 推进第一阶段

**请求**：
```bash
curl -X POST http://localhost:18789/v1/pipeline/uuid-pipeline-1/advance \
  -H "Content-Type: application/json" \
  -d '{
    "stage_name": "read",
    "result": {"content": "def main():\n    print('Hello')\n", "lines": 2}
  }'
```

**预期响应** (200)：
```json
{
  "pipeline_id": "uuid-pipeline-1",
  "current_stage": 1,
  "stages": [
    {
      "name": "read",
      "status": "Completed",
      "result": {"content": "def main():\n    print('Hello')\n", "lines": 2},
      "completed_at": 1700000002000,
      ...
    },
    {
      "name": "analyze",
      "status": "Pending",
      "input_template": "$read.output",
      ...
    },
    {
      "name": "report",
      "status": "Pending",
      ...
    }
  ],
  "results": {
    "read": {"content": "def main():\n    print('Hello')\n", "lines": 2}
  },
  "status": "Running",
  ...
}
```

### 3.6 获取下一任务（验证模板替换）

**请求**：
```bash
curl http://localhost:18789/v1/pipeline/uuid-pipeline-1/next
```

**预期响应** (200)：
```json
{
  "has_next": true,
  "stage_name": "analyze",
  "input": "分析代码质量",  // 注意：模板 $read.output 应该被替换
  "progress": 0.3333333333333333
}
```

### 3.7 推进第二阶段

**请求**：
```bash
curl -X POST http://localhost:18789/v1/pipeline/uuid-pipeline-1/advance \
  -H "Content-Type: application/json" \
  -d '{
    "stage_name": "analyze",
    "result": {"issues": 1, "score": 85}
  }'
```

**预期响应** (200)：
```json
{
  "pipeline_id": "uuid-pipeline-1",
  "current_stage": 2,
  "results": {
    "read": {"content": "def main():\n    print('Hello')\n", "lines": 2},
    "analyze": {"issues": 1, "score": 85}
  },
  "status": "Running",
  ...
}
```

### 3.8 推进最后阶段（完成流水线）

**请求**：
```bash
curl -X POST http://localhost:18789/v1/pipeline/uuid-pipeline-1/advance \
  -H "Content-Type: application/json" \
  -d '{
    "stage_name": "report",
    "result": {"report_url": "/reports/main.py.html"}
  }'
```

**预期响应** (200)：
```json
{
  "pipeline_id": "uuid-pipeline-1",
  "status": "Completed",
  "completed_at": 1700000004000,
  "current_stage": 3,
  "results": {
    "read": {"content": "def main():\n    print('Hello')\n", "lines": 2},
    "analyze": {"issues": 1, "score": 85},
    "report": {"report_url": "/reports/main.py.html"}
  },
  ...
}
```

### 3.9 验证流水线完成

**请求**：
```bash
curl http://localhost:18789/v1/pipeline/uuid-pipeline-1/next
```

**预期响应** (200)：
```json
{
  "has_next": false,
  "progress": 1.0
}
```

### 3.10 测试失败场景

**创建新流水线**：
```bash
curl -X POST http://localhost:18789/v1/pipeline \
  -H "Content-Type: application/json" \
  -d '{
    "name": "failing-pipeline",
    "stages": [
      {"name": "step1", "message": "步骤1"},
      {"name": "step2", "message": "步骤2"}
    ]
  }'
```

**启动并失败**：
```bash
# 启动
curl -X POST http://localhost:18789/v1/pipeline/uuid-pipeline-2/start

# 推进 step1
curl -X POST http://localhost:18789/v1/pipeline/uuid-pipeline-2/advance \
  -H "Content-Type: application/json" \
  -d '{"stage_name": "step1", "result": {"data": "ok"}}'

# 失败 step2
curl -X POST http://localhost:18789/v1/pipeline/uuid-pipeline-2/fail \
  -H "Content-Type: application/json" \
  -d '{"stage_name": "step2", "error": "处理失败"}'
```

**预期响应** (200)：
```json
{
  "pipeline_id": "uuid-pipeline-2",
  "status": "Failed",
  "completed_at": 1700000005000,
  "stages": [
    {
      "name": "step1",
      "status": "Completed",
      ...
    },
    {
      "name": "step2",
      "status": "Failed",
      "error": "处理失败",
      ...
    }
  ],
  ...
}
```

### 3.11 取消流水线

**请求**：
```bash
curl -X POST http://localhost:18789/v1/pipeline/uuid-pipeline-1/cancel
```

**预期响应** (200)：
```json
{
  "pipeline_id": "uuid-pipeline-1",
  "status": "Cancelled",
  "completed_at": 1700000006000,
  ...
}
```

---

## 四、综合测试场景

### 4.1 完整工作流：协调任务 + Agent 通信

**场景描述**：主 Agent 创建协调任务，分配子任务给多个 Agent，Agent 间通过消息通信

```bash
# 1. 创建 Agent 邮箱
curl -X POST http://localhost:18789/v1/mailbox -d '{"agent_id": "main-agent"}'
curl -X POST http://localhost:18789/v1/mailbox -d '{"agent_id": "worker-1"}'
curl -X POST http://localhost:18789/v1/mailbox -d '{"agent_id": "worker-2"}'

# 2. 创建协调任务
curl -X POST http://localhost:18789/v1/coordination \
  -d '{
    "parent_agent": "main-agent",
    "subtasks": [
      {"task_id": "task-1", "message": "分析模块 A"},
      {"task_id": "task-2", "message": "分析模块 B"}
    ]
  }'

# 3. 启动协调任务
curl -X POST http://localhost:18789/v1/coordination/uuid-coord/start

# 4. 主 Agent 发送任务给 worker
curl -X POST http://localhost:18789/v1/agent/message \
  -d '{
    "from_agent": "main-agent",
    "to_agent": "worker-1",
    "topic": "task_assignment",
    "payload": {"task_id": "task-1", "message": "分析模块 A"}
  }'

curl -X POST http://localhost:18789/v1/agent/message \
  -d '{
    "from_agent": "main-agent",
    "to_agent": "worker-2",
    "topic": "task_assignment",
    "payload": {"task_id": "task-2", "message": "分析模块 B"}
  }'

# 5. Worker 接收任务
curl http://localhost:18789/v1/agent/worker-1/messages
curl http://localhost:18789/v1/agent/worker-2/messages

# 6. Worker 完成任务，更新协调状态
curl -X POST http://localhost:18789/v1/coordination/uuid-coord/subtask/task-1 \
  -d '{"status": "Completed", "result": {"module": "A", "issues": 0}}'

curl -X POST http://localhost:18789/v1/coordination/uuid-coord/subtask/task-2 \
  -d '{"status": "Completed", "result": {"module": "B", "issues": 2}}'

# 7. 获取汇总结果
curl http://localhost:18789/v1/coordination/uuid-coord/results
```

### 4.2 完整工作流：流水线 + Agent 通信

**场景描述**：流水线各阶段由不同 Agent 执行，通过消息传递中间结果

```bash
# 1. 创建 Agent 邮箱
curl -X POST http://localhost:18789/v1/mailbox -d '{"agent_id": "reader-agent"}'
curl -X POST http://localhost:18789/v1/mailbox -d '{"agent_id": "analyzer-agent"}'
curl -X POST http://localhost:18789/v1/mailbox -d '{"agent_id": "reporter-agent"}'

# 2. 创建流水线
curl -X POST http://localhost:18789/v1/pipeline \
  -d '{
    "name": "multi-agent-pipeline",
    "stages": [
      {"name": "read", "message": "读取文件"},
      {"name": "analyze", "message": "分析代码", "input_template": "$read.output"},
      {"name": "report", "message": "生成报告", "input_template": "$analyze.output"}
    ]
  }'

# 3. 启动流水线
curl -X POST http://localhost:18789/v1/pipeline/uuid-pipeline/start

# 4. 获取第一阶段任务
curl http://localhost:18789/v1/pipeline/uuid-pipeline/next

# 5. 通知 reader-agent 执行
curl -X POST http://localhost:18789/v1/agent/message \
  -d '{
    "from_agent": "pipeline-orchestrator",
    "to_agent": "reader-agent",
    "topic": "execute_stage",
    "payload": {"stage": "read", "input": "读取文件"}
  }'

# 6. reader-agent 完成后推进流水线
curl -X POST http://localhost:18789/v1/pipeline/uuid-pipeline/advance \
  -d '{"stage_name": "read", "result": {"content": "file content..."}}'

# 7. 继续后续阶段...
```

---

## 五、错误场景测试

### 5.1 无效 JSON

```bash
curl -X POST http://localhost:18789/v1/mailbox \
  -H "Content-Type: application/json" \
  -d 'invalid json'
```

**预期响应** (400)：
```json
{
  "error": {
    "code": "parse_error",
    "message": "Invalid JSON: ..."
  }
}
```

### 5.2 缺少必填字段

```bash
curl -X POST http://localhost:18789/v1/mailbox \
  -H "Content-Type: application/json" \
  -d '{}'
```

**预期响应** (400)：
```json
{
  "error": {
    "code": "invalid_params",
    "message": "Invalid mailbox params: ..."
  }
}
```

### 5.3 资源不存在

```bash
curl http://localhost:18789/v1/coordination/nonexistent-id
curl http://localhost:18789/v1/pipeline/nonexistent-id
```

**预期响应** (404)：
```json
{
  "error": {
    "code": "coordination_not_found",
    "message": "Coordination not found: nonexistent-id"
  }
}
```

### 5.4 无效状态转换

```bash
# 尝试推进未启动的流水线
curl -X POST http://localhost:18789/v1/pipeline/uuid-pipeline/advance \
  -d '{"stage_name": "read", "result": {}}'
```

---

## 六、性能测试

### 6.1 批量创建邮箱

```bash
for i in {1..100}; do
  curl -X POST http://localhost:18789/v1/mailbox -d "{\"agent_id\": \"agent-$i\"}" &
done
wait
```

### 6.2 批量发送消息

```bash
for i in {1..100}; do
  curl -X POST http://localhost:18789/v1/agent/message \
    -d "{\"from_agent\": \"agent-1\", \"to_agent\": \"agent-$i\", \"topic\": \"test\", \"payload\": {}}" &
done
wait
```

### 6.3 并发协调任务

```bash
for i in {1..10}; do
  curl -X POST http://localhost:18789/v1/coordination \
    -d "{\"parent_agent\": \"coordinator-$i\", \"subtasks\": [{\"task_id\": \"t1\", \"message\": \"task\"}]}" &
done
wait
```

---

## 七、测试检查清单

| 测试项 | 状态 | 备注 |
|--------|------|------|
| **Agent 通信** | | |
| 创建邮箱 | ☐ | |
| 删除邮箱 | ☐ | |
| 列出邮箱 | ☐ | |
| 发送点对点消息 | ☐ | |
| 发送广播消息 | ☐ | |
| 接收消息 | ☐ | |
| **协调任务** | | |
| 创建协调任务 | ☐ | |
| 启动协调任务 | ☐ | |
| 更新子任务状态 | ☐ | |
| 完成所有子任务 | ☐ | |
| 子任务失败处理 | ☐ | |
| 取消协调任务 | ☐ | |
| 获取汇总结果 | ☐ | |
| **流水线** | | |
| 创建流水线 | ☐ | |
| 启动流水线 | ☐ | |
| 获取下一任务 | ☐ | |
| 推进阶段 | ☐ | |
| 模板变量替换 | ☐ | |
| 流水线失败 | ☐ | |
| 取消流水线 | ☐ | |
| **错误处理** | | |
| 无效 JSON | ☐ | |
| 缺少必填字段 | ☐ | |
| 资源不存在 | ☐ | |
| 重复创建 | ☐ | |
| **性能** | | |
| 批量创建邮箱 | ☐ | |
| 批量发送消息 | ☐ | |
| 并发协调任务 | ☐ | |
