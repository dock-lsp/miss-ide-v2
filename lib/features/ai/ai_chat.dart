import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'ai_service.dart';
import 'file_operation_service.dart';
import '../file_manager/project_directory.dart';

class AIChatPage extends StatefulWidget {
  final Function(String)? onNavigateToEditor;
  final Function(String, String)? onNavigateToFileBrowser;
  final String? projectPath;  // 当前项目路径
  
  const AIChatPage({
    super.key,
    this.onNavigateToEditor,
    this.onNavigateToFileBrowser,
    this.projectPath,
  });

  @override
  State<AIChatPage> createState() => _AIChatPageState();
}

class _AIChatPageState extends State<AIChatPage> {
  final TextEditingController _messageController = TextEditingController();
  final List<ChatMessage> _messages = [];
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  bool _isLoading = false;
  bool _showQuickActions = true;
  
  // 待保存的代码
  String? _pendingCode;
  String? _pendingLanguage;
  
  // 文件操作上下文
  String? _currentEditFile;
  String? _lastReadFile;
  String? _lastReadContent;

  // 已保存的文件列表
  final List<SavedFile> _savedFiles = [];

  // AI 修改授权机制 - 待处理的修改
  PendingModification? _pendingModification;
  
  // 选中的文件列表（用于 AI 分析）
  final List<String> _selectedFilesForAI = [];
  
  // 上下文文件列表（用于 AI 对话上下文）
  final List<String> _selectedContextFiles = [];
  
  // API Key 验证状态
  bool _isApiKeyValid = false;
  bool _isValidating = false;

  @override
  void initState() {
    super.initState();
    _initService();
    // 设置AI回调
    aiService.onCodeGenerated = _onCodeGenerated;
    // 初始化文件操作服务
    if (widget.projectPath != null) {
      fileOperationService.setProjectPath(widget.projectPath);
    }
  }

  @override
  void didUpdateWidget(AIChatPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 更新项目路径
    if (widget.projectPath != oldWidget.projectPath && widget.projectPath != null) {
      fileOperationService.setProjectPath(widget.projectPath);
    }
  }

  Future<void> _initService() async {
    await aiService.init();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onCodeGenerated(String language, String code) {
    setState(() {
      _pendingCode = code;
      _pendingLanguage = language;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.smart_toy, size: 24),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('AI 助手 - ${aiService.selectedModel}', style: const TextStyle(fontSize: 16)),
                      if (_isValidating)
                        const Padding(
                          padding: EdgeInsets.only(left: 8),
                          child: SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      else if (aiService.apiKey.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Icon(
                            _isApiKeyValid == true ? Icons.check_circle : Icons.error,
                            size: 14,
                            color: _isApiKeyValid == true ? Colors.green : Colors.red,
                          ),
                        ),
                    ],
                  ),
                  if (widget.projectPath != null)
                    Text(
                      '项目: ${p.basename(widget.projectPath!)}',
                      style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(_showQuickActions ? Icons.shortcut : Icons.expand_more),
            onPressed: () => setState(() => _showQuickActions = !_showQuickActions),
            tooltip: '快捷操作',
          ),
          PopupMenuButton<String>(
            initialValue: aiService.selectedModel,
            onSelected: (model) async {
              await aiService.setModel(model);
              if (mounted) setState(() {});
            },
            itemBuilder: (context) => aiService.modelNames.map((model) {
              return PopupMenuItem(
                value: model,
                child: Row(
                  children: [
                    if (model == aiService.selectedModel)
                      const Icon(Icons.check, size: 16, color: Colors.green),
                    if (model == aiService.selectedModel)
                      const SizedBox(width: 8),
                    Expanded(child: Text(model)),
                    FutureBuilder<bool>(
                      future: _hasApiKey(model),
                      builder: (context, snapshot) {
                        if (snapshot.data == true) {
                          return const Icon(Icons.key, size: 14, color: Colors.green);
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
      body: Column(
        children: [
          // API Key状态提示
          if (aiService.apiKey.isEmpty && aiService.selectedModel != 'Ollama')
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: Colors.orange.shade100,
              child: Row(
                children: [
                  const Icon(Icons.warning, color: Colors.orange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '请先在设置中配置 ${aiService.selectedModel} 的 API Key',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _showApiKeyDialog(),
                    child: const Text('配置'),
                  ),
                ],
              ),
            )
          else if (aiService.apiKey.isNotEmpty && _isApiKeyValid == false)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: Colors.red.shade100,
              child: Row(
                children: [
                  const Icon(Icons.error, color: Colors.red),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${aiService.selectedModel} API Key 无效，点击重新验证',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _showApiKeyDialog(),
                    child: const Text('重新配置'),
                  ),
                ],
              ),
            ),
          
          // 文件操作上下文提示
          if (_currentEditFile != null || _lastReadFile != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: Colors.blue.shade50,
              child: Row(
                children: [
                  const Icon(Icons.folder_open, size: 16, color: Colors.blue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _buildContextHint(),
                      style: TextStyle(fontSize: 12, color: Colors.blue.shade700),
                    ),
                  ),
                  if (_currentEditFile != null)
                    IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      onPressed: () => setState(() => _currentEditFile = null),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                    ),
                ],
              ),
            ),
          
          // 已保存的文件列表
          if (_savedFiles.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: Colors.green.shade50,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.save, size: 16, color: Colors.green.shade700),
                      const SizedBox(width: 8),
                      Text(
                        '已保存 ${_savedFiles.length} 个文件',
                        style: TextStyle(fontSize: 12, color: Colors.green.shade700, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => _showSavedFilesDialog(),
                        child: Text('查看', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: _savedFiles.take(3).map((file) {
                      return Chip(
                        label: Text(
                          p.basename(file.path),
                          style: const TextStyle(fontSize: 10),
                        ),
                        avatar: Icon(Icons.insert_drive_file, size: 14),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          
          // 快捷操作按钮
          if (_showQuickActions)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: Theme.of(context).colorScheme.surfaceVariant,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildQuickActionChip(
                      icon: Icons.create_new_folder,
                      label: '创建项目',
                      color: Colors.blue,
                      onTap: _onCreateProject,
                    ),
                    const SizedBox(width: 8),
                    _buildQuickActionChip(
                      icon: Icons.code,
                      label: '生成代码',
                      color: Colors.green,
                      onTap: _onGenerateCode,
                    ),
                    const SizedBox(width: 8),
                    _buildQuickActionChip(
                      icon: Icons.help_outline,
                      label: '解释代码',
                      color: Colors.purple,
                      onTap: _onExplainCode,
                    ),
                    const SizedBox(width: 8),
                    _buildQuickActionChip(
                      icon: Icons.edit_document,
                      label: '修改文件',
                      color: Colors.orange,
                      onTap: _onEditFile,
                    ),
                    const SizedBox(width: 8),
                    _buildQuickActionChip(
                      icon: Icons.file_open,
                      label: '选择文件',
                      color: Colors.teal,
                      onTap: _onSelectFiles,
                    ),
                    const SizedBox(width: 8),
                    _buildQuickActionChip(
                      icon: Icons.bug_report,
                      label: '调试代码',
                      color: Colors.red,
                      onTap: _onDebugCode,
                    ),
                  ],
                ),
              ),
            ),
          
          // 待保存代码提示
          if (_pendingCode != null)
            Container(
              margin: const EdgeInsets.all(8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.code, color: Colors.green.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '检测到生成的 $_pendingLanguage 代码，是否保存到文件？',
                      style: TextStyle(color: Colors.green.shade700),
                    ),
                  ),
                  TextButton(
                    onPressed: _savePendingCode,
                    child: const Text('保存'),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _pendingCode = null;
                      _pendingLanguage = null;
                    }),
                    child: const Text('忽略'),
                  ),
                ],
              ),
            ),
          
          // 消息列表
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.smart_toy,
                          size: 64,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'AI 编程助手',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '当前模型: ${aiService.selectedModel}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        if (widget.projectPath != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Chip(
                              avatar: const Icon(Icons.folder, size: 16),
                              label: Text('项目: ${p.basename(widget.projectPath!)}'),
                            ),
                          ),
                        const SizedBox(height: 16),
                        // 快捷操作示例
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: [
                            _buildSuggestionChip('@read lib/main.dart'),
                            _buildSuggestionChip('@create utils/helper.dart'),
                            _buildSuggestionChip('写一个快速排序算法'),
                          ],
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () => _showApiKeyDialog(),
                          icon: const Icon(Icons.key),
                          label: const Text('配置 API Key'),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      return _buildMessage(_messages[index]);
                    },
                  ),
          ),
          
