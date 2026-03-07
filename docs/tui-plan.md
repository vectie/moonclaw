# Moonclaw TUI 设计文档

## 概述

Moonclaw TUI 是一个用纯 MoonBit 实现的终端用户界面，提供丰富的交互体验，包括聊天界面、工具执行展示、多主题支持等功能。

## 架构设计

### 整体架构

```
┌─────────────────────────────────────┐
│              TUI (主控制器)           │
├─────────────────────────────────────┤
│  Terminal (终端抽象层)                │
│  ├─ Input/Output 流管理               │
│  ├─ 原始模式设置                       │
│  └─ Alt Screen 支持                   │
├─────────────────────────────────────┤
│  Components (组件层)                  │
│  ├─ ChatLog (聊天日志)                │
│  ├─ Editor (输入编辑器)               │
│  ├─ Text (文本显示)                   │
│  ├─ Loader (加载动画)                 │
│  └─ Container (布局容器)              │
├─────────────────────────────────────┤
│  Message Components (消息组件)        │
│  ├─ UserMessage (用户消息)            │
│  ├─ AssistantMessage (助手消息)       │
│  ├─ SystemMessage (系统消息)          │
│  └─ ToolExecution (工具执行)          │
└─────────────────────────────────────┘
```

## 核心组件

### 1. TUI (主控制器)

**文件**: `internal/tui/tui.mbt`

TUI 是整个界面的主控制器，负责管理所有组件和事件分发。

```moonbit
pub struct TUI {
  terminal : Terminal
  mut chat_log : ChatLog
  mut editor : Editor
  mut status_loader : Loader
  mut status_text : Text
  mut header : Text
  mut footer : Text
  mut state : TuiState
  mut running : Bool
  mut on_submit : ((String) -> Unit)?
  mut on_command : ((String) -> Unit)?
  mut on_escape : (() -> Unit)?
  mut on_ctrl_c : (() -> Unit)?
  mut on_ctrl_d : (() -> Unit)?
  mut on_ctrl_o : (() -> Unit)?
}
```

**主要功能**:
- ✅ 终端生命周期管理 (start/stop)
- ✅ 事件循环处理
- ✅ 组件渲染调度
- ✅ 回调函数注册
- ✅ 状态管理

**事件回调**:
- `on_submit`: 用户提交输入
- `on_command`: 斜杠命令处理
- `on_escape`: ESC 键处理
- `on_ctrl_c`: Ctrl+C 处理
- `on_ctrl_d`: Ctrl+D 处理
- `on_ctrl_o`: Ctrl+O 工具折叠

### 2. Terminal (终端抽象)

**文件**: `internal/tui/terminal.mbt`

提供底层的终端控制功能。

```moonbit
pub struct Terminal {
  input : @stdio.Input
  output : @stdio.Output
  mut width : Int
  mut height : Int
  mut cursor_x : Int
  mut cursor_y : Int
  mut running : Bool
  mut in_alt_screen : Bool
}
```

**主要功能**:
- ✅ 终端大小检测 (`@tty.window_size()`)
- ✅ 原始模式设置 (`@tty.set_raw_mode()`)
- ✅ Alt Screen 切换
- ✅ 光标控制 (显示/隐藏/移动)
- ✅ 屏幕清除
- ✅ 窗口大小变化处理

### 3. Editor (输入编辑器)

**文件**: `internal/tui/editor.mbt`

功能丰富的输入框组件，支持历史记录和快捷键。

```moonbit
pub struct Editor {
  mut text : String
  mut cursor : Int
  history : Array[String]
  mut history_index : Int
  mut placeholder : String
  multiline : Bool
  mut on_submit : ((String) -> Unit)?
  mut on_change : ((String) -> Unit)?
  mut on_escape : (() -> Unit)?
  mut on_ctrl_c : (() -> Unit)?
  mut on_ctrl_d : (() -> Unit)?
  mut prompt : String
  style : TextStyle
}
```

**主要功能**:
- ✅ 文本输入和编辑
- ✅ 光标移动 (左右、Home、End)
- ✅ 字符删除 (Backspace、Delete)
- ✅ 历史记录导航 (↑/↓)
- ✅ 单词删除 (Ctrl+W、Ctrl+Backspace)
- ✅ 行编辑 (Ctrl+K 删除到末尾、Ctrl+U 删除到开头)
- ✅ 提交处理 (Enter)
- ✅ Placeholder 显示

