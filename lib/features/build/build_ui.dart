import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'build_config.dart';
import 'build_service.dart';
import 'build_progress.dart';
import 'build_history.dart';
import 'signing_manager.dart';

/// 构建配置 Provider
final buildConfigProvider = StateProvider<BuildConfig>((ref) => BuildConfig(
  projectName: 'Miss IDE',
  projectPath: '',
));

/// 签名配置列表 Provider
final signingConfigsProvider = FutureProvider<List<String>>((ref) async {
  return SigningManager.getSigningConfigNames();
});

/// 构建页面
/// 已改进：支持默认构建当前项目、选择项目、GitHub 构建
class BuildPage extends ConsumerStatefulWidget {
  final String? currentProjectPath;  // 当前打开的项目路径
  final String? currentProjectName;  // 当前打开的项目名称
  
  const BuildPage({
    super.key,
    this.currentProjectPath,
    this.currentProjectName,
  });

  @override
  ConsumerState<BuildPage> createState() => _BuildPageState();
}

class _BuildPageState extends ConsumerState<BuildPage> {
  bool _isBuilding = false;
  BuildHistoryItem? _currentBuild;
  String? _selectedSigningConfig;
  bool _useGitHubBuild = true;  // 默认使用 GitHub 构建

  @override
  void initState() {
    super.initState();
    _initBuildListener();
    _initProjectPath();
  }
  