          // 加载指示器
          if (_isLoading)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text('AI正在思考...', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          
          // 输入区域
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 命令提示
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.lightbulb_outline, size: 16, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          '@read 文件路径 - 读取文件  |  @edit 文件路径 - 修改文件  |  @create 文件路径 - 创建文件',
                          style: TextStyle(fontSize: 10),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // 已选文件区域
                if (_selectedFilesForAI.isNotEmpty || _pendingModification != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_selectedFilesForAI.isNotEmpty) ...[
                          Row(
                            children: [
                              Icon(Icons.folder_open, size: 16, color: Colors.teal.shade700),
                              const SizedBox(width: 8),
                              Text(
                                '已选文件 (${_selectedFilesForAI.length})',
                                style: TextStyle(fontSize: 12, color: Colors.teal.shade700),
                              ),
                              const Spacer(),
                              TextButton(
                                onPressed: _showSelectedFilesDialog,
                                child: Text('查看', style: TextStyle(fontSize: 10)),
                              ),
                              IconButton(
                                icon: const Icon(Icons.clear, size: 16),
                                onPressed: () => setState(() => _selectedFilesForAI.clear()),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                              ),
                            ],
                          ),
                        ],
                        // 待处理修改提示
                        if (_pendingModification != null)
                          Container(
                            margin: const EdgeInsets.only(top: 8),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.orange.shade200),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.pending_actions, size: 16, color: Colors.orange.shade700),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '待应用的修改: ${_pendingModification!.filePath}',
                                        style: TextStyle(fontSize: 11, color: Colors.orange.shade700),
                                      ),
                                      Text(
                                        '请审阅后决定是否应用',
                                        style: TextStyle(fontSize: 10, color: Colors.orange.shade500),
                                      ),
                                    ],
                                  ),
                                ),
                                TextButton(
                                  onPressed: _showModificationDialog,
                                  child: Text('查看', style: TextStyle(fontSize: 10)),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                // 代码粘贴区（可折叠）
                if (_pastedCode != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.code, size: 16, color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '待解释代码 (${_pastedCode!.length} 字符)',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          onPressed: () => setState(() => _pastedCode = null),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                  ),
                Row(
                  children: [
                    // 选择上下文文件按钮（替代粘贴按钮）
                    if (widget.projectPath != null)
                      IconButton(
                        icon: const Icon(Icons.folder_open),
                        onPressed: _onSelectContextFiles,
                        tooltip: '选择上下文文件',
                        color: _selectedContextFiles.isNotEmpty ? Colors.teal : null,
                      ),
                    // 选择文件按钮
                    if (widget.projectPath != null)
                      IconButton(
                        icon: const Icon(Icons.file_open),
                        onPressed: _onSelectFiles,
                        tooltip: '选择分析文件',
                        color: _selectedFilesForAI.isNotEmpty ? Colors.orange : null,
                      ),
                    Expanded(
                      child: Container(
                        constraints: const BoxConstraints(maxHeight: 48),
                        child: TextField(
                          controller: _messageController,
                          focusNode: _focusNode,
                          decoration: InputDecoration(
                            hintText: '输入问题，或使用 @read/@edit/@create 命令...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            prefixIcon: _selectedContextFiles.isNotEmpty
                                ? Container(
                                    margin: const EdgeInsets.symmetric(horizontal: 8),
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.teal.shade100,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      '${_selectedContextFiles.length}个上下文',
                                      style: TextStyle(fontSize: 10, color: Colors.teal.shade700),
                                    ),
                                  )
                                : null,
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.paste),
                              onPressed: _pasteFromClipboard,
                              tooltip: '粘贴代码',
                            ),
                          ),
                          maxLines: 1,
                          minLines: 1,
                          onSubmitted: _isLoading ? null : (_) => _sendMessage(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FloatingActionButton(
                      onPressed: _isLoading ? null : _sendMessage,
                      mini: true,
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.send),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 检查指定模型是否有 API Key
  Future<bool> _hasApiKey(String model) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = prefs.getString('ai_api_key_$model');
      return key != null && key.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  void _showSavedFilesDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.folder, color: Colors.green),
            const SizedBox(width: 8),
            Text('已保存的文件 (${_savedFiles.length})'),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _savedFiles.length,
            itemBuilder: (context, index) {
              final file = _savedFiles[index];
              return ListTile(
                leading: Icon(_getFileIcon(file.extension)),
                title: Text(p.basename(file.path)),
                subtitle: Text(file.path, style: const TextStyle(fontSize: 10)),
                trailing: IconButton(
                  icon: const Icon(Icons.open_in_new),
                  onPressed: () {
                    Navigator.pop(context);
                    // 导航到文件
                    widget.onNavigateToFileBrowser?.call(file.path, file.content);
                  },
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() => _savedFiles.clear());
              Navigator.pop(context);
            },
            child: const Text('清除记录'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  IconData _getFileIcon(String extension) {
    switch (extension.toLowerCase()) {
      case 'dart':
        return Icons.flutter_dash;
      case 'py':
        return Icons.code;
      case 'js':
      case 'ts':
        return Icons.javascript;
      case 'java':
        return Icons.coffee;
      case 'go':
        return Icons.code;
      case 'rs':
        return Icons.settings;
      default:
        return Icons.insert_drive_file;
    }
  }

  String _buildContextHint() {
    final parts = <String>[];
    if (_currentEditFile != null) {
      parts.add('编辑文件: $_currentEditFile');
    }
    if (_lastReadFile != null) {
      parts.add('已读文件: $_lastReadFile');
    }
    return parts.join(' | ');
  }

  String? _pastedCode;

  Widget _buildQuickActionChip({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestionChip(String text) {
    return ActionChip(
      label: Text(text, style: const TextStyle(fontSize: 12)),
      onPressed: () {
        _messageController.text = text;
        _sendMessage();
      },
    );
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.isNotEmpty) {
      setState(() => _pastedCode = data.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已粘贴代码，可以输入问题让AI解释')),
        );
      }
    }
  }

  void _onCreateProject() {
    showModalBottomSheet(
      context: context,
      builder: (context) => _CreateProjectSheet(
        onProjectCreated: (name, template) async {
          Navigator.pop(context);
          await _createProject(name, template);
        },
      ),
    );
  }

  Future<void> _createProject(String name, String template) async {
    try {
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
      if (selectedDirectory == null) return;

      final projectPath = p.join(selectedDirectory, name);
      
      _addMessage(ChatMessage(
        text: '正在为您创建 $name 项目...',
        isUser: false,
        time: _getCurrentTime(),
      ));

      String result;
      if (aiService.isConfigured) {
        result = await aiService.generateProjectWithAI(projectPath, '创建一个$name的$template项目');
      } else {
        result = await aiService.createProject(projectPath, template);
      }

      _addMessage(ChatMessage(
        text: result,
        isUser: false,
        time: _getCurrentTime(),
      ));
    } catch (e) {
      _addMessage(ChatMessage(
        text: '创建失败: $e',
        isUser: false,
        time: _getCurrentTime(),
      ));
    }
  }

  void _onGenerateCode() {
    _showQuickActionDialog(
      title: '生成代码',
      hintText: '描述你想要生成的代码功能...',
      exampleHints: [
        '写一个Python的快速排序算法',
        '创建一个Flutter登录页面',
        '用Java实现一个链表',
      ],
      onSubmit: (description) async {
        String language = 'dart';
        if (description.toLowerCase().contains('python')) language = 'python';
        if (description.toLowerCase().contains('java')) language = 'java';
        if (description.toLowerCase().contains('javascript') || description.toLowerCase().contains('js')) language = 'javascript';
        if (description.toLowerCase().contains('go')) language = 'go';
        if (description.toLowerCase().contains('rust')) language = 'rust';
        
        final response = await aiService.generateCode(language, description);
        _addMessage(ChatMessage(
          text: response,
          isUser: false,
          time: _getCurrentTime(),
        ));
      },
    );
  }

  void _onExplainCode() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('解释代码'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('请粘贴要解释的代码，然后发送即可'),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _pasteFromClipboard();
              },
              icon: const Icon(Icons.paste),
              label: const Text('粘贴代码'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  void _onEditFile() {
    _showFileOperationDialog(
      title: '修改文件',
      hintText: '输入要修改的文件路径',
      buttonText: '开始修改',
      onSubmit: (filePath) async {
        Navigator.pop(context);
        await _handleEditCommand(filePath);
      },
    );
  }

  Future<void> _handleEditCommand(String filePath) async {
    // 先读取文件内容
    final readResult = await fileOperationService.readFile(filePath);
    
    if (readResult.success) {
      setState(() {
        _currentEditFile = filePath;
        _lastReadFile = filePath;
        _lastReadContent = readResult.content;
      });
      
      _addMessage(ChatMessage(
        text: '已读取文件: $filePath\n\n文件内容已加载，现在可以描述你想要做的修改。',
        isUser: false,
        time: _getCurrentTime(),
      ));
    } else {
      // 文件不存在，询问是否创建
      _addMessage(ChatMessage(
        text: '文件 "$filePath" 不存在。\n\n你可以：\n1. 直接告诉我创建这个文件的内容\n2. 使用 @create 命令创建新文件',
        isUser: false,
        time: _getCurrentTime(),
      ));
    }
  }

  void _showFileOperationDialog({
    required String title,
    required String hintText,
    required String buttonText,
    required Function(String) onSubmit,
  }) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: hintText,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            if (widget.projectPath != null)
              Text(
                '项目目录: ${widget.projectPath}',
                style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isEmpty) return;
              Navigator.pop(context);
              onSubmit(controller.text.trim());
            },
            child: Text(buttonText),
          ),
        ],
      ),
    );
  }

  void _onDebugCode() {
    _showQuickActionDialog(
      title: '调试代码',
      hintText: '粘贴代码并描述遇到的问题...',
      exampleHints: [
        '这段代码报错了，帮我看看',
        '代码运行结果不对',
        '性能有问题吗？',
      ],
      onSubmit: (description) async {
        final code = _pastedCode ?? '';
        final prompt = '''请帮我调试以下代码：

代码：
```
$code
```

问题描述：$description

请分析问题原因并提供修复方案。''';
        
        final response = await aiService.chat(prompt);
        _addMessage(ChatMessage(
          text: response,
          isUser: false,
          time: _getCurrentTime(),
        ));
      },
    );
  }

  void _showQuickActionDialog({
    required String title,
    required String hintText,
    required List<String> exampleHints,
    required Function(String) onSubmit,
  }) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: hintText,
                border: const OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: exampleHints.map((hint) {
                return ActionChip(
                  label: Text(hint, style: const TextStyle(fontSize: 10)),
                  onPressed: () {
                    controller.text = hint;
                  },
                );
              }).toList(),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isEmpty) return;
              Navigator.pop(context);
              onSubmit(controller.text.trim());
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _savePendingCode() async {
    if (_pendingCode == null) return;
    
    try {
      // 确定保存目录
      String saveDir = widget.projectPath ?? '';
      if (saveDir.isEmpty) {
        saveDir = await FilePicker.platform.getDirectoryPath() ?? '';
        if (saveDir.isEmpty) return;
      }
      
      // 生成文件名
      final extension = _getExtension(_pendingLanguage ?? 'txt');
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      String fileName = 'generated_code_$timestamp.$extension';
      
      // 尝试从代码中提取更好的文件名
      final fileNameMatch = RegExp(r'(?:文件名|filename|file\s* name)[:\s]*([a-zA-Z0-9_\-\.]+)', caseSensitive: false).firstMatch(_pendingCode!);
      if (fileNameMatch != null) {
        fileName = fileNameMatch.group(1)!;
      }
      
      final filePath = p.join(saveDir, fileName);
      final file = File(filePath);
      await file.parent.create(recursive: true);
      await file.writeAsString(_pendingCode!);
      
      // 添加到已保存文件列表
      _savedFiles.add(SavedFile(
        path: filePath,
        content: _pendingCode!,
        extension: extension,
        savedAt: DateTime.now(),
      ));
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已保存到: $fileName'),
            action: SnackBarAction(
              label: '查看',
              onPressed: _showSavedFilesDialog,
            ),
          ),
        );
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    }
    
    setState(() {
      _pendingCode = null;
      _pendingLanguage = null;
    });
  }

  String _getExtension(String language) {
    const extensions = {
      'dart': 'dart',
      'python': 'py',
      'java': 'java',
      'javascript': 'js',
      'go': 'go',
      'rust': 'rs',
      'c': 'c',
      'cpp': 'cpp',
      'ruby': 'rb',
      'swift': 'swift',
      'kotlin': 'kt',
      'typescript': 'ts',
    };
    return extensions[language.toLowerCase()] ?? 'txt';
  }

  String _getCurrentTime() {
    return DateTime.now().toString().substring(11, 16);
  }

  void _addMessage(ChatMessage message) {
    setState(() {
      _messages.add(message);
    });
    _scrollToBottom();
  }

  /// 解析并处理特殊命令
  AICommand? _parseCommand(String text) {
    final trimmed = text.trim();
    
    // @read 命令
    final readMatch = RegExp(r'^@read\s+(.+)$', caseSensitive: false).firstMatch(trimmed);
    if (readMatch != null) {
      return AICommand(
        type: AICommandType.read,
        filePath: readMatch.group(1)!.trim(),
      );
    }
    
    // @edit 命令
    final editMatch = RegExp(r'^@edit\s+(.+)$', caseSensitive: false).firstMatch(trimmed);
    if (editMatch != null) {
      return AICommand(
        type: AICommandType.edit,
        filePath: editMatch.group(1)!.trim(),
      );
    }
    
    // @create 命令
    final createMatch = RegExp(r'^@create\s+(.+)$', caseSensitive: false).firstMatch(trimmed);
    if (createMatch != null) {
      return AICommand(
        type: AICommandType.create,
        filePath: createMatch.group(1)!.trim(),
      );
    }
    
    return null;
  }

  void _sendMessage() async {
    String text = _messageController.text.trim();
    
    // 如果有待解释的代码
    if (_pastedCode != null && text.isNotEmpty) {
      text = '$text\n\n```\n$_pastedCode\n```';
      setState(() => _pastedCode = null);
    }
    
    if (text.isEmpty || _isLoading) return;

    // 添加用户消息
    _addMessage(ChatMessage(
      text: text,
      isUser: true,
      time: _getCurrentTime(),
    ));

    _messageController.clear();
    setState(() => _isLoading = true);

    try {
      // 检查是否包含特殊命令
      final command = _parseCommand(text);
      
      if (command != null) {
        await _handleCommand(command);
      } else {
        await _handleNormalMessage(text);
      }
    } catch (e) {
      if (mounted) {
        _addMessage(ChatMessage(
          text: '请求出错: $e',
          isUser: false,
          time: _getCurrentTime(),
        ));
      }
    }
    
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  /// 处理特殊命令
  Future<void> _handleCommand(AICommand command) async {
    switch (command.type) {
      case AICommandType.read:
        await _handleReadCommand(command.filePath!);
        break;
      case AICommandType.edit:
        await _handleEditCommand(command.filePath!);
        break;
      case AICommandType.create:
        await _handleCreateCommand(command.filePath!);
        break;
    }
  }

  /// 处理 @read 命令
  Future<void> _handleReadCommand(String filePath) async {
    if (widget.projectPath == null) {
      _addMessage(ChatMessage(
        text: '请先打开一个项目，然后再读取文件。',
        isUser: false,
        time: _getCurrentTime(),
      ));
      return;
    }

    final readResult = await fileOperationService.readFile(filePath);
    
    if (readResult.success) {
      setState(() {
        _lastReadFile = filePath;
        _lastReadContent = readResult.content;
      });
      
      // 显示文件内容（限制长度）
      final content = readResult.content!;
      final displayContent = content.length > 2000 
          ? '${content.substring(0, 2000)}\n\n... (内容过长，已截断)' 
          : content;
      
      _addMessage(ChatMessage(
        text: '✅ 已读取文件: $filePath\n\n```${fileOperationService.inferLanguage(filePath)}\n$displayContent\n```',
        isUser: false,
        time: _getCurrentTime(),
      ));
    } else {
      _addMessage(ChatMessage(
        text: '❌ 读取失败: ${readResult.error}\n\n请检查文件路径是否正确。',
        isUser: false,
        time: _getCurrentTime(),
      ));
    }
  }

  /// 处理 @create 命令
  Future<void> _handleCreateCommand(String filePath) async {
    if (widget.projectPath == null) {
      _addMessage(ChatMessage(
        text: '请先打开一个项目，然后再创建文件。',
        isUser: false,
        time: _getCurrentTime(),
      ));
      return;
    }

    // 更新当前编辑文件
    setState(() {
      _currentEditFile = filePath;
    });
    
    // 获取上下文
    String context = '';
    if (_lastReadContent != null) {
      context = '\n\n参考已有代码:\n```\n${_lastReadContent!.length > 500 ? '${_lastReadContent!.substring(0, 500)}...' : _lastReadContent}\n```\n';
    }
    
    // 请求AI生成文件内容
    final prompt = '''请为文件 "$filePath" 生成代码内容。

文件用途描述: (请根据文件名推断文件用途)

$context

请生成完整的、可直接使用的代码。''';
    
    if (aiService.isConfigured) {
      final response = await aiService.chat(prompt);
      
      // 提取代码块
      final codeBlocks = _extractCodeBlocks(response);
      
      if (codeBlocks.isNotEmpty) {
        // 保存代码块到文件
        final code = codeBlocks.first['code'] as String;
        final language = codeBlocks.first['language'] as String;
        
        final writeResult = await fileOperationService.writeFile(filePath, code);
        
        if (writeResult.success) {
          // 添加到已保存文件列表
          _savedFiles.add(SavedFile(
            path: p.join(widget.projectPath!, filePath),
            content: code,
            extension: p.extension(filePath).replaceFirst('.', ''),
            savedAt: DateTime.now(),
          ));
          
          _addMessage(ChatMessage(
            text: '✅ 文件已创建: $filePath\n\n```$language\n${code.length > 500 ? '${code.substring(0, 500)}...\n(内容过长，已截断显示)' : code}\n```\n\n文件已保存到项目目录。',
            isUser: false,
            time: _getCurrentTime(),
          ));
        } else {
          _addMessage(ChatMessage(
            text: '❌ 保存失败: ${writeResult.error}',
            isUser: false,
            time: _getCurrentTime(),
          ));
        }
      } else {
        _addMessage(ChatMessage(
          text: 'AI响应中未找到可保存的代码。\n\n响应内容:\n$response',
          isUser: false,
          time: _getCurrentTime(),
        ));
      }
    } else {
      _addMessage(ChatMessage(
        text: '需要配置AI API Key才能自动生成代码。\n\n请先配置API Key，或直接粘贴要保存的代码内容。',
        isUser: false,
        time: _getCurrentTime(),
      ));
    }
  }

  /// 处理普通消息
  Future<void> _handleNormalMessage(String text) async {
    // 识别意图
    final intent = aiService.recognizeIntent(text);
    String response;
    List<String> createdFiles = [];
    List<String> editedFiles = [];
    
    switch (intent.type) {
      case AIIntentType.createProject:
        // 创建项目
        response = '好的，我来帮您创建项目...\n\n';
        final name = intent.params['name'] ?? 'my_project';
        final template = intent.params['template'] ?? 'flutter';
        
        String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
        
        if (selectedDirectory == null) {
          response = '已取消';
          break;
        }
        
        final projectPath = p.join(selectedDirectory, name);
        if (aiService.isConfigured) {
          response += await aiService.generateProjectWithAI(projectPath, text);
        } else {
          response += await aiService.createProject(projectPath, template);
        }
        break;
        
      case AIIntentType.generateCode:
        response = await aiService.generateCode(
          intent.params['language'] ?? 'dart',
          text,
        );
        // 自动检测并保存代码文件
        createdFiles = await _autoSaveCodeFromResponse(response, text);
        if (createdFiles.isNotEmpty) {
          response += '\n\n---\n✅ 已自动保存 ${createdFiles.length} 个文件';
        }
        break;
        
      case AIIntentType.explainCode:
        // 尝试提取代码块
        final codeMatch = RegExp(r'```[\s\S]*?```').firstMatch(text);
        if (codeMatch != null) {
          final code = codeMatch.group(0)!.replaceAll('```', '').trim();
          response = await aiService.explainCode(code);
        } else {
          response = '请提供要解释的代码，可以直接粘贴代码后发送';
        }
        break;
        
      default:
        // 在prompt中添加文件上下文
        String enhancedPrompt = text;
        
        // 构建上下文文件内容
        String contextFilesContent = '';
        if (_selectedContextFiles.isNotEmpty) {
          for (final filePath in _selectedContextFiles) {
            final readResult = await fileOperationService.readFile(filePath);
            if (readResult.success && readResult.content != null) {
              final content = readResult.content!;
              final displayContent = content.length > 2000 
                  ? '${content.substring(0, 2000)}\n...(内容过长已截断)' 
                  : content;
              contextFilesContent += '''
【文件: $filePath】
$displayContent
【文件结束】
''';
            }
          }
        }
        
        if (_lastReadContent != null && _lastReadFile != null) {
          enhancedPrompt = '''参考文件: $_lastReadFile

$text

---
$contextFilesContent

注意：请结合上面的文件内容来回答问题。如果需要修改文件，请生成完整的修改后代码。''';
        } else if (contextFilesContent.isNotEmpty) {
          enhancedPrompt = '''上下文文件:
$contextFilesContent

用户问题: $text

请结合上述上下文文件内容来回答问题。''';
        }
        
        response = await aiService.chat(enhancedPrompt);
        
        // 如果当前有编辑文件上下文，处理可能的修改
        if (_currentEditFile != null) {
          editedFiles = await _handleResponseEdits(response, _currentEditFile!);
          if (editedFiles.isNotEmpty) {
            response += '\n\n---\n✅ 已修改 ${editedFiles.length} 个文件';
          }
        }
        
        // 检查响应中是否包含代码块，自动保存
        createdFiles = await _autoSaveCodeFromResponse(response, text);
        if (createdFiles.isNotEmpty) {
          response += '\n\n---\n✅ 已自动保存 ${createdFiles.length} 个文件';
        }
    }
    
    if (mounted) {
      _addMessage(ChatMessage(
        text: response,
        isUser: false,
        time: _getCurrentTime(),
      ));
    }
  }

  /// 处理响应中的编辑
  Future<List<String>> _handleResponseEdits(String response, String filePath) async {
    final editedFiles = <String>[];
    
    // 检查响应中是否包含代码块（可能是修改后的完整文件）
    final codeBlocks = _extractCodeBlocks(response);
    
    if (codeBlocks.isNotEmpty) {
      // 如果用户明确说保存修改，则保存
      if (response.contains('已修改') || 
          response.contains('已更新') || 
          response.contains('下面是修改后的代码') ||
          response.contains('完整代码')) {
        
        final code = codeBlocks.first['code'] as String;
        final result = await fileOperationService.editFile(filePath, code);
        
        if (result.success) {
          editedFiles.add(filePath);
          // 清空编辑上下文
          setState(() {
            _currentEditFile = null;
          });
        }
      }
    }
    
    return editedFiles;
  }

  /// 从响应中提取代码块
  List<Map<String, String>> _extractCodeBlocks(String response) {
    final blocks = <Map<String, String>>[];
    final pattern = RegExp(r'```(\w*)\n?([\s\S]*?)```', multiLine: true);
    final matches = pattern.allMatches(response);
    
    for (final match in matches) {
      final language = match.group(1)?.trim() ?? '';
      final code = match.group(2)?.trim() ?? '';
      
      if (code.isNotEmpty) {
        blocks.add({
          'language': language,
          'code': code,
        });
      }
    }
    
    return blocks;
  }

  /// 从AI响应中自动提取并保存代码
  Future<List<String>> _autoSaveCodeFromResponse(String response, String userPrompt) async {
    final createdFiles = <String>[];
    
    // 如果有项目路径，优先保存到项目目录
    String? saveDir = widget.projectPath;
    
    // 如果没有项目目录，让用户选择
    if (saveDir == null) {
      saveDir = await FilePicker.platform.getDirectoryPath();
      if (saveDir == null) return createdFiles;
    }
    
    // 首先尝试使用 AI Service 的高级解析功能
    if (widget.projectPath != null) {
      final parsedFiles = await aiService.parseAndCreateFiles(response, widget.projectPath!);
      for (final filePath in parsedFiles) {
        if (!createdFiles.contains(filePath)) {
          createdFiles.add(filePath);
          // 读取文件内容添加到已保存列表
          try {
            final content = await File(filePath).readAsString();
            final extension = p.extension(filePath).replaceFirst('.', '');
            _savedFiles.add(SavedFile(
              path: filePath,
              content: content,
              extension: extension,
              savedAt: DateTime.now(),
            ));
          } catch (e) {
            debugPrint('Failed to read created file: $e');
          }
        }
      }
    }
    
    // 如果 AI 解析没有找到文件，使用传统方法
    if (createdFiles.isEmpty) {
      // 匹配代码块
      final codeBlockPattern = RegExp(r'```(\w*)\n?([\s\S]*?)```', multiLine: true);
      final matches = codeBlockPattern.allMatches(response);
      
      if (matches.isEmpty) return createdFiles;
      
      // 从用户提示中推断项目/文件名
      String baseName = 'generated';
      if (userPrompt.contains('创建') || userPrompt.contains('生成')) {
        final nameMatch = RegExp(r'(?:创建|生成|写一个|帮我)[\s]*([a-zA-Z_\u4e00-\u9fa5]+)').firstMatch(userPrompt);
        if (nameMatch != null) {
          baseName = nameMatch.group(1)!.replaceAll(RegExp(r'[^\w]'), '_');
        }
      }
      
      int fileIndex = 1;
      for (final match in matches) {
        final language = match.group(1)?.trim() ?? 'txt';
        final code = match.group(2)?.trim() ?? '';
        
        if (code.isEmpty || code.length < 10) continue; // 跳过太短的代码
        
        // 根据语言确定文件扩展名
        final extension = fileOperationService.getExtension(language);
        
        // 尝试从代码中提取文件名
        String fileName = '$baseName$fileIndex.$extension';
        
        // 检查代码中是否有文件名注释
        final fileNameMatch = RegExp(r'(?:文件名|filename|file)[:\s]*([a-zA-Z0-9_\-\.]+)').firstMatch(code);
        if (fileNameMatch != null) {
          fileName = fileNameMatch.group(1)!;
        }
        
        // 保存文件
        final filePath = p.join(saveDir!, fileName);
        final file = File(filePath);
      
      try {
        await file.parent.create(recursive: true);
        await file.writeAsString(code);
        createdFiles.add(filePath);
        
        // 添加到已保存文件列表
        _savedFiles.add(SavedFile(
          path: filePath,
          content: code,
          extension: extension,
          savedAt: DateTime.now(),
        ));
        
        fileIndex++;
      } catch (e) {
        // 保存失败，继续下一个
        debugPrint('Failed to save file: $e');
      }
    }
    }
    
    return createdFiles;
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showApiKeyDialog() {
    final controller = TextEditingController(text: aiService.apiKey);
    final isValidating = ValueNotifier(false);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Text('${aiService.selectedModel} API Key'),
            const SizedBox(width: 8),
            if (isValidating.value)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (aiService.apiKey.isNotEmpty)
              Icon(
                _isApiKeyValid == true ? Icons.check_circle : Icons.error,
                size: 20,
                color: _isApiKeyValid == true ? Colors.green : Colors.red,
              ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: '输入API Key',
                border: const OutlineInputBorder(),
                suffixIcon: controller.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => controller.clear(),
                      )
                    : null,
              ),
              onChanged: (_) {
                // 清除验证状态当用户编辑时
              },
            ),
            const SizedBox(height: 12),
            Text(
              '获取API Key:',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _getKeyUrl(aiService.selectedModel),
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            ValueListenableBuilder<bool>(
              valueListenable: isValidating,
              builder: (context, validating, _) {
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    OutlinedButton.icon(
                      onPressed: validating
                          ? null
                          : () async {
                              isValidating.value = true;
                              await aiService.saveApiKey(controller.text.trim());
                              isValidating.value = false;
                              if (context.mounted) Navigator.pop(context);
                            },
                      icon: const Icon(Icons.save),
                      label: const Text('保存'),
                    ),
                    if (aiService.apiKey.isNotEmpty)
                      FilledButton.icon(
                        onPressed: validating
                            ? null
                            : () async {
                                isValidating.value = true;
                                // 简单的验证：检查 API Key 是否非空
                                await Future.delayed(const Duration(milliseconds: 500));
                                setState(() {
                                  _isApiKeyValid = controller.text.trim().isNotEmpty;
                                });
                                isValidating.value = false;
                                if (context.mounted) {
                                  Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(_isApiKeyValid == true ? 'API Key 已保存 ✓' : 'API Key 无效'),
                                      backgroundColor: _isApiKeyValid == true ? Colors.green : Colors.red,
                                    ),
                                  );
                                }
                              },
                        icon: const Icon(Icons.verified),
                        label: const Text('验证'),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  String _getKeyUrl(String model) {
    const urls = {
      'DeepSeek': 'platform.deepseek.com',
      '通义千问': 'dashscope.aliyuncs.com',
      '豆包': 'console.volcengine.com/ark',
      'Minimax': 'api.minimax.chat',
      '智谱清言': 'open.bigmodel.cn',
      'Gemini': 'makersuite.google.com',
      'GPT-4': 'platform.openai.com',
      'Claude': 'console.anthropic.com',
    };
    return urls[model] ?? '';
  }

  Widget _buildMessage(ChatMessage message) {
    return Align(
      alignment: message.isUser 
        ? Alignment.centerRight 
        : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.85,
        ),
        decoration: BoxDecoration(
          color: message.isUser
            ? Theme.of(context).colorScheme.primaryContainer
            : Theme.of(context).colorScheme.surfaceVariant,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 检测并高亮代码块
            _buildMessageContent(message.text),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  message.time,
                  style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                if (!message.isUser && message.text.contains('```'))
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: InkWell(
                      onTap: () => _copyCodeFromMessage(message.text),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.copy,
                            size: 12,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '复制代码',
                            style: TextStyle(
                              fontSize: 10,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageContent(String text) {
    // 检测代码块
    final codePattern = RegExp(r'```(\w*)\n?([\s\S]*?)```');
    final matches = codePattern.allMatches(text);
    
    if (matches.isEmpty) {
      return SelectableText(
        text,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 14,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      );
    }
    
    // 分割并构建混合内容
    final List<InlineSpan> spans = [];
    int lastEnd = 0;
    
    for (final match in matches) {
      // 添加匹配前的文本
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
      }
      
      // 添加代码块
      final code = match.group(2)?.trim() ?? '';
      final language = match.group(1) ?? '';
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (language.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  margin: const EdgeInsets.only(bottom: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    language,
                    style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              SelectableText(
                code,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ));
      
      lastEnd = match.end;
    }
    
    // 添加剩余文本
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }
    
    return SelectableText.rich(
      TextSpan(children: spans),
      style: const TextStyle(fontSize: 14),
    );
  }

  void _copyCodeFromMessage(String text) {
    final codePattern = RegExp(r'```\w*\n?([\s\S]*?)```');
    final match = codePattern.firstMatch(text);
    if (match != null) {
      final code = match.group(1)?.trim() ?? '';
      Clipboard.setData(ClipboardData(text: code));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('代码已复制到剪贴板')),
      );
    }
  }

  /// 选择上下文文件进行AI对话
  void _onSelectContextFiles() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _ContextFileSelectionSheet(
        projectPath: widget.projectPath,
        selectedFiles: _selectedContextFiles,
        onConfirm: (selectedFiles) {
          setState(() {
            _selectedContextFiles.clear();
            _selectedContextFiles.addAll(selectedFiles);
          });
        },
      ),
    );
  }

  /// 选择文件进行AI分析
  void _onSelectFiles() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _FileSelectionSheet(
        projectPath: widget.projectPath,
        selectedFiles: _selectedFilesForAI,
        onConfirm: (selectedFiles) {
          setState(() {
            _selectedFilesForAI.clear();
            _selectedFilesForAI.addAll(selectedFiles);
          });
        },
      ),
    );
  }

  /// 选择文件进行AI代码检查
  void _onCheckFiles() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _FileCheckSelectionSheet(
        projectPath: widget.projectPath,
        selectedFiles: _selectedFilesForAI,
        onConfirm: (selectedFiles) {
          if (selectedFiles.isNotEmpty) {
            setState(() {
              _selectedFilesForAI.clear();
              _selectedFilesForAI.addAll(selectedFiles);
            });
            // 自动填充提示词
            final fileNames = selectedFiles.map((f) => p.basename(f)).join('\n- ');
            _messageController.text = '请检查以下文件是否有问题：\n- $fileNames';
            _focusNode.requestFocus();
          }
        },
      ),
    );
  }

  /// 显示已选文件对话框
  void _showSelectedFilesDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.folder_open, color: Colors.teal),
            const SizedBox(width: 8),
            Text('已选文件 (${_selectedFilesForAI.length})'),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: _selectedFilesForAI.isEmpty
              ? const Center(child: Text('未选择任何文件'))
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: _selectedFilesForAI.length,
                  itemBuilder: (context, index) {
                    final filePath = _selectedFilesForAI[index];
                    return ListTile(
                      leading: Icon(_getFileIcon(p.extension(filePath).replaceFirst('.', ''))),
                      title: Text(p.basename(filePath)),
                      subtitle: Text(filePath, style: const TextStyle(fontSize: 10)),
                      trailing: IconButton(
                        icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                        onPressed: () {
                          setState(() {
                            _selectedFilesForAI.removeAt(index);
                          });
                          Navigator.pop(context);
                          if (_selectedFilesForAI.isNotEmpty) {
                            _showSelectedFilesDialog();
                          }
                        },
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() => _selectedFilesForAI.clear());
              Navigator.pop(context);
            },
            child: const Text('清空'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              // 自动填充提示词
              if (_selectedFilesForAI.isNotEmpty) {
                final fileNames = _selectedFilesForAI.map((f) => p.basename(f)).join(', ');
                _messageController.text = '请检查并修正以下文件的代码问题：$fileNames';
              }
            },
            child: const Text('询问AI'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  /// 显示待处理修改对话框
  void _showModificationDialog() {
    if (_pendingModification == null) return;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.pending_actions, color: Colors.orange),
            const SizedBox(width: 8),
            const Text('待应用的修改'),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '文件: ${_pendingModification!.filePath}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Divider(),
                const SizedBox(height: 8),
                const Text(
                  '修改说明:',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 4),
                Text(
                  _pendingModification!.description,
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 16),
                const Text(
                  '修改内容:',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    _pendingModification!.newContent,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() => _pendingModification = null);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已拒绝修改')),
              );
            },
            child: const Text('拒绝'),
          ),
          OutlinedButton(
            onPressed: () async {
              Navigator.pop(context);
              // 复制修改内容到剪贴板
              Clipboard.setData(ClipboardData(text: _pendingModification!.newContent));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('修改内容已复制到剪贴板')),
              );
            },
            child: const Text('复制'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              await _applyModification();
            },
            child: const Text('应用修改'),
          ),
        ],
      ),
    );
  }

  /// 应用待处理的修改
  Future<void> _applyModification() async {
    if (_pendingModification == null) return;
    
    try {
      final result = await fileOperationService.editFile(
        _pendingModification!.filePath,
        _pendingModification!.newContent,
      );
      
      if (result.success) {
        setState(() => _pendingModification = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('文件已修改: ${_pendingModification!.filePath}'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('修改失败: ${result.error}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('应用修改时出错: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// 保存AI响应中的代码块为待处理修改
  void _saveCodeAsPendingModification(String filePath, String description, String code) {
    setState(() {
      _pendingModification = PendingModification(
        filePath: filePath,
        description: description,
        newContent: code,
        createdAt: DateTime.now(),
      );
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('检测到修改建议，请审阅后决定是否应用'),
        backgroundColor: Colors.orange,
        action: SnackBarAction(
          label: '查看',
          onPressed: _showModificationDialog,
        ),
      ),
    );
  }
}

/// AI命令类型
enum AICommandType {
  read,
  edit,
  create,
}

/// AI命令
class AICommand {
  final AICommandType type;
  final String? filePath;
  
  AICommand({
    required this.type,
    this.filePath,
  });
}

class ChatMessage {
  final String text;
  final bool isUser;
  final String time;

  ChatMessage({
    required this.text,
    required this.isUser,
    required this.time,
  });
}

/// 已保存的文件
class SavedFile {
  final String path;
  final String content;
  final String extension;
  final DateTime savedAt;
  
  SavedFile({
    required this.path,
    required this.content,
    required this.extension,
    required this.savedAt,
  });
}

/// 待处理的修改
class PendingModification {
  final String filePath;
  final String description;
  final String newContent;
  final DateTime createdAt;
  
  PendingModification({
    required this.filePath,
    required this.description,
    required this.newContent,
    required this.createdAt,
  });
}

/// 文件选择底部弹窗
class _FileSelectionSheet extends StatefulWidget {
  final String? projectPath;
  final List<String> selectedFiles;
  final Function(List<String>) onConfirm;
  
  const _FileSelectionSheet({
    this.projectPath,
    required this.selectedFiles,
    required this.onConfirm,
  });

  @override
  State<_FileSelectionSheet> createState() => _FileSelectionSheetState();
}

class _FileSelectionSheetState extends State<_FileSelectionSheet> {
  final Set<String> _selectedFiles = {};
  List<FileSystemEntity> _files = [];
  bool _isLoading = true;
  String? _currentPath;
  
  @override
  void initState() {
    super.initState();
    _selectedFiles.addAll(widget.selectedFiles);
    _currentPath = widget.projectPath;
    _loadFiles();
  }
  
  Future<void> _loadFiles() async {
    if (_currentPath == null) {
      setState(() {
        _files = [];
        _isLoading = false;
      });
      return;
    }
    
    try {
      final dir = Directory(_currentPath!);
      final entities = await dir.list().toList();
      
      entities.sort((a, b) {
        if (a is Directory && b is! Directory) return -1;
        if (a is! Directory && b is Directory) return 1;
        return p.basename(a.path).compareTo(p.basename(b.path));
      });
      
      setState(() {
        _files = entities.where((e) {
          final name = p.basename(e.path);
          return !name.startsWith('.');
        }).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _files = [];
        _isLoading = false;
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              // 标题栏
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Theme.of(context).dividerColor),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.folder_open),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '选择文件',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (_currentPath != null)
                            Text(
                              _currentPath!,
                              style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    Text(
                      '已选 ${_selectedFiles.length} 个',
                      style: TextStyle(
                        fontSize: 12,
                        color: _selectedFiles.isNotEmpty ? Colors.teal : null,
                      ),
                    ),
                  ],
                ),
              ),
              
              // 路径导航
              if (_currentPath != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_upward, size: 20),
                        onPressed: () {
                          final parent = Directory(_currentPath!).parent.path;
                          setState(() {
                            _currentPath = parent;
                            _isLoading = true;
                          });
                          _loadFiles();
                        },
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: _buildPathBreadcrumbs(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              
              // 文件列表
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _files.isEmpty
                        ? const Center(child: Text('空目录'))
                        : ListView.builder(
                            controller: scrollController,
                            itemCount: _files.length,
                            itemBuilder: (context, index) {
                              final file = _files[index];
                              final name = p.basename(file.path);
                              final isDir = file is Directory;
                              
                              return ListTile(
                                leading: isDir
                                    ? const Icon(Icons.folder, color: Colors.amber)
                                    : Icon(
                                        _getFileIcon(p.extension(name).replaceFirst('.', '')),
                                        color: _getFileColor(p.extension(name).replaceFirst('.', '')),
                                      ),
                                title: Text(name),
                                subtitle: isDir ? const Text('文件夹', style: TextStyle(fontSize: 10)) : null,
                                trailing: !isDir
                                    ? Checkbox(
                                        value: _selectedFiles.contains(file.path),
                                        onChanged: (value) {
                                          setState(() {
                                            if (value == true) {
                                              _selectedFiles.add(file.path);
                                            } else {
                                              _selectedFiles.remove(file.path);
                                            }
                                          });
                                        },
                                      )
                                    : IconButton(
                                        icon: const Icon(Icons.chevron_right),
                                        onPressed: () {
                                          setState(() {
                                            _currentPath = file.path;
                                            _isLoading = true;
                                          });
                                          _loadFiles();
                                        },
                                      ),
                                onTap: isDir
                                    ? () {
                                        setState(() {
                                          _currentPath = file.path;
                                          _isLoading = true;
                                        });
                                        _loadFiles();
                                      }
                                    : () {
                                        setState(() {
                                          if (_selectedFiles.contains(file.path)) {
                                            _selectedFiles.remove(file.path);
                                          } else {
                                            _selectedFiles.add(file.path);
                                          }
                                        });
                                      },
                              );
                            },
                          ),
              ),
              
              // 底部按钮
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: Theme.of(context).dividerColor),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('取消'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          widget.onConfirm(_selectedFiles.toList());
                          Navigator.pop(context);
                        },
                        child: Text('确定 (${_selectedFiles.length})'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
  
  List<Widget> _buildPathBreadcrumbs() {
    if (_currentPath == null) return [];
    
    final parts = _currentPath!.split('/');
    final widgets = <Widget>[];
    
    for (int i = 0; i < parts.length; i++) {
      if (i > 0) {
        widgets.add(const Icon(Icons.chevron_right, size: 16));
      }
      widgets.add(
        InkWell(
          onTap: () {
            final newPath = parts.sublist(0, i + 1).join('/');
            setState(() {
              _currentPath = newPath;
              _isLoading = true;
            });
            _loadFiles();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: i == parts.length - 1
                  ? Theme.of(context).colorScheme.primaryContainer
                  : null,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              parts[i].isEmpty ? '/' : parts[i],
              style: TextStyle(
                fontSize: 12,
                color: i == parts.length - 1
                    ? Theme.of(context).colorScheme.onPrimaryContainer
                    : null,
              ),
            ),
          ),
        ),
      );
    }
    
    return widgets;
  }
  
  /// 获取文件图标
  IconData _getFileIcon(String extension) {
    switch (extension.toLowerCase()) {
      case 'dart':
        return Icons.code;
      case 'py':
        return Icons.code;
      case 'js':
      case 'ts':
        return Icons.javascript;
      case 'java':
        return Icons.coffee;
      case 'go':
        return Icons.code;
      case 'rs':
        return Icons.settings;
      case 'html':
        return Icons.html;
      case 'css':
        return Icons.style;
      case 'json':
        return Icons.data_object;
      case 'yaml':
      case 'yml':
        return Icons.settings;
      case 'md':
        return Icons.description;
      default:
        return Icons.insert_drive_file;
    }
  }
  
  /// 获取文件颜色
  Color _getFileColor(String extension) {
    switch (extension.toLowerCase()) {
      case 'dart':
        return Colors.blue;
      case 'py':
        return Colors.green;
      case 'js':
        return Colors.yellow;
      case 'java':
        return Colors.orange;
      case 'html':
        return Colors.orange;
      case 'css':
        return Colors.blue;
      case 'json':
        return Colors.amber;
      case 'yaml':
      case 'yml':
        return Colors.cyan;
      default:
        return Colors.grey;
    }
  }
}

/// 上下文文件选择底部弹窗（用于AI对话上下文）
class _ContextFileSelectionSheet extends StatefulWidget {
  final String? projectPath;
  final List<String> selectedFiles;
  final Function(List<String>) onConfirm;
  
  const _ContextFileSelectionSheet({
    this.projectPath,
    required this.selectedFiles,
    required this.onConfirm,
  });

  @override
  State<_ContextFileSelectionSheet> createState() => _ContextFileSelectionSheetState();
}

class _ContextFileSelectionSheetState extends State<_ContextFileSelectionSheet> {
  final Set<String> _selectedFiles = {};
  List<FileSystemEntity> _files = [];
  bool _isLoading = true;
  String? _currentPath;
  
  @override
  void initState() {
    super.initState();
    _selectedFiles.addAll(widget.selectedFiles);
    _currentPath = widget.projectPath;
    _loadFiles();
  }
  
  Future<void> _loadFiles() async {
    if (_currentPath == null) {
      setState(() {
        _files = [];
        _isLoading = false;
      });
      return;
    }
    
    try {
      final dir = Directory(_currentPath!);
      final entities = await dir.list().toList();
      
      entities.sort((a, b) {
        if (a is Directory && b is! Directory) return -1;
        if (a is! Directory && b is Directory) return 1;
        return p.basename(a.path).compareTo(p.basename(b.path));
      });
      
      setState(() {
        _files = entities.where((e) {
          final name = p.basename(e.path);
          return !name.startsWith('.');
        }).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _files = [];
        _isLoading = false;
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              // 标题栏
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Theme.of(context).dividerColor),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.folder_open, color: Colors.teal),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '选择上下文文件',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '选中的文件内容将作为AI对话的上下文',
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '已选 ${_selectedFiles.length} 个',
                      style: TextStyle(
                        fontSize: 12,
                        color: _selectedFiles.isNotEmpty ? Colors.teal : null,
                      ),
                    ),
                  ],
                ),
              ),
              
              // 路径导航
              if (_currentPath != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_upward, size: 20),
                        onPressed: () {
                          final parent = Directory(_currentPath!).parent.path;
                          setState(() {
                            _currentPath = parent;
                            _isLoading = true;
                          });
                          _loadFiles();
                        },
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: _buildPathBreadcrumbs(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              
              // 文件列表
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _files.isEmpty
                        ? const Center(child: Text('空目录'))
                        : ListView.builder(
                            controller: scrollController,
                            itemCount: _files.length,
                            itemBuilder: (context, index) {
                              final file = _files[index];
                              final name = p.basename(file.path);
                              final isDir = file is Directory;
                              
                              return ListTile(
                                leading: isDir
                                    ? const Icon(Icons.folder, color: Colors.amber)
                                    : Icon(
                                        _getFileIcon(p.extension(name).replaceFirst('.', '')),
                                        color: _getFileColor(p.extension(name).replaceFirst('.', '')),
                                      ),
                                title: Text(name),
                                subtitle: isDir ? const Text('文件夹', style: TextStyle(fontSize: 10)) : null,
                                trailing: !isDir
                                    ? Checkbox(
                                        value: _selectedFiles.contains(file.path),
                                        onChanged: (value) {
                                          setState(() {
                                            if (value == true) {
                                              _selectedFiles.add(file.path);
                                            } else {
                                              _selectedFiles.remove(file.path);
                                            }
                                          });
                                        },
                                      )
                                    : IconButton(
                                        icon: const Icon(Icons.chevron_right),
                                        onPressed: () {
                                          setState(() {
                                            _currentPath = file.path;
                                            _isLoading = true;
                                          });
                                          _loadFiles();
                                        },
                                      ),
                                onTap: isDir
                                    ? () {
                                        setState(() {
                                          _currentPath = file.path;
                                          _isLoading = true;
                                        });
                                        _loadFiles();
                                      }
                                    : () {
                                        setState(() {
                                          if (_selectedFiles.contains(file.path)) {
                                            _selectedFiles.remove(file.path);
                                          } else {
                                            _selectedFiles.add(file.path);
                                          }
                                        });
                                      },
                              );
                            },
                          ),
              ),
              
              // 底部按钮
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: Theme.of(context).dividerColor),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          setState(() => _selectedFiles.clear());
                        },
                        child: const Text('清空'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          widget.onConfirm(_selectedFiles.toList());
                          Navigator.pop(context);
                        },
                        child: Text('确定 (${_selectedFiles.length})'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
  
  List<Widget> _buildPathBreadcrumbs() {
    if (_currentPath == null) return [];
    
    final parts = _currentPath!.split('/');
    final widgets = <Widget>[];
    
    for (int i = 0; i < parts.length; i++) {
      if (i > 0) {
        widgets.add(const Icon(Icons.chevron_right, size: 16));
      }
      widgets.add(
        InkWell(
          onTap: () {
            final newPath = parts.sublist(0, i + 1).join('/');
            setState(() {
              _currentPath = newPath;
              _isLoading = true;
            });
            _loadFiles();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: i == parts.length - 1
                  ? Theme.of(context).colorScheme.primaryContainer
                  : null,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              parts[i].isEmpty ? '/' : parts[i],
              style: TextStyle(
                fontSize: 12,
                color: i == parts.length - 1
                    ? Theme.of(context).colorScheme.onPrimaryContainer
                    : null,
              ),
            ),
          ),
        ),
      );
    }
    
    return widgets;
  }
  
  /// 获取文件图标
  IconData _getFileIcon(String extension) {
    switch (extension.toLowerCase()) {
      case 'dart':
        return Icons.code;
      case 'py':
        return Icons.code;
      case 'js':
      case 'ts':
        return Icons.javascript;
      case 'java':
        return Icons.coffee;
      case 'go':
        return Icons.code;
      case 'rs':
        return Icons.settings;
      case 'html':
        return Icons.html;
      case 'css':
        return Icons.style;
      case 'json':
        return Icons.data_object;
      case 'yaml':
      case 'yml':
        return Icons.settings;
      case 'md':
        return Icons.description;
      default:
        return Icons.insert_drive_file;
    }
  }
  
  /// 获取文件颜色
  Color _getFileColor(String extension) {
    switch (extension.toLowerCase()) {
      case 'dart':
        return Colors.blue;
      case 'py':
        return Colors.green;
      case 'js':
        return Colors.yellow;
      case 'java':
        return Colors.orange;
      case 'html':
        return Colors.orange;
      case 'css':
        return Colors.blue;
      case 'json':
        return Colors.amber;
      case 'yaml':
      case 'yml':
        return Colors.cyan;
      default:
        return Colors.grey;
    }
  }
}

