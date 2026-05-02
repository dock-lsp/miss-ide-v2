# Miss IDE Pro 开发计划

基于 AIDE Pro 需求文档，对 Miss IDE 进行二次开发。

## 当前已实现功能

### ✅ AI 功能
- AI 聊天界面（支持 9 种大模型）
- AI 文件操作命令（@read/@edit/@create）
- 自动保存生成的代码文件
- 代码块提取和保存

### ✅ 构建功能
- GitHub Actions 云端构建
- 构建历史记录
- 构建状态轮询
- APK 下载

### ✅ 其他
- 项目文件浏览器
- 代码编辑器
- 设置页面（API Key 配置）

---

## 待开发功能（按优先级排序）

### Phase 1: AI 编辑增强 (核心功能)

#### 1.1 文件浏览器 AI 编辑入口
- [ ] 长按文件弹出上下文菜单
- [ ] 添加"AI 编辑"菜单项
- [ ] 支持多选文件批量处理

#### 1.2 Diff 对比视图
- [ ] 创建双栏对比组件
- [ ] 实现代码差异高亮
- [ ] 支持"应用修改"、"撤销"、"手动合并"操作

#### 1.3 流式输出
- [ ] AI 响应流式传输
- [ ] 打字机效果展示
- [ ] 取消/中断请求

#### 1.4 上下文增强
- [ ] 读取 build.gradle 获取项目配置
- [ ] 智能关联相关文件（Layout XML 等）
- [ ] 项目依赖信息注入

#### 1.5 历史版本管理
- [ ] 创建 .aide_history 目录
- [ ] AI 编辑前自动备份
- [ ] 版本回退功能

### Phase 2: AI 文件生成增强

#### 2.1 生成入口优化
- [ ] 项目视图添加"+ AI 生成"按钮
- [ ] 支持选择生成范围（单文件/多文件）
- [ ] 模板预设（Activity + Layout + Adapter）

#### 2.2 智能生成
- [ ] 分析项目包名和 minSdk
- [ ] 读取项目依赖自动适配
- [ ] 多模块项目识别

#### 2.3 模板市场
- [ ] 预制代码模板
- [ ] 模板分类浏览
- [ ] 一键生成

### Phase 3: GitHub 集成增强

#### 3.1 OAuth 登录
- [ ] GitHub OAuth 授权流程
- [ ] Token 安全存储
- [ ] 权限最小化

#### 3.2 仓库管理
- [ ] 项目关联 GitHub 仓库
- [ ] 自动创建仓库
- [ ] 一键推送代码

#### 3.3 签名密钥管理
- [ ] 密钥自动检测
- [ ] 加密存储到 GitHub Secrets
- [ ] 本地加密备份

#### 3.4 构建优化
- [ ] Actions 工作流模板
- [ ] 构建日志实时显示
- [ ] 构建失败重试

### Phase 4: 扩展系统

#### 4.1 插件框架
- [ ] 插件加载机制
- [ ] 插件 API 接口定义
- [ ] 权限管理

#### 4.2 扩展市场
- [ ] 插件列表展示
- [ ] 安装/更新/卸载
- [ ] 开发者 API

---

## 技术实现要点

### AI 服务层
```dart
abstract class AIProvider {
  Stream<String> streamChat(String prompt, {List<AIMessage>? history});
  Future<String> editCode(String code, String instruction);
  Future<GeneratedFiles> generateCode(String description, ProjectContext context);
}
```

### Diff 视图组件
```dart
class DiffViewer extends StatelessWidget {
  final String originalCode;
  final String modifiedCode;
  final VoidCallback onApply;
  final VoidCallback onUndo;
  final VoidCallback onManualMerge;
}
```

### GitHub 集成
```dart
class GitHubService {
  Future<bool> authenticate(); // OAuth
  Future<void> createRepository(String name);
  Future<void> pushChanges(String projectPath);
  Future<int> triggerBuild();
  Future<String> downloadArtifact(int artifactId);
}
```

---

## 开发时间线

| 阶段 | 功能 | 预计工作量 |
|------|------|-----------|
| Week 1 | Phase 1.1-1.2 | 文件菜单 + Diff 视图 |
| Week 2 | Phase 1.3-1.5 | 流式输出 + 上下文 + 历史 |
| Week 3 | Phase 2 | AI 生成增强 |
| Week 4 | Phase 3 | GitHub 集成增强 |
| Week 5+ | Phase 4 | 扩展系统 |

---

## 安全设计

1. **API Key 存储**: Android Keystore 加密
2. **GitHub Token**: 最小权限原则，支持手动吊销
3. **签名密钥**: 不明文落盘，使用 AES-256-GCM 加密
4. **数据传输**: 全程 HTTPS

---

## 开始开发

运行以下命令启动开发：
1. 实现文件长按菜单
2. 创建 Diff 视图组件
3. 实现流式 AI 输出
