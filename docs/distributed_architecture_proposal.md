# MoonClaw 分布式架构升级方案

## 一、当前架构限制

### 1.1 单机瓶颈

| 组件 | 当前实现 | 百万级限制 |
|------|---------|-----------|
| **Gateway** | 单进程，内存存储 `agent_runs` | 内存溢出，无法横向扩展 |
| **Daemon** | 文件锁单例 | 无法多实例运行 |
| **Agent** | 每个任务独立进程 | 进程数限制（~1000） |
| **状态存储** | 内存 Map | 无法跨实例共享 |
| **事件广播** | 内存 Broadcast | 无法跨进程通信 |

### 1.2 关键瓶颈分析

```
当前架构：
┌─────────────────────────────────────────────────────────────┐
│                     单机 Gateway                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  agent_runs: Map[String, AgentRun]  ← 内存限制      │   │
│  │  pending_requests: Int              ← 单进程并发限制 │   │
│  │  events: Broadcast                   ← 无法跨进程    │   │
│  └─────────────────────────────────────────────────────┘   │
│                           │                                 │
│                           ▼                                 │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐          │
│  │ Agent 1 │ │ Agent 2 │ │ Agent 3 │ │   ...   │ ← 进程数限制
│  └─────────┘ └─────────┘ └─────────┘ └─────────┘          │
└─────────────────────────────────────────────────────────────┘

问题：
1. 单进程内存限制：~100万 AgentRun 对象 ≈ 10GB+ 内存
2. 进程数限制：Linux 默认 ~32768 进程
3. 文件描述符限制：每个 Agent 需要多个 fd
4. 单点故障：Gateway 崩溃 = 全部丢失
```

## 二、目标架构

### 2.1 分布式架构总览

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            负载均衡层                                        │
│                    ┌─────────────────────────┐                              │
│                    │   Load Balancer (LB)    │                              │
│                    │   (Nginx / Envoy / ALB) │                              │
│                    └─────────────────────────┘                              │
└─────────────────────────────────────────────────────────────────────────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        ▼                     ▼                     ▼
┌───────────────┐     ┌───────────────┐     ┌───────────────┐
│  Gateway #1   │     │  Gateway #2   │     │  Gateway #N   │
│  (无状态)     │     │  (无状态)     │     │  (无状态)     │
└───────────────┘     └───────────────┘     └───────────────┘
        │                     │                     │
        └─────────────────────┼─────────────────────┘
                              │
┌─────────────────────────────────────────────────────────────────────────────┐
│                            消息队列层                                        │
│                    ┌─────────────────────────┐                              │
│                    │      Kafka / NATS       │                              │
│                    │   (Agent 任务队列)       │                              │
│                    └─────────────────────────┘                              │
└─────────────────────────────────────────────────────────────────────────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        ▼                     ▼                     ▼
┌───────────────┐     ┌───────────────┐     ┌───────────────┐
│  Worker #1    │     │  Worker #2    │     │  Worker #N    │
│  (Agent 执行) │     │  (Agent 执行) │     │  (Agent 执行) │
│               │     │               │     │               │
│  - Agent Pool │     │  - Agent Pool │     │  - Agent Pool │
│  - 1000 agents│     │  - 1000 agents│     │  - 1000 agents│
└───────────────┘     └───────────────┘     └───────────────┘
        │                     │                     │
        └─────────────────────┼─────────────────────┘
                              │
┌─────────────────────────────────────────────────────────────────────────────┐
│                            状态存储层                                        │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐            │
│  │     Redis       │  │   PostgreSQL    │  │      etcd       │            │
│  │  (缓存/会话)    │  │  (持久化状态)   │  │  (分布式锁)     │            │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘            │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 2.2 核心组件设计

#### A. 无状态 Gateway