/// 创建项目底部弹窗
class _CreateProjectSheet extends StatefulWidget {
  final Function(String name, String template) onProjectCreated;
  
  const _CreateProjectSheet({required this.onProjectCreated});

  @override
  State<_CreateProjectSheet> createState() => _CreateProjectSheetState();
}

class _CreateProjectSheetState extends State<_CreateProjectSheet> {
  final _nameController = TextEditingController(text: 'my_project');
  String _selectedTemplate = 'flutter';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.create_new_folder),
              const SizedBox(width: 8),
              Text(
                '创建项目',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: '项目名称',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.folder),
            ),
          ),
          const SizedBox(height: 16),
          const Text('选择模板'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Flutter'),
                selected: _selectedTemplate == 'flutter',
                onSelected: (selected) {
                  if (selected) setState(() => _selectedTemplate = 'flutter');
                },
              ),
              ChoiceChip(
                label: const Text('Python'),
                selected: _selectedTemplate == 'python',
                onSelected: (selected) {
                  if (selected) setState(() => _selectedTemplate = 'python');
                },
              ),
              ChoiceChip(
                label: const Text('Node.js'),
                selected: _selectedTemplate == 'nodejs',
                onSelected: (selected) {
                  if (selected) setState(() => _selectedTemplate = 'nodejs');
                },
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                final name = _nameController.text.trim();
                if (name.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('请输入项目名称')),
                  );
                  return;
                }
                widget.onProjectCreated(name, _selectedTemplate);
              },
              icon: const Icon(Icons.add),
              label: const Text('创建'),
            ),
          ),
        ],
      ),
    );
  }
}