**快捷键支持**:
| 快捷键 | 功能 |
|--------|------|
| `←` / `→` | 光标移动 |
| `Home` / `End` | 移动到开头/结尾 |
| `Backspace` | 删除前一个字符 |
| `Delete` | 删除当前字符 |
| `Ctrl+W` | 删除前一个单词 |
| `Ctrl+K` | 删除到行尾 |
| `Ctrl+U` | 删除到行首 |
| `Ctrl+A` | 移动到开头 |
| `Ctrl+E` | 移动到结尾 |
| `↑` / `↓` | 历史记录导航 |
| `Enter` | 提交输入 |

### 4. ChatLog (聊天日志)

**文件**: `internal/tui/chat_log.mbt`

聊天消息的容器，支持多种消息类型和工具调用展示。

```moonbit
pub struct ChatLog {
  mut components : Array[MessageComponent]
  mut tool_by_id : Map[String, Int]
  mut streaming_by_id : Map[String, Int]
  mut tools_expanded : Bool
  max_components : Int
}
```

**主要功能**:
- ✅ 消息添加和管理
- ✅ 自动滚动到最新消息
- ✅ 组件数量限制 (防止内存溢出)
- ✅ 工具调用跟踪
- ✅ 流式消息支持
- ✅ 工具折叠/展开

**消息类型**:
```moonbit
pub enum MessageComponent {
  UserMsg(UserMessage)        // 用户消息
  AssistantMsg(AssistantMessage) // AI 助手消息
  SystemMsg(SystemMessage)    // 系统消息
  ToolExec(ToolExecution)     // 工具执行
  SpacerComp(Spacer)          // 间隔
}
```

### 5. Container (布局容器)

**文件**: `internal/tui/container.mbt`

灵活的布局容器，支持垂直和水平布局。

```moonbit
pub struct Container {
  children : Array[Component]
  direction : Direction
}

pub enum Direction {
  Vertical
  Horizontal
}
```

**主要功能**:
- ✅ 垂直/水平布局
- ✅ 子组件管理
- ✅ 自动高度计算
- ✅ 嵌套布局支持

**组件类型**:
```moonbit
pub enum Component {
  TextComponent(Text)
  ContainerComponent(Container)
  EditorComponent(Editor)
  LoaderComponent(Loader)
  SpacerComponent(Spacer)
  BoxComponent(Box)
}
```

### 6. Text (文本显示)

**文件**: `internal/tui/text.mbt`

简单的文本显示组件，支持样式。

```moonbit
pub struct Text {
  content : String
  style : TextStyle
}
```

**主要功能**:
- ✅ 文本显示
- ✅ 样式应用 (颜色、粗体等)
- ✅ 自动换行
- ✅ 文本截断

### 7. Loader (加载动画)

**文件**: `internal/tui/loader.mbt`

加载状态指示器，显示旋转动画。

```moonbit
pub struct Loader {
  frames : Array[String]
  mut current : Int
  mut message : String
  mut running : Bool
  style : TextStyle
}
```

**主要功能**:
- ✅ 旋转动画帧
- ✅ 自定义消息
- ✅ 开始/停止控制
- ✅ 动画帧更新

**默认动画帧**: `["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]`

### 8. Spacer (间隔组件)

**文件**: `internal/tui/text.mbt`

用于布局的空白间隔。

```moonbit
pub struct Spacer {
  height : Int
}
```

### 9. Box (边框容器)

**文件**: `internal/tui/text.mbt`

带边框的容器组件。

```moonbit
pub struct Box {
  title : String
  content : Component
  style : BoxStyle
}
```

## 消息组件

### UserMessage (用户消息)

**文件**: `internal/tui/user_message.mbt`

显示用户输入的消息。

```moonbit
pub struct UserMessage {
  text : String
}
```

**显示格式**:
```
┌─ You ─────────────────────────────┐
│ <用户输入内容>                      │
└───────────────────────────────────┘
```

### AssistantMessage (助手消息)

**文件**: `internal/tui/assistant_message.mbt`

显示 AI 助手的回复，支持流式输出。

```moonbit
pub struct AssistantMessage {
  mut text : String
  mut lines : Array[StringView]
  mut is_streaming : Bool
}
```