```moonbit
// 新的 Gateway 设计：无状态，可横向扩展
pub struct DistributedGateway {
  // 无本地状态存储
  uuid : @uuid.Generator
  httpx : @httpx.Server
  port : Int
  logger : @pino.Logger
  
  // 外部依赖
  message_queue : @mq.Producer           // Kafka/NATS 生产者
  state_store : @state.Client            // Redis/PostgreSQL 客户端
  lock_service : @lock.Client            // etcd 分布式锁
  event_stream : @stream.Producer        // 事件流生产者
}

// Agent 请求处理流程
pub async fn DistributedGateway::submit_agent(
  self : DistributedGateway,
  request : AgentRequest,
) -> AgentResponse {
  // 1. 生成唯一 ID
  let run_id = self.uuid.v4()
  
  // 2. 检查幂等性（Redis）
  guard !self.state_store.exists("dedupe:\{request.idempotency_key}") else {
    return AgentResponse::duplicate()
  }
  
  // 3. 获取分布式锁（etcd）- 防止并发创建
  let lock = self.lock_service.acquire(
    key="agent:\{run_id}",
    ttl=30_000,
  )
  
  // 4. 创建 AgentRun 记录（PostgreSQL）
  let run = AgentRun::{
    run_id,
    session_key: request.session_key,
    status: "pending",
    created_at: self.clock.now(),
  }
  self.state_store.create_run(run)
  
  // 5. 发布任务到消息队列（Kafka）
  self.message_queue.publish(
    topic="agent.tasks",
    key=run_id,
    value=AgentTask::{
      run_id,
      message: request.message,
      model: request.model,
      cwd: request.cwd,
      priority: request.priority,
    },
  )
  
  // 6. 返回立即响应
  AgentResponse::accepted(run_id)
}
```

#### B. Agent Worker Pool

```moonbit
// Worker 进程：消费任务，执行 Agent
pub struct AgentWorker {
  worker_id : String
  message_queue : @mq.Consumer          // Kafka/NATS 消费者
  state_store : @state.Client           // 状态更新客户端
  event_stream : @stream.Producer       // 事件流生产者
  
  // Agent 池：复用 Agent 实例
  agent_pool : @pool.Pool[Agent]
  max_concurrent : Int                  // 最大并发数
}

// Worker 主循环
pub async fn AgentWorker::run(self : AgentWorker) -> Unit {
  // 订阅任务队列
  let stream = self.message_queue.subscribe(
    topics=["agent.tasks"],
    group="agent-workers",
  )
  
  for message in stream {
    // 并发控制
    guard self.agent_pool.available() > 0 else {
      // 池满，延迟确认
      message.nack()
      continue
    }
    
    // 异步执行
    @async.spawn(async {
      self.execute_agent(message)
    })
  }
}

// 执行单个 Agent
pub async fn AgentWorker::execute_agent(
  self : AgentWorker,
  task : AgentTask,
) -> Unit {
  // 1. 更新状态为 running
  self.state_store.update_status(task.run_id, "running")
  
  // 2. 从池中获取 Agent
  let agent = self.agent_pool.acquire(task.model)
  
  // 3. 发送事件流
  self.event_stream.publish("agent.events", AgentEvent::started(task.run_id))
  
  // 4. 执行 Agent
  let result = agent.run(task.message)
  
  // 5. 更新状态为 completed
  self.state_store.update_result(task.run_id, result)
  
  // 6. 发送完成事件
  self.event_stream.publish("agent.events", AgentEvent::completed(task.run_id, result))
  
  // 7. 归还 Agent 到池
  self.agent_pool.release(agent)
}
```

#### C. 分布式状态管理

```moonbit
// 状态存储客户端接口
pub trait StateStore {
  // AgentRun CRUD
  fn create_run(self : Self, run : AgentRun) -> Result[Unit, Error]
  fn get_run(self : Self, run_id : String) -> Result[AgentRun?, Error]
  fn update_status(self : Self, run_id : String, status : String) -> Result[Unit, Error]
  fn update_result(self : Self, run_id : String, result : Json) -> Result[Unit, Error]
  fn list_runs(self : Self, filter : RunFilter) -> Result[Array[AgentRun], Error]
  
  // 会话管理
  fn get_session(self : Self, key : String) -> Result[Session?, Error]
  fn save_session(self : Self, session : Session) -> Result[Unit, Error]
  
  // 幂等性检查
  fn check_dedupe(self : Self, key : String, ttl : Int) -> Result[Bool, Error]
}

// Redis 实现
pub struct RedisClient {
  client : @redis.Client
}

pub impl StateStore for RedisClient with create_run(self, run) {
  // 使用 Redis Hash 存储
  self.client.hset("runs:\{run.run_id}", run.to_json().to_map())
}

// PostgreSQL 实现（持久化）
pub struct PostgresClient {
  pool : @pg.Pool
}

pub impl StateStore for PostgresClient with create_run(self, run) {
  self.pool.execute(
    "INSERT INTO agent_runs (run_id, session_key, status, created_at) VALUES ($1, $2, $3, $4)",
    [run.run_id, run.session_key, run.status, run.created_at],
  )
}
```