/// 文件检查选择底部弹窗（带代码预览）
class _FileCheckSelectionSheet extends StatefulWidget {
  final String? projectPath;
  final List<String> selectedFiles;
  final Function(List<String>) onConfirm;
  
  const _FileCheckSelectionSheet({
    this.projectPath,
    required this.selectedFiles,
    required this.onConfirm,
  });

  @override
  State<_FileCheckSelectionSheet> createState() => _FileCheckSelectionSheetState();
}

class _FileCheckSelectionSheetState extends State<_FileCheckSelectionSheet> {
  final Set<String> _selectedFiles = {};
  List<FileSystemEntity> _files = [];
  bool _isLoading = true;
  String? _currentPath;
  Map<String, String> _fileContents = {};
  
  @override
  void initState() {
    super.initState();
    _selectedFiles.addAll(widget.selectedFiles);
    _currentPath = widget.projectPath;
    _loadFiles();
  }
  
  Future<void> _loadFiles() async {
    if (_currentPath == null) {
      setState(() {
        _files = [];
        _isLoading = false;
      });
      return;
    }
    
    try {
      final dir = Directory(_currentPath!);
      final entities = await dir.list().toList();
      
      entities.sort((a, b) {
        if (a is Directory && b is! Directory) return -1;
        if (a is! Directory && b is Directory) return 1;
        return p.basename(a.path).compareTo(p.basename(b.path));
      });
      
      setState(() {
        _files = entities.where((e) {
          final name = p.basename(e.path);
          return !name.startsWith('.');
        }).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _files = [];
        _isLoading = false;
      });
    }
  }
  