**主要功能**:
- ✅ 多行文本显示
- ✅ 流式输出标记
- ✅ 自动换行

**显示格式**:
```
Assistant: <AI 回复内容>
```

### SystemMessage (系统消息)

**文件**: `internal/tui/assistant_message.mbt`

显示系统通知和状态信息。

```moonbit
pub struct SystemMessage {
  text : String
}
```

**显示格式**:
```
System: <系统消息内容>
```

### ToolExecution (工具执行)

**文件**: `internal/tui/tool_execution.mbt`

显示工具调用的执行过程和结果。

```moonbit
pub struct ToolExecution {
  tool_call_id : String
  tool_name : String
  args : String
  mut result : String
  mut status : ToolStatus
  mut expanded : Bool
}

pub enum ToolStatus {
  Running
  Success
  Error
}
```

**主要功能**:
- ✅ 工具名称和参数显示
- ✅ 执行状态 (运行中/成功/失败)
- ✅ 结果展示
- ✅ 折叠/展开控制

**显示格式**:
```
┌─ Tool: <tool_name> ───────────────┐
│ Args: <参数>                       │
│ Status: ● Running / ✓ Success / ✗ Error │
│ Result: <结果>                     │
└───────────────────────────────────┘
```

## 事件处理

### Key 枚举

**文件**: `internal/tui/component.mbt`

定义了所有支持的按键类型。

```moonbit
pub enum Key {
  Char(Char)          // 普通字符
  Enter               // 回车
  Backspace           // 退格
  Delete              // 删除
  Up                  // 上箭头
  Down                // 下箭头
  Left                // 左箭头
  Right               // 右箭头
  Home                // Home 键
  End                 // End 键
  PageUp              // Page Up
  PageDown            // Page Down
  Tab                 // Tab
  ShiftTab            // Shift+Tab
  Escape              // ESC
  F1..F12             // 功能键
  Ctrl(Char)          // Ctrl 组合键
  Alt(Char)           // Alt 组合键
  PasteStart          // 粘贴开始
  PasteEnd            // 粘贴结束
  Unknown             // 未知按键
}
```

### 键盘事件解析

**文件**: `internal/tui/component.mbt`

解析终端输入的转义序列，转换为 Key 枚举。

**支持的转义序列**:
- `\x1b[A` - Up
- `\x1b[B` - Down
- `\x1b[C` - Right
- `\x1b[D` - Left
- `\x1b[1~` - Home
- `\x1b[4~` - End
- `\x1b[5~` - PageUp
- `\x1b[6~` - PageDown
- `\x1b[11~` - F1
- ... (更多功能键)
- `\x1b[200~` - PasteStart
- `\x1b[201~` - PasteEnd

## ANSI 转义码

### 颜色支持

**文件**: `internal/tui/ansi.mbt`

```moonbit
pub enum Color {
  Black, Red, Green, Yellow, Blue, Magenta, Cyan, White
  BrightBlack, BrightRed, BrightGreen, BrightYellow
  BrightBlue, BrightMagenta, BrightCyan, BrightWhite
  Rgb(Int, Int, Int)  // 24位真彩色
}
```

**使用示例**:
```moonbit
let red_text = colorize("Error", Color::Red)
let blue_bg = colorize("Info", Color::White, bg=Color::Blue)
```

### 文本样式

```moonbit
pub fn bold(text : String) -> String
pub fn dim(text : String) -> String
pub fn italic(text : String) -> String
pub fn underline(text : String) -> String
pub fn strikethrough(text : String) -> String
```

### 光标控制

```moonbit
pub const CursorHome : String      // 光标回到原点
pub const CursorUp : String        // 光标上移
pub const CursorDown : String      // 光标下移
pub const CursorRight : String     // 光标右移
pub const CursorLeft : String      // 光标左移
pub const CursorSave : String      // 保存光标位置
pub const CursorRestore : String   // 恢复光标位置
pub const CursorHide : String      // 隐藏光标
pub const CursorShow : String      // 显示光标

pub fn cursor_to(col : Int, row : Int) -> String
pub fn cursor_to_col(col : Int) -> String
```

### 屏幕控制