#### D. 分布式锁服务

```moonbit
// 分布式锁接口
pub trait LockService {
  fn acquire(self : Self, key : String, ttl : Int) -> Result[Lock, Error]
  fn release(self : Self, lock : Lock) -> Result[Unit, Error]
  fn extend(self : Self, lock : Lock, ttl : Int) -> Result[Unit, Error]
}

pub struct Lock {
  key : String
  value : String
  expires_at : Int
}

// etcd 实现
pub struct EtcdClient {
  client : @etcd.Client
}

pub impl LockService for EtcdClient with acquire(self, key, ttl) {
  let value = self.uuid.v4()
  let lease = self.client.grant_lease(ttl / 1000)
  let result = self.client.put_if_absent(
    key="/locks/\{key}",
    value=value,
    lease=lease,
  )
  match result {
    Ok(_) => Lock::{ key, value, expires_at: self.clock.now() + ttl }
    Err(_) => Error::LockAcquireFailed
  }
}
```

#### E. 事件流系统

```moonbit
// 事件流接口
pub trait EventStream {
  fn publish(self : Self, topic : String, event : Event) -> Result[Unit, Error]
  fn subscribe(self : Self, topics : Array[String]) -> Stream[Event]
}

// SSE Gateway 端点
pub async fn DistributedGateway::events_sse(
  self : DistributedGateway,
  request : SSERequest,
) -> SSEStream {
  // 从 Kafka 订阅事件
  let stream = self.event_stream.subscribe(
    topics=["agent.events"],
    group="sse-\{request.client_id}",
  )
  
  // 转换为 SSE 格式
  stream.map(fn(event) {
    SSEMessage::{
      event: event.type,
      data: event.payload.to_json().stringify(),
    }
  })
}
```

## 三、容量规划

### 3.1 百万级 Agent 部署方案

| 组件 | 实例数 | 单实例容量 | 总容量 |
|------|--------|-----------|--------|
| **Gateway** | 10 | 10K req/s | 100K req/s |
| **Kafka** | 9 (3x3) | 100K msg/s | 300K msg/s |
| **Worker** | 1000 | 1000 concurrent agents | 1M agents |
| **Redis** | 6 (3 master + 3 replica) | 100K ops/s | 300K ops/s |
| **PostgreSQL** | 3 (1 primary + 2 replica) | 10K TPS | 10K TPS |
| **etcd** | 3 | 10K ops/s | 10K ops/s |

### 3.2 Worker 资源配置

```
单个 Worker 节点：
┌─────────────────────────────────────────────────────────────┐
│  Agent Worker (单进程)                                       │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  CPU: 16 cores                                       │   │
│  │  Memory: 64 GB                                       │   │
│  │  Max Concurrent Agents: 1000                         │   │
│  │  Agent Pool Size: 100 (复用)                         │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘

1000 个 Worker 节点 = 1,000,000 并发 Agent
```

## 四、迁移路径

### 4.1 阶段一：抽象层（1-2 周）

**目标**：引入抽象接口，不改变现有行为

```moonbit
// 1. 定义状态存储接口
pub trait StateStore { ... }

// 2. 定义锁服务接口
pub trait LockService { ... }

// 3. 定义消息队列接口
pub trait MessageQueue { ... }

// 4. 实现内存版本（保持兼容）
pub struct InMemoryStateStore { ... }
pub struct FileLockService { ... }
pub struct ChannelMessageQueue { ... }
```

### 4.2 阶段二：外部依赖集成（2-3 周）

**目标**：实现 Redis/PostgreSQL/Kafka 适配器

```moonbit
// 1. Redis 状态存储
pub struct RedisStateStore { ... }

// 2. PostgreSQL 持久化
pub struct PostgresStateStore { ... }

// 3. Kafka 消息队列
pub struct KafkaMessageQueue { ... }

// 4. etcd 分布式锁
pub struct EtcdLockService { ... }
```

### 4.3 阶段三：Worker 架构（2-3 周）

**目标**：实现 Agent Worker Pool

```moonbit
// 1. Agent 池化
pub struct AgentPool { ... }

// 2. Worker 进程
pub struct AgentWorker { ... }

// 3. 任务调度
pub struct TaskScheduler { ... }
```

### 4.4 阶段四：Gateway 无状态化（1-2 周）

**目标**：Gateway 变为无状态代理