  void _initProjectPath() {
    // 如果有当前项目，设置默认项目路径
    if (widget.currentProjectPath != null && widget.currentProjectPath!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final config = ref.read(buildConfigProvider);
        ref.read(buildConfigProvider.notifier).state = BuildConfig(
          projectName: widget.currentProjectName ?? config.projectName,
          projectPath: widget.currentProjectPath!,
          buildType: config.buildType,
          enableProguard: config.enableProguard,
          outputPath: config.outputPath,
          signingConfig: config.signingConfig,
          useGitHubBuild: true,  // 默认使用 GitHub 构建
        );
      });
    }
  }

  void _initBuildListener() {
    buildService.buildStatusStream.listen((item) {
      if (mounted) {
        setState(() {
          _currentBuild = item;
          _isBuilding = item?.status == BuildStatus.running ||
              item?.status == BuildStatus.pending;
        });
      }
    });
  }
  
  @override
  void didUpdateWidget(BuildPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 更新项目路径
    if (widget.currentProjectPath != oldWidget.currentProjectPath &&
        widget.currentProjectPath != null &&
        widget.currentProjectPath!.isNotEmpty) {
      final config = ref.read(buildConfigProvider);
      ref.read(buildConfigProvider.notifier).state = BuildConfig(
        projectName: widget.currentProjectName ?? config.projectName,
        projectPath: widget.currentProjectPath!,
        buildType: config.buildType,
        enableProguard: config.enableProguard,
        outputPath: config.outputPath,
        signingConfig: config.signingConfig,
        useGitHubBuild: config.useGitHubBuild,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    // 如果正在构建，显示构建进度界面
    if (_isBuilding && _currentBuild != null) {
      return _buildProgressView(colorScheme);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('构建'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: '构建历史',
            onPressed: () => _openHistory(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 当前项目提示
            if (widget.currentProjectPath != null && widget.currentProjectPath!.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.folder_open, color: Colors.blue.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '当前项目: ${widget.currentProjectName ?? '未知项目'}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade700,
                            ),
                          ),
                          Text(
                            widget.currentProjectPath!,
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.blue.shade600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: _selectProjectDirectory,
                      child: const Text('切换'),
                    ),
                  ],
                ),
              ),
            
            // 项目信息
            _buildProjectSection(colorScheme),
            const SizedBox(height: 24),
            
            // 构建配置
            _buildConfigSection(colorScheme),
            const SizedBox(height: 24),
            
            // 构建方式选择
            _buildBuildMethodSection(colorScheme),
            const SizedBox(height: 24),
            
            // 签名配置
            _buildSigningSection(colorScheme),
            const SizedBox(height: 32),
            
            // 构建按钮
            _buildBuildButton(colorScheme),
            const SizedBox(height: 16),
            
            // 最近构建状态
            if (_currentBuild != null) _buildRecentBuildCard(colorScheme),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressView(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: BuildProgressWidget(
        buildItem: _currentBuild!,
        onCancel: _cancelBuild,
        onClose: _closeProgress,
        onDownloadApk: _downloadApk,
      ),
    );
  }

  Widget _buildProjectSection(ColorScheme colorScheme) {
    final config = ref.watch(buildConfigProvider);
    
    return _buildSection(
      colorScheme,
      title: '项目信息',
      icon: Icons.folder,
      children: [
        ListTile(
          leading: const Icon(Icons.folder_open),
          title: const Text('选择项目目录'),
          subtitle: Text(
            config.projectPath.isEmpty ? '点击选择要构建的项目' : config.projectName,
            style: TextStyle(
              color: config.projectPath.isEmpty 
                  ? colorScheme.primary 
                  : colorScheme.onSurfaceVariant,
            ),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: _selectProjectDirectory,
        ),
        if (config.projectPath.isNotEmpty)
          ListTile(
            title: const Text('项目路径'),
            subtitle: Text(
              config.projectPath.length > 35 
                  ? '...${config.projectPath.substring(config.projectPath.length - 35)}'
                  : config.projectPath,
              style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
            ),
          ),
        ListTile(
          leading: const Icon(Icons.edit),
          title: const Text('项目名称'),
          subtitle: Text(config.projectName),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showProjectNameDialog(config),
        ),
      ],
    );
  }
  
  /// 构建方式选择
  Widget _buildBuildMethodSection(ColorScheme colorScheme) {
    return _buildSection(
      colorScheme,
      title: '构建方式',
      icon: Icons.cloud,
      children: [
        RadioListTile<bool>(
          title: const Text('GitHub Actions 云端构建'),
          subtitle: const Text('自动构建并下载 APK，无需本地环境'),
          value: true,
          groupValue: _useGitHubBuild,
          onChanged: (value) {
            setState(() => _useGitHubBuild = value ?? true);
            final config = ref.read(buildConfigProvider);
            ref.read(buildConfigProvider.notifier).state = config.copyWith(
              useGitHubBuild: true,
            );
          },
        ),
        RadioListTile<bool>(
          title: const Text('后端 API 构建'),
          subtitle: const Text('通过远程服务器构建'),
          value: false,
          groupValue: _useGitHubBuild,
          onChanged: (value) {
            setState(() => _useGitHubBuild = value ?? true);
            final config = ref.read(buildConfigProvider);
            ref.read(buildConfigProvider.notifier).state = config.copyWith(
              useGitHubBuild: false,
            );
          },
        ),
      ],
    );
  }

  Future<void> _selectProjectDirectory() async {
    try {
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
      if (selectedDirectory == null) return;
      
      final name = selectedDirectory.split('/').last;
      final config = ref.read(buildConfigProvider);
      ref.read(buildConfigProvider.notifier).state = BuildConfig(
        projectName: name,
        projectPath: selectedDirectory,
        buildType: config.buildType,
        enableProguard: config.enableProguard,
        outputPath: config.outputPath,
        signingConfig: config.signingConfig,
        useGitHubBuild: _useGitHubBuild,
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已选择项目: $name')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('选择失败: $e')),
        );
      }
    }
  }

  Widget _buildConfigSection(ColorScheme colorScheme) {
    final config = ref.watch(buildConfigProvider);
    
    return _buildSection(
      colorScheme,
      title: '构建配置',
      icon: Icons.build,
      children: [
        // 构建类型
        ListTile(
          title: const Text('构建类型'),
          subtitle: Text(config.buildType.label),
          trailing: SegmentedButton<BuildType>(
            segments: BuildType.values.map((type) => ButtonSegment(
              value: type,
              label: Text(type.value),
            )).toList(),
            selected: {config.buildType},
            onSelectionChanged: (selected) {
              ref.read(buildConfigProvider.notifier).state = 
                  config.copyWith(buildType: selected.first);
            },
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ),
        
        // Proguard
        SwitchListTile(
          title: const Text('启用 Proguard'),
          subtitle: const Text('代码混淆和优化'),
          value: config.enableProguard,
          onChanged: (value) {
            ref.read(buildConfigProvider.notifier).state = 
                config.copyWith(enableProguard: value);
          },
        ),
        
        // 输出路径
        ListTile(
          title: const Text('输出路径'),
          subtitle: Text(config.outputPath),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showOutputPathDialog(config),
        ),
      ],
    );
  }

  Widget _buildSigningSection(ColorScheme colorScheme) {
    final config = ref.watch(buildConfigProvider);
    
    return _buildSection(
      colorScheme,
      title: '签名配置',
      icon: Icons.vpn_key,
      children: [
        // 签名选择
        ListTile(
          title: const Text('签名配置'),
          subtitle: Text(
            config.signingConfig.isDebug 
                ? 'Debug 签名 (默认)' 
                : config.signingConfig.keyAlias.isNotEmpty 
                    ? config.signingConfig.keyAlias 
                    : '未配置',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showSigningSelector(context),
        ),
        
        // 快速配置
        ExpansionTile(
          title: const Text('签名详情'),
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildTextField(
                    label: '密钥库路径',
                    value: config.signingConfig.keystorePath,
                    onChanged: (v) => _updateSigningConfig(
                      config.signingConfig.copyWith(keystorePath: v),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    label: '密钥库密码',
                    value: config.signingConfig.keystorePassword,
                    obscure: true,
                    onChanged: (v) => _updateSigningConfig(
                      config.signingConfig.copyWith(keystorePassword: v),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    label: '别名',
                    value: config.signingConfig.keyAlias,
                    onChanged: (v) => _updateSigningConfig(
                      config.signingConfig.copyWith(keyAlias: v),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    label: '别名密码',
                    value: config.signingConfig.keyPassword,
                    obscure: true,
                    onChanged: (v) => _updateSigningConfig(
                      config.signingConfig.copyWith(keyPassword: v),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        
        // 生成密钥库
        ListTile(
          leading: const Icon(Icons.add_circle_outline),
          title: const Text('生成新密钥库'),
          onTap: () => _showGenerateKeystoreDialog(config),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required String label,
    required String value,
    bool obscure = false,
    required ValueChanged<String> onChanged,
  }) {
    return TextField(
      controller: TextEditingController(text: value),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      obscureText: obscure,
      onChanged: onChanged,
    );
  }

  Widget _buildBuildButton(ColorScheme colorScheme) {
    final config = ref.watch(buildConfigProvider);
    
    return FilledButton.icon(
      onPressed: _isBuilding ? null : () => _startBuild(config),
      icon: _isBuilding 
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.play_arrow),
      label: Text(_isBuilding ? '构建中...' : '开始构建'),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        textStyle: const TextStyle(fontSize: 18),
      ),
    );
  }

  Widget _buildRecentBuildCard(ColorScheme colorScheme) {
    final build = _currentBuild!;
    
    Color statusColor;
    switch (build.status) {
      case BuildStatus.success:
        statusColor = Colors.green;
        break;
      case BuildStatus.failure:
        statusColor = Colors.red;
        break;
      case BuildStatus.cancelled:
        statusColor = Colors.orange;
        break;
      default:
        statusColor = colorScheme.primary;
    }

    return Card(
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            build.status == BuildStatus.success 
                ? Icons.check_circle 
                : build.status == BuildStatus.failure
                    ? Icons.error
                    : Icons.sync,
            color: statusColor,
          ),
        ),
        title: Text('最近构建: ${build.projectName}'),
        subtitle: Text(
          '${build.buildType.label} - ${build.status.label}${build.durationString != '--' ? ' (${build.durationString})' : ''}',
        ),
        trailing: build.status == BuildStatus.success && build.apkPath != null
            ? IconButton(
                icon: const Icon(Icons.download),
                onPressed: () => _downloadApk(build.apkPath!),
              )
            : null,
      ),
    );
  }

  Widget _buildSection(
    ColorScheme colorScheme, {
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: colorScheme.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          margin: EdgeInsets.zero,
          child: Column(children: children),
        ),
      ],
    );
  }

  // 各种对话框
  void _showProjectNameDialog(BuildConfig config) {
    final controller = TextEditingController(text: config.projectName);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('项目名称'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '名称',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              ref.read(buildConfigProvider.notifier).state = 
                  config.copyWith(projectName: controller.text);
              Navigator.pop(context);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _showProjectPathDialog(BuildConfig config) {
    final controller = TextEditingController(text: config.projectPath);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('项目路径'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '路径',
            hintText: '留空使用当前应用',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              ref.read(buildConfigProvider.notifier).state = 
                  config.copyWith(projectPath: controller.text);
              Navigator.pop(context);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _showOutputPathDialog(BuildConfig config) {
    final controller = TextEditingController(text: config.outputPath);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('输出路径'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'APK 输出路径',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              ref.read(buildConfigProvider.notifier).state = 
                  config.copyWith(outputPath: controller.text);
              Navigator.pop(context);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _showSigningSelector(BuildContext context) async {
    final configNames = await SigningManager.getSigningConfigNames();
    final config = ref.read(buildConfigProvider);
    
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.bug_report),
              title: const Text('Debug 签名'),
              subtitle: const Text('默认 Android Debug 密钥'),
              selected: config.signingConfig.isDebug,
              onTap: () {
                ref.read(buildConfigProvider.notifier).state = 
                    config.copyWith(signingConfig: SigningConfig.debugDefault);
                Navigator.pop(context);
              },
            ),
            ...configNames.map((name) => ListTile(
              leading: const Icon(Icons.vpn_key),
              title: Text(name),
              onTap: () async {
                final savedConfig = await SigningManager.getSigningConfig(name);
                if (savedConfig != null) {
                  ref.read(buildConfigProvider.notifier).state = 
                      config.copyWith(signingConfig: savedConfig);
                }
                if (mounted) Navigator.pop(context);
              },
            )),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('保存当前配置'),
              onTap: () {
                Navigator.pop(context);
                _showSaveSigningDialog(config);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showSaveSigningDialog(BuildConfig config) {
    final controller = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('保存签名配置'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '配置名称',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              if (controller.text.trim().isEmpty) return;
              await SigningManager.saveSigningConfig(
                controller.text.trim(),
                config.signingConfig,
              );
              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('已保存: ${controller.text}')),
                );
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _showGenerateKeystoreDialog(BuildConfig config) {
    final keystoreController = TextEditingController(text: 'release.keystore');
    final passwordController = TextEditingController();
    final aliasController = TextEditingController(text: 'release');
    final keyPasswordController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('生成密钥库'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: keystoreController,
                decoration: const InputDecoration(
                  labelText: '文件名',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passwordController,
                decoration: const InputDecoration(
                  labelText: '密码',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: aliasController,
                decoration: const InputDecoration(
                  labelText: '别名',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: keyPasswordController,
                decoration: const InputDecoration(
                  labelText: '密钥密码',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              
              // 获取密钥库保存路径
              String? savePath = await FilePicker.platform.getDirectoryPath();
              if (savePath == null) return;
              
              final keystorePath = p.join(savePath, keystoreController.text);
              final password = passwordController.text;
              final alias = aliasController.text;
              final keyPassword = keyPasswordController.text;
              
              if (password.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('请输入密钥库密码')),
                );
                return;
              }
              
              // 调用密钥库生成
              final result = await SigningManager.generateKeystore(
                keystorePath: keystorePath,
                keystorePassword: password,
                keyAlias: alias,
                keyPassword: keyPassword.isEmpty ? password : keyPassword,
                commonName: 'Miss IDE',
                organization: 'Miss IDE',
                locality: 'Beijing',
                state: 'Beijing',
                country: 'CN',
              );
              
              if (result != null) {
                // 检查是否是命令行提示（keytool 不可用）
                if (result.startsWith('密钥库生成命令') || result.contains('keytool')) {
                  // 显示命令行供用户手动执行
                  _showKeystoreCommandDialog(result);
                } else {
                  // 密钥库生成成功
                  _updateSigningConfig(SigningConfig(
                    keystorePath: keystorePath,
                    keystorePassword: password,
                    keyAlias: alias,
                    keyPassword: keyPassword.isEmpty ? password : keyPassword,
                  ));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('密钥库已生成: ${keystoreController.text}')),
                  );
                }
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('密钥库生成失败，请检查权限和路径')),
                );
              }
            },
            child: const Text('生成'),
          ),
        ],
      ),
    );
  }

  void _updateSigningConfig(SigningConfig signingConfig) {
    final config = ref.read(buildConfigProvider);
    ref.read(buildConfigProvider.notifier).state = 
        config.copyWith(signingConfig: signingConfig);
  }

  /// 显示密钥库生成命令对话框（当 keytool 不可用时）
  void _showKeystoreCommandDialog(String command) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.terminal, color: Colors.orange),
            SizedBox(width: 8),
            Text('请在电脑上执行'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '手机上无法直接生成密钥库，请在电脑终端执行以下命令：',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  command,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '提示：需要安装 Java JDK，keytool 是 JDK 自带工具',
                style: TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: command));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('命令已复制到剪贴板')),
              );
            },
            child: const Text('复制命令'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _startBuild(BuildConfig config) async {
    if (config.projectPath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择项目目录')),
      );
      return;
    }

    setState(() => _isBuilding = true);

    try {
      BuildHistoryItem? result;
      
      if (_useGitHubBuild) {
        // GitHub 构建
        result = await buildService.triggerGitHubBuild(
          projectName: config.projectName,
          buildType: config.buildType,
          branch: 'main',
        );
      } else {
        // 本地/后端构建
        result = await buildService.triggerBuild(
          projectName: config.projectName,
          buildType: config.buildType,
          projectPath: config.projectPath,
        );
      }

      if (result != null) {
        setState(() => _currentBuild = result);
      } else {
        setState(() => _isBuilding = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('构建启动失败')),
          );
        }
      }
    } catch (e) {
      setState(() => _isBuilding = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('构建失败: $e')),
        );
      }
    }
  }

  void _cancelBuild() {
    buildService.cancelBuild();
    setState(() => _isBuilding = false);
  }

  void _closeProgress() {
    setState(() {
      _isBuilding = false;
      _currentBuild = null;
    });
  }

  void _downloadApk(String? apkPath) async {
    if (apkPath == null) return;
    
    try {
      // 如果是远程 URL，直接下载
      if (apkPath.startsWith('http')) {
        // 复制到剪贴板
        Clipboard.setData(ClipboardData(text: apkPath));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('APK 链接已复制到剪贴板'),
            action: SnackBarAction(
              label: '打开',
              onPressed: () {
                // TODO: 使用 url_launcher 打开链接
              },
            ),
          ),
        );
      } else {
        // 本地文件路径
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('APK 路径: $apkPath')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('下载失败: $e')),
      );
    }
  }

  void _openHistory(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const BuildHistoryPage(),
      ),
    );
  }
}