```moonbit
pub const ClearScreen : String       // 清屏
pub const ClearScreenDown : String   // 清除光标到屏幕底部
pub const ClearScreenUp : String     // 清除屏幕顶部到光标
pub const ClearLine : String         // 清除整行
pub const ClearLineRight : String    // 清除光标到行尾
pub const ClearLineLeft : String     // 清除行首到光标
pub const AltScreen : String         // 进入 Alt Screen
pub const MainScreen : String        // 返回主屏幕
```

## 主题系统

**文件**: `internal/tui/theme.mbt`

提供可配置的主题系统。

```moonbit
pub struct Theme {
  name : String
  colors : ThemeColors
}

pub struct ThemeColors {
  primary : Color
  secondary : Color
  accent : Color
  background : Color
  text : Color
  error : Color
  warning : Color
  success : Color
}
```

**主要功能**:
- ✅ 颜色方案定义
- ✅ 文本样式方法
- ✅ 默认主题支持

## 命令系统

**文件**: `internal/tui/commands.mbt`

支持斜杠命令解析。

```moonbit
pub fn parse_command(input : String) -> (String, String)
```

**命令格式**: `/command_name arguments`

**返回**: `(command_name, arguments)`

**示例**:
- `/help` → `("help", "")`
- `/model gpt-4` → `("model", "gpt-4")`
- `/clear all` → `("clear", "all")`

## 状态管理

**文件**: `internal/tui/tui_state.mbt`

管理 TUI 的全局状态。

```moonbit
pub struct TuiState {
  mut model : String
  mut thinking_mode : Bool
  mut tools_expanded : Bool
  mut is_loading : Bool
}
```

**状态属性**:
- `model`: 当前使用的模型
- `thinking_mode`: 思考模式开关
- `tools_expanded`: 工具折叠状态
- `is_loading`: 加载状态

## 文件结构

```
internal/tui/
├── ansi.mbt              # ANSI 转义码和颜色
├── assistant_message.mbt # 助手和系统消息
├── chat_log.mbt          # 聊天日志容器
├── commands.mbt          # 斜杠命令解析
├── component.mbt         # 组件接口和键盘事件
├── container.mbt         # 布局容器
├── editor.mbt            # 输入编辑器
├── loader.mbt            # 加载动画
├── terminal.mbt          # 终端抽象层
├── text.mbt              # 文本、间隔、边框组件
├── theme.mbt             # 主题配置
├── tool_execution.mbt    # 工具执行展示
├── tui.mbt               # 主 TUI 控制器
├── tui_state.mbt         # 状态管理
└── user_message.mbt      # 用户消息组件
```

## 实现进度

### ✅ 已完成

#### 第一阶段：基础终端控制
- [x] 终端大小检测
- [x] 光标位置控制
- [x] 颜色输出 (16色 + 256色 + 真彩色)
- [x] 原始模式输入
- [x] Alt Screen 支持
- [x] ANSI 转义码完整实现

#### 第二阶段：布局组件
- [x] Container - 布局容器 (垂直/水平)
- [x] Text - 文本显示
- [x] Editor - 输入框 (完整功能)
- [x] Loader - 加载动画
- [x] Spacer - 间隔组件
- [x] Box - 边框容器

#### 第三阶段：高级组件
- [x] ChatLog - 聊天日志容器
- [x] UserMessage - 用户消息
- [x] AssistantMessage - AI 消息 (支持流式)
- [x] SystemMessage - 系统消息
- [x] ToolExecution - 工具执行展示
- [x] 消息滚动支持
- [x] 组件数量限制 (内存管理)

#### 第四阶段：事件处理
- [x] 完整的键盘事件解析
- [x] Ctrl 组合键支持
- [x] Alt 组合键支持
- [x] 功能键支持 (F1-F12)
- [x] 括号粘贴支持
- [x] 快捷键绑定系统

#### 第五阶段：集成
- [x] TUI 主控制器
- [x] 事件循环
- [x] 回调系统
- [x] 状态管理
- [x] 斜杠命令解析

### 🚧 部分完成

- [ ] 代码块语法高亮 (基础文本显示已实现)
- [ ] Markdown 渲染 (基础换行已实现)
- [ ] 自动完成 (Tab 键支持，但未实现自动补全逻辑)

### 📋 待实现

