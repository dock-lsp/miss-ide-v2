# Miss IDE v2

> 🎯 移动端智能集成开发环境 - 让开发随手可及

Miss IDE 是一款专为移动设备设计的智能集成开发环境，参考 AIDE 的核心设计理念，同时融入现代化的 AI 辅助能力。

## ✨ 核心特性

### 🤖 AI 智能助手
- **多模型支持**：通义千问、DeepSeek、豆包、Minimax、智谱清言、GPT、Claude、Gemini、Ollama、MiMo
- **代码补全**：智能代码补全，提升编码效率
- **代码解释**：快速理解代码逻辑
- **代码重构**：优化代码结构
- **Bug 修复**：智能分析与修复建议

### 🔨 自包含构建系统
- **零配置**：打开项目即可编译
- **内置 SDK**：Java/Kotlin 编译器、Build Tools 内置
- **增量编译**：智能检测变更，仅编译必要文件
- **按需下载**：NDK、Python、Node.js 按需安装

### 📱 终端模拟器
- **完整 Shell 支持**：执行各种命令行工具
- **内置命令**：msdk、cd、ls 等 IDE 专用命令
- **命令历史**：快速回溯执行过的命令

### 💻 代码编辑器
- **语法高亮**：支持 Kotlin/Java/Python/JS 等多种语言
- **多标签编辑**：同时打开多个文件
- **撤销/重做**：完整的编辑历史

## 📦 支持的项目类型

| 类型 | 语言 | 特点 |
|------|------|------|
| Android | Kotlin/Java | 完整 Android 开发支持 |
| Flutter | Dart | 跨平台 UI 框架 |
| Java | Java | 标准 Java 应用 |
| Kotlin | Kotlin | 纯 Kotlin 开发 |
| Python | Python | 脚本和后端开发 |
| Node.js | JavaScript/TypeScript | Web 开发 |

## 🚀 快速开始

### 安装

1. 从应用商店下载 Miss IDE
2. 安装完成后打开应用

### 首次配置

#### 配置 AI 模型

1. 进入「设置」→「AI 设置」
2. 点击「API Key 配置」
3. 选择要使用的 AI 提供商
4. 输入对应的 API Key
5. 保存配置

**推荐配置**：
- 🤖 **免费首选**：Gemini 1.5 Flash（每月 100 万 tokens 免费额度）
- 💰 **性价比之选**：DeepSeek Coder（代码能力强，价格低）
- 🏠 **离线使用**：Ollama（本地部署，完全免费）

#### 导入项目

1. 点击「导入项目」
2. 选择项目文件夹
3. Miss IDE 将自动检测项目类型
4. 点击确认导入

#### 创建新项目

1. 点击「新建项目」
2. 选择项目类型
3. 输入项目名称
4. 点击「创建」

### 编译运行

1. 打开项目
2. 点击顶部的「运行」按钮
3. 选择构建变体（Debug/Release）
4. 等待编译完成
5. 应用将自动安装并运行

## 📖 使用指南

### AI 助手使用

#### 代码补全
1. 在编辑器中输入代码
2. AI 将自动提供代码建议
3. 按 Tab 或点击采纳建议

#### 代码解释
1. 选中文本或打开文件
2. 点击 AI 助手面板
3. 选择「代码解释」
4. 查看详细解释

#### Bug 修复
1. 复制错误信息
2. 粘贴到 AI 助手
3. 获取修复建议

### 终端使用

基础命令：
```bash
# 查看帮助
help

# 切换目录
cd lib

# 列出文件
ls

# 查看文件内容
cat MainActivity.kt

# 执行构建
flutter build apk

# 清理构建缓存
clean
```

内置命令：
```bash
# 查看 SDK 信息
msdk
```

### 键盘快捷键

| 功能 | 快捷键 |
|------|--------|
| 保存 | Ctrl+S |
| 撤销 | Ctrl+Z |
| 重做 | Ctrl+Y |
| 查找 | Ctrl+F |
| 替换 | Ctrl+H |
| 运行 | F5 |
| 调试 | F7 |

## ❓ 常见问题

### Q: 构建失败怎么办？

**A:** 按以下步骤排查：
1. 检查错误信息
2. 确认 SDK 是否已安装
3. 尝试清理并重新构建
4. 检查代码语法错误

### Q: AI 响应很慢？

**A:** 可以尝试：
1. 切换到响应更快的模型
2. 减少请求的代码量
3. 检查网络连接

### Q: 如何节省 API 调用？

**A:** 建议：
1. 优先使用免费模型（Gemini、Ollama）
2. 合理使用代码补全功能
3. 使用增量编译减少全量编译

### Q: 支持哪些文件类型？

**A:** 支持以下文件类型：
- 源代码：Dart, Kotlin, Java, Python, JavaScript, TypeScript, Go, Rust, Swift
- 标记：HTML, CSS, Markdown
- 配置：JSON, YAML, XML, Properties
- 其他：SQL, Shell, Plain Text

## 🔧 开发者配置

### AI 模型 API Key 获取

#### 🇨🇳 国内模型

| 模型 | 获取地址 |
|------|----------|
| 通义千问 | https://dashscope.console.aliyun.com/ |
| DeepSeek | https://platform.deepseek.com/ |
| 豆包 | https://console.volcengine.com/ |
| Minimax | https://www.minimax.io/ |
| 智谱清言 | https://open.bigmodel.cn/ |

#### 🌍 国际模型

| 模型 | 获取地址 |
|------|----------|
| Gemini | https://aistudio.google.com/ |
| OpenAI | https://platform.openai.com/ |
| Claude | https://console.anthropic.com/ |

### Ollama 本地部署

1. 安装 Ollama：https://ollama.ai/
2. 下载模型：
   ```bash
   ollama pull codellama:7b
   ollama pull deepseek-coder:6.7b
   ```
3. Miss IDE 将自动连接本地 Ollama

## 📱 系统要求

- **最低版本**：Android 8.0 (API 26)
- **推荐配置**：RAM 4GB+，存储 2GB+
- **架构支持**：arm64-v8a, armeabi-v7a, x86_64

## 📄 许可证

Miss IDE 采用 Apache 2.0 许可证开源。

## 📞 反馈

如有问题或建议，欢迎通过以下方式反馈：
- GitHub Issues
- 应用内反馈

---

**Miss IDE v2** - 让移动开发更简单 🚀