```moonbit
// 1. 移除内存状态
// 2. 使用外部状态存储
// 3. 使用消息队列
// 4. 支持多实例部署
```

## 五、新增模块结构

```
distributed/
├── state/
│   ├── interface.mbt        # StateStore trait
│   ├── redis.mbt            # Redis 实现
│   ├── postgres.mbt         # PostgreSQL 实现
│   └── memory.mbt           # 内存实现（测试用）
├── lock/
│   ├── interface.mbt        # LockService trait
│   ├── etcd.mbt             # etcd 实现
│   └── file.mbt             # 文件锁实现（兼容）
├── mq/
│   ├── interface.mbt        # MessageQueue trait
│   ├── kafka.mbt            # Kafka 实现
│   ├── nats.mbt             # NATS 实现
│   └── channel.mbt          # Channel 实现（兼容）
├── stream/
│   ├── interface.mbt        # EventStream trait
│   └── kafka.mbt            # Kafka Streams 实现
├── pool/
│   ├── agent_pool.mbt       # Agent 对象池
│   └── pool_config.mbt      # 池配置
├── worker/
│   ├── worker.mbt           # Worker 主进程
│   ├── scheduler.mbt        # 任务调度器
│   └── coordinator.mbt      # 协调器
└── gateway/
    ├── distributed_gateway.mbt  # 无状态 Gateway
    └── sse_handler.mbt          # SSE 处理器
```

## 六、配置示例

### 6.1 分布式配置

```json
{
  "mode": "distributed",
  "gateway": {
    "instances": 10,
    "port": 18789
  },
  "worker": {
    "instances": 1000,
    "max_concurrent_agents": 1000,
    "agent_pool_size": 100
  },
  "kafka": {
    "brokers": ["kafka-1:9092", "kafka-2:9092", "kafka-3:9092"],
    "topics": {
      "tasks": "agent.tasks",
      "events": "agent.events"
    }
  },
  "redis": {
    "nodes": [
      {"host": "redis-1", "port": 6379},
      {"host": "redis-2", "port": 6379},
      {"host": "redis-3", "port": 6379}
    ]
  },
  "postgres": {
    "host": "postgres-primary",
    "port": 5432,
    "database": "moonclaw",
    "replicas": ["postgres-replica-1", "postgres-replica-2"]
  },
  "etcd": {
    "endpoints": ["etcd-1:2379", "etcd-2:2379", "etcd-3:2379"]
  }
}
```

### 6.2 单机配置（兼容模式）

```json
{
  "mode": "standalone",
  "gateway": {
    "instances": 1,
    "port": 18789
  },
  "state_store": "memory",
  "lock_service": "file",
  "message_queue": "channel"
}
```

## 七、监控与运维

### 7.1 关键指标

```moonbit
pub struct GatewayMetrics {
  requests_per_second : Double
  active_agents : Int
  pending_tasks : Int
  queue_depth : Int
  avg_latency_ms : Double
  error_rate : Double
}

pub struct WorkerMetrics {
  worker_id : String
  active_agents : Int
  pool_utilization : Double
  tasks_completed : Int
  tasks_failed : Int
  avg_task_duration_ms : Double
}
```

### 7.2 健康检查

```
GET /health
{
  "status": "healthy",
  "mode": "distributed",
  "components": {
    "kafka": "connected",
    "redis": "connected",
    "postgres": "connected",
    "etcd": "connected"
  },
  "metrics": {
    "active_agents": 50000,
    "pending_tasks": 1000,
    "workers_online": 100
  }
}
```

## 八、总结

### 改造要点

| 方面 | 当前 | 目标 |
|------|------|------|
| **Gateway** | 单进程，内存状态 | 无状态，可横向扩展 |
| **Agent 执行** | 每任务一进程 | Worker Pool，复用进程 |
| **状态存储** | 内存 Map | Redis + PostgreSQL |
| **任务分发** | 直接调用 | Kafka 消息队列 |
| **锁服务** | 文件锁 | etcd 分布式锁 |
| **事件流** | 内存 Broadcast | Kafka Streams |

### 预期收益

1. **横向扩展**：Gateway 和 Worker 都可以水平扩展
2. **高可用**：无单点故障，任意组件可重启
3. **容量提升**：从 ~1000 并发 → 1,000,000 并发
4. **持久化**：所有状态持久化，支持故障恢复
5. **可观测性**：集中式日志和指标收集