  Future<void> _loadFileContent(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        final content = await file.readAsString();
        setState(() {
          _fileContents[filePath] = content.length > 5000 
              ? '${content.substring(0, 5000)}\n\n... (内容过长，已截断)' 
              : content;
        });
      }
    } catch (e) {
      debugPrint('Failed to load file: $e');
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              // 标题栏
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Theme.of(context).dividerColor),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.search, color: Colors.orange),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '选择要检查的文件',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'AI将分析文件并提供修改建议',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '已选 ${_selectedFiles.length} 个',
                      style: TextStyle(
                        fontSize: 12,
                        color: _selectedFiles.isNotEmpty ? Colors.orange : null,
                      ),
                    ),
                  ],
                ),
              ),
              
              // 路径导航
              if (_currentPath != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_upward, size: 20),
                        onPressed: () {
                          final parent = Directory(_currentPath!).parent.path;
                          setState(() {
                            _currentPath = parent;
                            _isLoading = true;
                          });
                          _loadFiles();
                        },
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: _buildPathBreadcrumbs(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              
              // 文件列表
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _files.isEmpty
                        ? const Center(child: Text('空目录'))
                        : ListView.builder(
                            controller: scrollController,
                            itemCount: _files.length,
                            itemBuilder: (context, index) {
                              final file = _files[index];
                              final name = p.basename(file.path);
                              final isDir = file is Directory;
                              final isSelected = _selectedFiles.contains(file.path);
                              
                              return Column(
                                children: [
                                  ListTile(
                                    leading: isDir
                                        ? const Icon(Icons.folder, color: Colors.amber)
                                        : Icon(
                                            _getFileIcon(p.extension(name).replaceFirst('.', '')),
                                            color: isSelected ? Colors.orange : _getFileColor(p.extension(name).replaceFirst('.', '')),
                                          ),
                                    title: Text(
                                      name,
                                      style: TextStyle(
                                        fontWeight: isSelected ? FontWeight.bold : null,
                                        color: isSelected ? Colors.orange : null,
                                      ),
                                    ),
                                    subtitle: isDir 
                                        ? const Text('文件夹', style: TextStyle(fontSize: 10)) 
                                        : Text(
                                            _fileContents.containsKey(file.path) 
                                                ? '${_fileContents[file.path]!.length} 字符' 
                                                : '点击预览内容',
                                            style: const TextStyle(fontSize: 10),
                                          ),
                                    trailing: !isDir
                                        ? Checkbox(
                                            value: isSelected,
                                            onChanged: (value) {
                                              setState(() {
                                                if (value == true) {
                                                  _selectedFiles.add(file.path);
                                                  _loadFileContent(file.path);
                                                } else {
                                                  _selectedFiles.remove(file.path);
                                                  _fileContents.remove(file.path);
                                                }
                                              });
                                            },
                                          )
                                        : IconButton(
                                            icon: const Icon(Icons.chevron_right),
                                            onPressed: () {
                                              setState(() {
                                                _currentPath = file.path;
                                                _isLoading = true;
                                              });
                                              _loadFiles();
                                            },
                                          ),
                                    onTap: isDir
                                        ? () {
                                            setState(() {
                                              _currentPath = file.path;
                                              _isLoading = true;
                                            });
                                            _loadFiles();
                                          }
                                        : () {
                                            _showFilePreview(file.path, name);
                                          },
                                  ),
                                  // 显示选中文件的内容预览
                                  if (isSelected && _fileContents.containsKey(file.path))
                                    Container(
                                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.shade50,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: Colors.orange.shade200),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(Icons.preview, size: 14, color: Colors.orange.shade700),
                                              const SizedBox(width: 4),
                                              Text(
                                                '内容预览',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.orange.shade700,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Container(
                                            constraints: const BoxConstraints(maxHeight: 100),
                                            child: SingleChildScrollView(
                                              child: Text(
                                                _fileContents[file.path]!,
                                                style: const TextStyle(
                                                  fontFamily: 'monospace',
                                                  fontSize: 10,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              );
                            },
                          ),
              ),
              
              // 底部按钮
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: Theme.of(context).dividerColor),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('取消'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _selectedFiles.isEmpty
                            ? null
                            : () {
                                widget.onConfirm(_selectedFiles.toList());
                                Navigator.pop(context);
                              },
                        icon: const Icon(Icons.search),
                        label: Text('检查 ${_selectedFiles.length} 个文件'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.orange,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
  
  void _showFilePreview(String filePath, String fileName) async {
    await _loadFileContent(filePath);
    if (!mounted) return;
    
    final content = _fileContents[filePath] ?? '无法读取文件内容';
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(_getFileIcon(p.extension(fileName).replaceFirst('.', '')), color: Colors.orange),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                fileName,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: SingleChildScrollView(
            child: SelectableText(
              content,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
  
  List<Widget> _buildPathBreadcrumbs() {
    if (_currentPath == null) return [];
    
    final parts = _currentPath!.split('/');
    final widgets = <Widget>[];
    
    for (int i = 0; i < parts.length; i++) {
      if (i > 0) {
        widgets.add(const Icon(Icons.chevron_right, size: 16));
      }
      widgets.add(
        InkWell(
          onTap: () {
            final newPath = parts.sublist(0, i + 1).join('/');
            setState(() {
              _currentPath = newPath;
              _isLoading = true;
            });
            _loadFiles();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: i == parts.length - 1
                  ? Theme.of(context).colorScheme.primaryContainer
                  : null,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              parts[i].isEmpty ? '/' : parts[i],
              style: TextStyle(
                fontSize: 12,
                color: i == parts.length - 1
                    ? Theme.of(context).colorScheme.onPrimaryContainer
                    : null,
              ),
            ),
          ),
        ),
      );
    }
    
    return widgets;
  }
  
  IconData _getFileIcon(String extension) {
    switch (extension.toLowerCase()) {
      case 'dart': return Icons.code;
      case 'py': return Icons.code;
      case 'js': case 'ts': return Icons.javascript;
      case 'java': return Icons.coffee;
      case 'go': return Icons.code;
      case 'rs': return Icons.settings;
      case 'html': return Icons.html;
      case 'css': return Icons.style;
      case 'json': return Icons.data_object;
      case 'yaml': case 'yml': return Icons.settings;
      case 'md': return Icons.description;
      default: return Icons.insert_drive_file;
    }
  }
  
  Color _getFileColor(String extension) {
    switch (extension.toLowerCase()) {
      case 'dart': return Colors.blue;
      case 'py': return Colors.green;
      case 'js': return Colors.yellow;
      case 'java': return Colors.orange;
      case 'html': return Colors.orange;
      case 'css': return Colors.blue;
      case 'json': return Colors.amber;
      case 'yaml': case 'yml': return Colors.cyan;
      default: return Colors.grey;
    }
  }
}
