# Miss IDE v2 - 构建功能说明

## 概述

Miss IDE v2 新增了一键构建打包及签名功能，支持通过 GitHub Actions 云端构建或本地构建 Android APK。

## 功能特性

### 1. 构建系统
- **GitHub Actions 云端构建** - 自动触发远程构建
- **本地构建** - 使用设备上的 Flutter SDK
- **后端构建服务** - 连接后端 API 构建

### 2. 构建类型
- **Debug 构建** - 调试版本，使用默认 Android Debug 签名
- **Release 构建** - 发布版本，需要配置签名信息

### 3. 签名管理
- 生成新的密钥库
- 保存和管理多个签名配置
- Debug 签名（默认）和 Release 签名

### 4. 构建进度
- 实时日志显示
- 构建状态跟踪
- 进度通知

### 5. 构建历史
- 记录所有构建历史
- 快速查看构建结果
- APK 下载链接

## 使用方法

### 1. 配置 GitHub Token（云端构建必需）

1. 打开 Miss IDE
2. 进入「设置」页面
3. 找到「构建服务」部分
4. 点击「GitHub Token」
5. 输入你的 GitHub Personal Access Token

**Token 权限要求：**
- `repo` - 访问私有仓库
- `workflow` - 触发 Actions

获取 Token：https://github.com/settings/tokens?type=beta

### 2. 开始构建

1. 打开底部导航栏的「构建」页面
2. 配置构建选项：
   - 项目名称
   - 构建类型（Debug/Release）
   - 签名配置
   - 输出路径
3. 点击「开始构建」按钮

### 3. 监控构建进度

构建开始后，界面会显示：
- 当前构建状态
- 实时构建日志
- 预计剩余时间

### 4. 下载 APK

构建成功后：
- 点击「下载 APK」按钮
- APK 会保存到配置的输出路径
- 下载链接也会复制到剪贴板

## 签名配置

### Debug 签名
默认使用 Android Debug 签名，无需额外配置。

### Release 签名
1. 生成密钥库：
   ```bash
   keytool -genkey -v -keystore release.keystore \
     -alias release -keyalg RSA -keysize 2048 \
     -validity 10000 -storepass <密码> \
     -keypass <密码> -dname "CN=Your Name,O=Your Org"
   ```

2. 在构建页面配置签名信息：
   - 密钥库路径
   - 密钥库密码
   - 别名
   - 别名密码

3. 保存配置以便下次使用

## 目录结构

```
lib/features/build/
├── build.dart              # 模块导出
├── build_config.dart       # 配置模型
├── build_service.dart      # 构建服务核心
├── build_ui.dart           # 构建界面
├── build_progress.dart     # 进度组件
├── build_history.dart      # 历史记录
└── signing_manager.dart    # 签名管理
```

## API 端点

- **GitHub Actions**: `https://api.github.com/repos/{owner}/{repo}/actions/workflows`
- **后端服务**: `http://47.92.220.102`

## 注意事项

1. **GitHub Token 安全**：Token 仅存储在本地安全存储中，不会传输到第三方
2. **网络要求**：云端构建需要稳定的网络连接
3. **构建时间**：云端构建通常需要 5-15 分钟
4. **存储空间**：确保设备有足够的存储空间存储 APK

## 故障排除

### 构建失败
- 检查 GitHub Token 是否有效
- 确认网络连接正常
- 查看构建日志中的错误信息

### 无法下载 APK
- 检查输出路径是否可写
- 确认设备存储空间充足

### 签名错误
- 验证密钥库密码是否正确
- 确认别名和密码匹配

## 技术支持

- GitHub Issues: https://github.com/qq00150610-cpu/miss-ide-v2/issues