- [ ] 鼠标事件支持
- [ ] 多主题切换
- [ ] 配置文件支持
- [ ] 更丰富的 Markdown 渲染
- [ ] 代码语法高亮
- [ ] 搜索功能
- [ ] 复制粘贴增强

## 技术亮点

### 1. 纯 MoonBit 实现
- 无外部依赖
- 跨平台兼容
- 类型安全

### 2. 异步架构
- 使用 `async fn` 处理 I/O
- 非阻塞事件循环
- 流式消息支持

### 3. 组件化设计
- 可组合的组件系统
- 统一的渲染接口
- 灵活的布局系统

### 4. 内存管理
- 组件数量限制
- 自动清理旧消息
- 高效的数据结构

### 5. 错误处理
- 使用 `try!` 处理可能的错误
- Result 类型转换
- 安全的字符串切片

## 使用示例

### 基本使用

```moonbit
let tui = TUI::new()?

tui.set_on_submit(fn(text : String) {
  // 处理用户输入
  if text.starts_with("/") {
    // 处理命令
  } else {
    // 发送消息
  }
})

tui.set_on_ctrl_c(fn() {
  // 处理 Ctrl+C
  tui.stop()
})

await tui.start()
```

### 添加消息

```moonbit
// 添加用户消息
let user_msg = UserMessage::new("Hello!")
tui.chat_log().add_user_message(user_msg)

// 添加助手消息
let assistant_msg = AssistantMessage::new("Hi there!")
tui.chat_log().add_assistant_message(assistant_msg)

// 添加工具执行
let tool_exec = ToolExecution::new(
  tool_call_id="call_123",
  tool_name="read_file",
  args="{\"path\": \"/src/main.mbt\"}"
)
tui.chat_log().add_tool_execution(tool_exec)
```

### 自定义组件

```moonbit
// 创建自定义布局
let container = Container::vertical([
  Text::new("Header"),
  ChatLog::new(),
  Editor::with_prompt("> "),
])

// 渲染
await container.render(output, x=0, y=0, width=80, height=24)
```

## 性能优化

### 1. 增量渲染
- 只渲染可见区域
- 避免不必要的重绘

### 2. 组件缓存
- 缓存计算结果
- 减少重复计算

### 3. 内存限制
- 限制最大组件数量
- 自动清理旧消息

### 4. 异步 I/O
- 非阻塞输入读取
- 批量输出写入

## 调试技巧

### 1. 启用调试输出

```moonbit
// 在 terminal.mbt 中添加调试日志
fn Terminal::debug(self : Terminal, msg : String) -> Unit {
  // 输出到 stderr，不影响 TUI 显示
  @stdio.stderr.write("[DEBUG] \{msg}\n")
}
```

### 2. 检查终端大小

```moonbit
let size = @tty.window_size()
println("Terminal size: \{size.col}x\{size.row}")
```

### 3. 测试键盘事件

```moonbit
loop {
  let key = read_key()
  println("Key pressed: \{key}")
  if key is Escape {
    break
  }
}
```

## 常见问题

### Q: 为什么光标不显示？
A: 检查是否调用了 `terminal.hide_cursor()` 而忘记调用 `show_cursor()`。

### Q: 如何处理终端大小变化？
A: 监听 `SIGWINCH` 信号并调用 `terminal.update_size()`。

### Q: 为什么颜色显示不正确？
A: 检查终端是否支持 256 色或真彩色，使用 `Color::Rgb` 需要终端支持。

### Q: 如何退出 Alt Screen？
A: 调用 `terminal.exit_alt_screen()` 或 `terminal.stop()`。

## 未来规划

### 短期目标 (1-2 周)
- [ ] 完善错误处理
- [ ] 添加更多测试
- [ ] 优化性能

### 中期目标 (1-2 月)
- [ ] 鼠标事件支持
- [ ] 多主题系统
- [ ] 配置文件支持

### 长期目标 (3-6 月)
- [ ] 完整的 Markdown 渲染
- [ ] 代码语法高亮
- [ ] 插件系统

## 贡献指南

欢迎贡献代码！请遵循以下步骤：

1. Fork 项目
2. 创建特性分支
3. 提交更改
4. 运行测试 (`moon test`)
5. 格式化代码 (`moon fmt`)
6. 提交 Pull Request

## 许可证

[根据项目许可证填写]

---

**最后更新**: 2026-03-06  
**维护者**: Moonclaw Team
