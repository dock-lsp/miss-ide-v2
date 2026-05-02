import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:miss_ide/features/file_manager/project_directory.dart';
import 'package:miss_ide/features/editor/editor_settings.dart';
import 'package:miss_ide/features/editor/syntax_highlighter.dart';

/// VS Code Dark+ 主题颜色常量
class VSCodeColors {
  // 主题色
  static const Color editorBackground = Color(0xFF1E1E1E);
  static const Color sidebarBackground = Color(0xFF252526);
  static const Color activityBarBackground = Color(0xFF333333);
  static const Color statusBarBackground = Color(0xFF007ACC);
  static const Color tabBackground = Color(0xFF2D2D2D);
  static const Color tabActiveBackground = Color(0xFF1E1E1E);
  
  // 文字颜色
  static const Color tabText = Color(0xFFCCCCCC);
  static const Color lineNumberColor = Color(0xFF858585);
  static const Color currentLineNumber = Color(0xFFC6C6C6);
  static const Color statusBarText = Color(0xFFFFFFFF);
  
  // 边框颜色
  static const Color borderColor = Color(0xFF3C3C3C);
  static const Color lineNumberBorder = Color(0xFF2D2D2D);
  
  // 当前行高亮
  static const Color currentLineHighlight = Color(0xFF264F78);
}

/// 根据背景色获取动态编辑器颜色
class DynamicEditorColors {
  final Color backgroundColor;
  final Color textColor;
  
  DynamicEditorColors({required this.backgroundColor, required this.textColor});
  
  /// 判断是否是深色背景
  bool get isDarkBackground {
    final luminance = backgroundColor.computeLuminance();
    return luminance < 0.5;
  }
  
  /// 侧边栏背景色（比主背景稍亮/暗）
  Color get sidebarBackground {
    if (isDarkBackground) {
      return _lightenColor(backgroundColor, 0.05);
    } else {
      return _darkenColor(backgroundColor, 0.05);
    }
  }
  
  /// 标签栏背景
  Color get tabBackground {
    if (isDarkBackground) {
      return _lightenColor(backgroundColor, 0.08);
    } else {
      return _darkenColor(backgroundColor, 0.08);
    }
  }
  
  /// 活动标签背景
  Color get tabActiveBackground => backgroundColor;
  
  /// 文字颜色
  Color get tabText => textColor;
  
  /// 行号颜色（文字颜色的淡化版本）
  Color get lineNumberColor {
    if (isDarkBackground) {
      return textColor.withOpacity(0.5);
    } else {
      return textColor.withOpacity(0.4);
    }
  }
  
  /// 当前行号颜色
  Color get currentLineNumber => textColor;
  
  /// 边框颜色
  Color get borderColor {
    if (isDarkBackground) {
      return _lightenColor(backgroundColor, 0.1);
    } else {
      return _darkenColor(backgroundColor, 0.1);
    }
  }
  
  /// 当前行高亮
  Color get currentLineHighlight {
    if (isDarkBackground) {
      return _lightenColor(backgroundColor, 0.1);
    } else {
      return _darkenColor(backgroundColor, 0.05);
    }
  }
  
  /// 状态栏背景（使用主题色或根据背景计算）
  Color get statusBarBackground {
    if (isDarkBackground) {
      return const Color(0xFF007ACC);
    } else {
      return const Color(0xFF007ACC);
    }
  }
  
  /// 状态栏文字
  Color get statusBarText => Colors.white;
  
  Color _lightenColor(Color color, double amount) {
    final hsl = HSLColor.fromColor(color);
    final lightness = (hsl.lightness + amount).clamp(0.0, 1.0);
    return hsl.withLightness(lightness).toColor();
  }
  
  Color _darkenColor(Color color, double amount) {
    final hsl = HSLColor.fromColor(color);
    final lightness = (hsl.lightness - amount).clamp(0.0, 1.0);
    return hsl.withLightness(lightness).toColor();
  }
}

/// 编码类型映射
class EncodingTypes {
  static const Map<String, String> commonEncodings = {
    'UTF-8': 'UTF-8',
    'UTF-16': 'UTF-16',
    'ASCII': 'ASCII',
    'ISO-8859-1': 'ISO-8859-1',
    'GBK': 'GBK',
    'GB2312': 'GB2312',
  };
}

class CodeEditorPage extends StatefulWidget {
  final String? filePath;
  final String? initialContent;
  final String? projectPath;

  const CodeEditorPage({
    super.key,
    this.filePath,
    this.initialContent,
    this.projectPath,
  });

  @override
  State<CodeEditorPage> createState() => _CodeEditorPageState();
}

class _CodeEditorPageState extends State<CodeEditorPage> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ScrollController _lineNumberScrollController = ScrollController();
  final FocusNode _editorFocusNode = FocusNode();
  final List<EditorTab> _tabs = [];
  int _currentTabIndex = 0;
  bool _hasChanges = false;
  String _currentFilePath = '';
  String _currentLanguage = 'Dart';
  String? _currentProjectPath;
  bool _isDirectoryExpanded = false;
  
  // 当前编码
  String _currentEncoding = 'UTF-8';
  
  // 当前行高亮
  int _currentHighlightedLine = 1;
  
  // 语法高亮相关
  List<TextSpan> _highlightedSpans = [];
  bool _syntaxHighlightingEnabled = true;
  
  // 自动保存相关
  Timer? _autoSaveTimer;
  bool _isAutoSaving = false;
  
  // 编辑器设置
  EditorSettings _editorSettings = EditorSettings();
  
  /// 获取动态编辑器颜色
  DynamicEditorColors get _colors => DynamicEditorColors(
    backgroundColor: _editorSettings.backgroundColor,
    textColor: _editorSettings.textColor,
  );

  @override
  void initState() {
    super.initState();
    _currentProjectPath = widget.projectPath;
    if (widget.initialContent != null) {
      _controller.text = widget.initialContent!;
    }
    if (widget.filePath != null) {
      _loadFile(widget.filePath!);
    }
    // 加载编辑器设置
    _loadEditorSettings();
    
    // 监听文本变化以更新语法高亮
    _controller.addListener(_onTextChanged);
    
    // 监听滚动以同步行号
    _scrollController.addListener(_syncLineNumberScroll);
  }

  @override
  void didUpdateWidget(CodeEditorPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 当 filePath 变化时，加载新文件
    if (widget.filePath != oldWidget.filePath && widget.filePath != null) {
      _loadFile(widget.filePath!);
    }
    // 当 projectPath 变化时更新
    if (widget.projectPath != oldWidget.projectPath) {
      _currentProjectPath = widget.projectPath;
    }
  }

  /// 同步行号和编辑器滚动
  void _syncLineNumberScroll() {
    if (_lineNumberScrollController.hasClients) {
      final offset = _scrollController.offset;
      _lineNumberScrollController.jumpTo(offset);
    }
  }

  Future<void> _loadEditorSettings() async {
    final settings = await EditorSettings.load();
    setState(() {
      _editorSettings = settings;
      _updateSyntaxHighlighting();
    });
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _scrollController.dispose();
    _lineNumberScrollController.dispose();
    _editorFocusNode.dispose();
    super.dispose();
  }
  
  /// 文本变化监听器 - 触发状态更新以重新渲染高亮
  void _onTextChanged() {
    _onContentChanged();
  }
  
  /// 更新语法高亮
  void _updateSyntaxHighlighting() {
    if (!_syntaxHighlightingEnabled) {
      _highlightedSpans = [];
      return;
    }
    
    // 根据语言类型更新高亮
    final code = _controller.text;
    _highlightedSpans = SyntaxHighlighter.highlight(
      code,
      _currentLanguage,
      defaultColor: _editorSettings.textColor,
      fontSize: _editorSettings.fontSize,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_tabs.isEmpty ? '代码编辑器' : _tabs[_currentTabIndex].fileName),
        leading: _currentProjectPath != null
            ? IconButton(
                icon: Icon(_isDirectoryExpanded ? Icons.menu_open : Icons.menu),
                onPressed: () {
                  setState(() {
                    _isDirectoryExpanded = !_isDirectoryExpanded;
                  });
                },
                tooltip: _isDirectoryExpanded ? '收起目录' : '展开目录',
              )
            : null,
        actions: [
          // 语法高亮开关
          if (_tabs.isNotEmpty)
            IconButton(
              icon: Icon(
                _syntaxHighlightingEnabled ? Icons.highlight : Icons.highlight_off,
                color: _syntaxHighlightingEnabled ? Colors.amber : Colors.grey,
              ),
              onPressed: () {
                setState(() {
                  _syntaxHighlightingEnabled = !_syntaxHighlightingEnabled;
                  _updateSyntaxHighlighting();
                });
              },
              tooltip: _syntaxHighlightingEnabled ? '关闭语法高亮' : '开启语法高亮',
            ),
          // 创建文件/文件夹按钮
          if (_currentProjectPath != null)
            PopupMenuButton<String>(
              icon: const Icon(Icons.add_circle_outline),
              tooltip: '创建',
              onSelected: (value) {
                if (value == 'file') {
                  _showCreateFileDialog();
                } else if (value == 'folder') {
                  _showCreateFolderDialog();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'file',
                  child: Row(
                    children: [
                      Icon(Icons.insert_drive_file, size: 20),
                      SizedBox(width: 12),
                      Text('创建文件'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'folder',
                  child: Row(
                    children: [
                      Icon(Icons.create_new_folder, size: 20),
                      SizedBox(width: 12),
                      Text('创建文件夹'),
                    ],
                  ),
                ),
              ],
            ),
          IconButton(
            icon: Icon(Icons.save, color: _hasChanges ? Colors.orange : null),
            onPressed: _saveCurrentFile,
            tooltip: '保存',
          ),
          IconButton(
            icon: const Icon(Icons.folder_open),
            onPressed: _openFile,
            tooltip: '打开文件',
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _newFile,
            tooltip: '新建文件',
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _showEditorSettingsDialog,
            tooltip: '编辑器设置',
          ),
          PopupMenuButton<String>(
            onSelected: _handleMenuAction,
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'find', child: Text('查找')),
              const PopupMenuItem(value: 'selectall', child: Text('全选')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // 主体内容区（标签栏 + 编辑区）
          Expanded(
            child: Row(
              children: [
                // 左侧项目目录
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: _isDirectoryExpanded && _currentProjectPath != null ? 200 : 0,
                  child: _isDirectoryExpanded && _currentProjectPath != null
                      ? Container(
                          color: _colors.sidebarBackground,
                          child: ProjectDirectoryPanel(
                            projectPath: _currentProjectPath!,
                            onFileSelected: _onFileSelectedFromDirectory,
                            onTabOperation: _handleTabOperation,
                            currentOpenFilePath: _tabs.isNotEmpty ? _tabs[_currentTabIndex].path : null,
                            openFilePaths: _tabs.map((t) => t.path).toList(),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                // 右侧编辑区
                Expanded(
                  child: Column(
                    children: [
                      // VS Code 风格顶部标签栏
                      if (_tabs.isNotEmpty)
                        Container(
                          height: 35,
                          color: _colors.tabBackground,
                          child: Row(
                            children: [
                              Expanded(
                                child: ListView.builder(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: _tabs.length,
                                  itemBuilder: (context, index) {
                                    final tab = _tabs[index];
                                    final isActive = index == _currentTabIndex;
                                    return GestureDetector(
                                      onTap: () => _switchTab(index),
                                      onLongPress: () => _showTabContextMenu(context, index),
                                      child: Container(
                                        constraints: const BoxConstraints(maxWidth: 200),
                                        padding: const EdgeInsets.symmetric(horizontal: 12),
                                        decoration: BoxDecoration(
                                          color: isActive 
                                              ? _colors.tabActiveBackground 
                                              : Colors.transparent,
                                          border: Border(
                                            top: BorderSide(
                                              color: isActive 
                                                  ? const Color(0xFF007ACC)  // VS Code 蓝色
                                                  : Colors.transparent,
                                              width: 2,
                                            ),
                                            right: BorderSide(
                                              color: _colors.borderColor,
                                              width: 1,
                                            ),
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              _getFileIcon(tab.fileName),
                                              size: 14,
                                              color: _getFileColor(tab.fileName),
                                            ),
                                            const SizedBox(width: 6),
                                            Flexible(
                                              child: Text(
                                                tab.fileName,
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: _colors.tabText,
                                                  fontWeight: isActive ? FontWeight.w500 : FontWeight.normal,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            if (tab.hasChanges)
                                              Container(
                                                margin: const EdgeInsets.only(left: 4),
                                                child: const Text('●', 
                                                  style: TextStyle(
                                                    color: Color(0xFFE8AB3D),  // VS Code 橙色
                                                    fontSize: 10,
                                                  )
                                                ),
                                              ),
                                            const SizedBox(width: 4),
                                            InkWell(
                                              onTap: () => _closeTab(index),
                                              borderRadius: BorderRadius.circular(8),
                                              child: Padding(
                                                padding: const EdgeInsets.all(2),
                                                child: Icon(
                                                  Icons.close,
                                                  size: 14,
                                                  color: _colors.tabText.withOpacity(0.7),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              // 标签栏右侧操作按钮
                              Container(
                                color: _colors.tabBackground,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _buildToolbarButton(
                                      icon: Icons.add,
                                      tooltip: '新建文件',
                                      onPressed: _newFile,
                                    ),
                                    _buildToolbarButton(
                                      icon: Icons.folder_open,
                                      tooltip: '打开文件',
                                      onPressed: _openFile,
                                    ),
                                    _buildToolbarButton(
                                      icon: Icons.save,
                                      tooltip: '保存',
                                      onPressed: _hasChanges ? _saveCurrentFile : null,
                                      iconColor: _hasChanges ? const Color(0xFFE8AB3D) : null,
                                    ),
                                    _buildToolbarButton(
                                      icon: Icons.settings,
                                      tooltip: '编辑器设置',
                                      onPressed: _showEditorSettingsDialog,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      // 编辑器工具栏
                      Container(
                        height: 28,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        color: _colors.sidebarBackground,
                        child: Row(
                          children: [
                            // 语言标签
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF3C3C3C),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                _currentLanguage,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFFCCCCCC),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            // 文件路径
                            Expanded(
                              child: Text(
                                _currentFilePath.isEmpty ? '(新建文件)' : _currentFilePath,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF808080),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            // 语法高亮状态
                            if (_syntaxHighlightingEnabled)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF007ACC).withOpacity(0.3),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: const Text(
                                  '语法高亮',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Color(0xFF007ACC),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      // 代码编辑区
                      Expanded(
                        child: _tabs.isEmpty
                            ? Container(
                                color: _colors.tabActiveBackground,
                                child: Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.code,
                                        size: 64,
                                        color: const Color(0xFF808080),
                                      ),
                                      const SizedBox(height: 16),
                                      const Text(
                                        '没有打开的文件',
                                        style: TextStyle(
                                          color: Color(0xFF808080),
                                          fontSize: 16,
                                        ),
                                      ),
                                      const SizedBox(height: 24),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          ElevatedButton.icon(
                                            onPressed: _openFile,
                                            icon: const Icon(Icons.folder_open, size: 18),
                                            label: const Text('打开文件'),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: const Color(0xFF007ACC),
                                              foregroundColor: Colors.white,
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          OutlinedButton.icon(
                                            onPressed: _newFile,
                                            icon: const Icon(Icons.add, size: 18),
                                            label: const Text('新建文件'),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: const Color(0xFFCCCCCC),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : _buildVSCodeEditor(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // VS Code 风格底部状态栏
          _buildStatusBar(),
        ],
      ),
    );
  }
  
  /// 构建工具栏按钮
  Widget _buildToolbarButton({
    required IconData icon,
    required String tooltip,
    VoidCallback? onPressed,
    Color? iconColor,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        child: Container(
          width: 35,
          height: 35,
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: 18,
            color: onPressed != null 
                ? (iconColor ?? _colors.tabText) 
                : _colors.tabText.withOpacity(0.3),
          ),
        ),
      ),
    );
  }
  
  /// 构建 VS Code 风格的编辑器 - 修复行号对齐问题
  Widget _buildVSCodeEditor() {
    final lineHeight = _editorSettings.fontSize * _editorSettings.lineHeight;
    final lineNumberWidth = _calculateLineNumberWidth();
    
    return Container(
      color: _colors.tabActiveBackground,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              // 行号区域 - 固定在左侧
              if (_editorSettings.showLineNumbers)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: lineNumberWidth,
                  child: Container(
                    color: _colors.sidebarBackground,
                    child: _buildLineNumbers(lineHeight, lineNumberWidth),
                  ),
                ),
              // 代码编辑区
              Positioned(
                left: lineNumberWidth,
                top: 0,
                right: 0,
                bottom: 0,
                child: _buildCodeArea(lineHeight),
              ),
            ],
          );
        },
      ),
    );
  }
  
  /// 构建行号区域
  Widget _buildLineNumbers(double lineHeight, double lineNumberWidth) {
    return ListView.builder(
      controller: _lineNumberScrollController,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: _getLineCount() + 100, // 预加载更多行
      itemBuilder: (context, index) {
        if (index >= _getLineCount()) {
          // 预渲染空白行
          return SizedBox(
            height: lineHeight,
            width: lineNumberWidth,
          );
        }
        
        final lineNumber = index + 1;
        final isCurrentLine = lineNumber == _currentHighlightedLine;
        
        return Container(
          height: lineHeight,
          width: lineNumberWidth,
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(
            color: isCurrentLine 
                ? _colors.currentLineHighlight.withOpacity(0.15)
                : Colors.transparent,
            border: Border(
              right: BorderSide(
                color: _colors.borderColor,
                width: 1,
              ),
            ),
          ),
          child: Text(
            '$lineNumber',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: _editorSettings.fontSize,
              height: _editorSettings.lineHeight,
              color: isCurrentLine 
                  ? _colors.currentLineNumber 
                  : _colors.lineNumberColor,
              fontWeight: isCurrentLine ? FontWeight.w500 : FontWeight.normal,
            ),
          ),
        );
      },
    );
  }
  
  /// 构建代码编辑区域
  Widget _buildCodeArea(double lineHeight) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        // 同步行号滚动
        if (notification is ScrollUpdateNotification) {
          if (_lineNumberScrollController.hasClients) {
            _lineNumberScrollController.jumpTo(notification.metrics.pixels);
          }
        }
        return false;
      },
      child: SingleChildScrollView(
        controller: _scrollController,
        physics: const ClampingScrollPhysics(),
        padding: EdgeInsets.only(
          top: 0,
          left: 12,
          right: 12,
        ),
        child: SizedBox(
          width: double.infinity,
          child: _buildHighlightedText(lineHeight),
        ),
      ),
    );
  }
  
  /// 构建带语法高亮的文本显示
  Widget _buildHighlightedText(double lineHeight) {
    final code = _controller.text;
    
    // 如果没有内容或语法高亮未启用，返回普通文本
    if (code.isEmpty || !_syntaxHighlightingEnabled) {
      return Text(
        code.isEmpty ? ' ' : code,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: _editorSettings.fontSize,
          height: _editorSettings.lineHeight,
          color: _syntaxHighlightingEnabled ? Colors.transparent : _colors.tabText,
        ),
      );
    }
    
    // 生成语法高亮文本
    final spans = SyntaxHighlighter.highlight(
      code,
      _currentLanguage,
      defaultColor: Colors.transparent, // 让 TextField 接收输入
      fontSize: _editorSettings.fontSize,
    );
    
    // 如果高亮结果只有一段且是空文本，显示空格保持高度
    if (spans.length == 1 && (spans.first.text?.isEmpty ?? true)) {
      return Text(
        ' ',
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: _editorSettings.fontSize,
          height: _editorSettings.lineHeight,
        ),
      );
    }
    
    return Stack(
      children: [
        // 高亮文本层（只读显示）
        IgnorePointer(
          child: RichText(
            text: TextSpan(
              children: spans,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: _editorSettings.fontSize,
                height: _editorSettings.lineHeight,
              ),
            ),
          ),
        ),
        // 透明输入层
        TextField(
          controller: _controller,
          focusNode: _editorFocusNode,
          autofocus: true,
          maxLines: null,
          expands: false,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          scrollPhysics: const NeverScrollableScrollPhysics(),
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: _editorSettings.fontSize,
            height: _editorSettings.lineHeight,
            color: Colors.transparent, // 透明，让高亮层显示
          ),
          cursorColor: const Color(0xFFAEAFAD),
          cursorWidth: 2,
          decoration: InputDecoration(
            border: InputBorder.none,
            contentPadding: EdgeInsets.zero,
            fillColor: Colors.transparent,
            filled: true,
            isDense: true,
          ),
          onChanged: (value) {
            _updateCurrentLine();
            _onContentChanged();
          },
        ),
      ],
    );
  }
  
  /// 更新当前行号
  void _updateCurrentLine() {
    final cursorPos = _controller.selection.baseOffset;
    if (cursorPos < 0) return;
    final text = _controller.text.substring(0, cursorPos);
    final newLine = text.split('\n').length;
    if (newLine != _currentHighlightedLine) {
      setState(() {
        _currentHighlightedLine = newLine;
      });
    }
  }
  
  /// 构建 VS Code 风格底部状态栏
  Widget _buildStatusBar() {
    return Container(
      height: 24,
      color: _colors.statusBarBackground,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          // 左侧：Git 分支、错误/警告数量
          _buildStatusBarItem(
            icon: Icons.account_tree,
            text: 'main',
            color: _colors.statusBarText,
          ),
          const SizedBox(width: 8),
          // 错误数量
          _buildStatusBarItem(
            icon: Icons.error_outline,
            text: '0',
            color: const Color(0xFFF14C4C),
            tooltip: '错误',
          ),
          const SizedBox(width: 4),
          // 警告数量
          _buildStatusBarItem(
            icon: Icons.warning_amber,
            text: '0',
            color: const Color(0xFFCCA700),
            tooltip: '警告',
          ),
          const Spacer(),
          // 右侧：位置信息
          _buildStatusBarItem(
            text: '行 $_currentHighlightedLine',
            color: _colors.statusBarText,
            tooltip: '当前行',
          ),
          const SizedBox(width: 8),
          _buildStatusBarItem(
            text: '列 ${_getCurrentColumn()}',
            color: _colors.statusBarText,
            tooltip: '当前列',
          ),
          const SizedBox(width: 8),
          // 文件编码
          GestureDetector(
            onTap: _showEncodingSelector,
            child: _buildStatusBarItem(
              text: _currentEncoding,
              color: _colors.statusBarText,
              tooltip: '文件编码 (点击更改)',
            ),
          ),
          const SizedBox(width: 8),
          // 文件类型
          _buildStatusBarItem(
            text: _currentLanguage,
            color: _colors.statusBarText,
            tooltip: '语言模式',
          ),
          const SizedBox(width: 8),
          // 缩进方式
          _buildStatusBarItem(
            text: _editorSettings.useSpaces ? '空格: ${_editorSettings.tabSize}' : 'Tab Size: ${_editorSettings.tabSize}',
            color: _colors.statusBarText,
            tooltip: '缩进方式',
          ),
        ],
      ),
    );
  }
  
  /// 构建状态栏项
  Widget _buildStatusBarItem({
    IconData? icon,
    required String text,
    required Color color,
    String? tooltip,
  }) {
    return Tooltip(
      message: tooltip ?? '',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 2),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
  
  /// 显示编码选择器
  void _showEncodingSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _colors.sidebarBackground,
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                '选择文件编码',
                style: TextStyle(
                  color: _colors.tabText,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Divider(color: _colors.borderColor),
            ...EncodingTypes.commonEncodings.entries.map((entry) {
              final isSelected = entry.key == _currentEncoding;
              return ListTile(
                leading: Icon(
                  isSelected ? Icons.check : null,
                  color: const Color(0xFF007ACC),
                ),
                title: Text(
                  entry.key,
                  style: TextStyle(
                    color: isSelected ? const Color(0xFF007ACC) : _colors.tabText,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                subtitle: Text(
                  entry.value,
                  style: const TextStyle(
                    color: Color(0xFF808080),
                    fontSize: 12,
                  ),
                ),
                onTap: () {
                  setState(() {
                    _currentEncoding = entry.key;
                  });
                  Navigator.pop(context);
                },
              );
            }),
          ],
        ),
      ),
    );
  }
  
  void _onContentChanged() {
    if (!_hasChanges && _tabs.isNotEmpty) {
      setState(() {
        _hasChanges = true;
        _tabs[_currentTabIndex].hasChanges = true;
      });
    }
    
    // 自动保存
    if (_editorSettings.autoSave) {
      _autoSaveTimer?.cancel();
      _autoSaveTimer = Timer(Duration(seconds: _editorSettings.autoSaveDelay), () {
        if (_hasChanges && _tabs.isNotEmpty && _tabs[_currentTabIndex].path.isNotEmpty) {
          _autoSave();
        }
      });
    }
  }
  
  Future<void> _autoSave() async {
    if (_isAutoSaving || _tabs.isEmpty) return;
    
    final tab = _tabs[_currentTabIndex];
    if (tab.path.isEmpty || !File(tab.path).existsSync()) return;
    
    _isAutoSaving = true;
    try {
      final file = File(tab.path);
      await file.writeAsString(_controller.text);
      if (mounted) {
        setState(() {
          _tabs[_currentTabIndex].hasChanges = false;
          _hasChanges = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('已自动保存'),
            backgroundColor: Colors.blue,
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      debugPrint('自动保存失败: $e');
    }
    _isAutoSaving = false;
  }

  int _getLineCount() {
    final text = _controller.text;
    if (text.isEmpty) return 1;
    return text.split('\n').length;
  }

  /// 计算行号面板宽度，基于最大行号位数动态调整
  /// 使用 monospace 字体精确计算
  double _calculateLineNumberWidth() {
    final lineCount = _getLineCount();
    // 计算行号的位数
    final digits = lineCount.toString().length;
    // monospace 字体中每个数字的宽度约为 fontSize * 0.6
    // 对于 14px 字体，数字宽度约为 8.4px
    // 加上 8px 的右侧 padding
    final digitWidth = _editorSettings.fontSize * 0.6;
    final width = (digits * digitWidth) + 12;
    // 限制在 40-80 之间，最小 40px 足够显示 4 位数字
    return width.clamp(40.0, 80.0);
  }

  int _getCurrentLine() {
    final text = _controller.text;
    final cursorPos = _controller.selection.baseOffset;
    if (cursorPos < 0) return 1;
    return text.substring(0, cursorPos).split('\n').length;
  }

  int _getCurrentColumn() {
    final text = _controller.text;
    final cursorPos = _controller.selection.baseOffset;
    if (cursorPos < 0) return 1;
    final lines = text.substring(0, cursorPos).split('\n');
    return lines.last.length + 1;
  }

  IconData _getFileIcon(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'dart': return Icons.code;
      case 'java': return Icons.coffee;
      case 'kt': return Icons.code;
      case 'py': return Icons.code;
      case 'js': return Icons.javascript;
      case 'ts': return Icons.code;
      case 'html': return Icons.html;
      case 'css': return Icons.style;
      case 'json': return Icons.data_object;
      case 'yaml':
      case 'yml': return Icons.settings;
      case 'md': return Icons.description;
      case 'xml': return Icons.code;
      default: return Icons.insert_drive_file;
    }
  }

  Color _getFileColor(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'dart': return Colors.blue;
      case 'java': return Colors.orange;
      case 'kt': return Colors.purple;
      case 'py': return Colors.green;
      case 'js': return Colors.yellow;
      case 'ts': return Colors.blue;
      case 'html': return Colors.orange;
      case 'css': return Colors.blue;
      case 'json': return Colors.amber;
      case 'yaml':
      case 'yml': return Colors.cyan;
      default: return Colors.grey;
    }
  }

  String _getLanguage(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'dart': return 'Dart';
      case 'java': return 'Java';
      case 'kt': return 'Kotlin';
      case 'py': return 'Python';
      case 'js': return 'JavaScript';
      case 'ts': return 'TypeScript';
      case 'html': return 'HTML';
      case 'css': return 'CSS';
      case 'json': return 'JSON';
      case 'yaml':
      case 'yml': return 'YAML';
      case 'md': return 'Markdown';
      case 'xml': return 'XML';
      case 'sql': return 'SQL';
      case 'sh': return 'Shell';
      case 'c': return 'C';
      case 'cpp': return 'C++';
      case 'go': return 'Go';
      case 'rs': return 'Rust';
      case 'php': return 'PHP';
      case 'rb': return 'Ruby';
      case 'swift': return 'Swift';
      default: return 'Text';
    }
  }

  Future<void> _openFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(allowMultiple: true);
      if (result != null && result.files.isNotEmpty) {
        for (var file in result.files) {
          if (file.path != null) {
            await _loadFile(file.path!);
          }
        }
      }
    } catch (e) {
      _showError('打开文件失败: $e');
    }
  }

  Future<void> _loadFile(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        _showError('文件不存在');
        return;
      }
      final content = await file.readAsString();
      final fileName = path.split('/').last;
      
      final existingIndex = _tabs.indexWhere((t) => t.path == path);
      if (existingIndex >= 0) {
        _switchTab(existingIndex);
        return;
      }
      
      setState(() {
        _tabs.add(EditorTab(
          fileName: fileName,
          path: path,
          content: content,
        ));
        _currentTabIndex = _tabs.length - 1;
        _controller.text = content;
        _currentFilePath = path;
        _currentLanguage = _getLanguage(fileName);
        _hasChanges = false;
        _updateSyntaxHighlighting();
      });
    } catch (e) {
      _showError('读取文件失败: $e');
    }
  }

  Future<void> _saveCurrentFile() async {
    if (_tabs.isEmpty) return;
    final tab = _tabs[_currentTabIndex];
    
    if (tab.path.isEmpty) {
      await _saveAs();
      return;
    }
    
    try {
      final file = File(tab.path);
      await file.writeAsString(_controller.text);
      setState(() {
        _tabs[_currentTabIndex].hasChanges = false;
        _hasChanges = false;
      });
      _showSuccess('文件已保存');
    } catch (e) {
      _showError('保存失败: $e');
    }
  }

  Future<void> _saveAs() async {
    // 修改：如果当前文件已有名称，直接保存，不再弹出对话框
    final currentTab = _tabs.isNotEmpty ? _tabs[_currentTabIndex] : null;
    final existingFileName = currentTab?.fileName ?? '';
    
    // 如果有文件名且不是新建文件（路径为空），直接保存
    if (existingFileName.isNotEmpty && (currentTab?.path.isEmpty ?? true)) {
      // 首次保存，需要用户输入文件名
      await _saveAsWithDialog();
    } else if (currentTab?.path.isNotEmpty ?? false) {
      // 文件已有路径，直接保存
      try {
        final file = File(currentTab!.path);
        await file.writeAsString(_controller.text);
        setState(() {
          _tabs[_currentTabIndex].hasChanges = false;
          _hasChanges = false;
        });
        _showSuccess('文件已保存');
      } catch (e) {
        _showError('保存失败: $e');
      }
    } else {
      // 真的没有文件名，弹出对话框
      await _saveAsWithDialog();
    }
  }
  
  /// 另存为 - 弹出文件名输入对话框
  Future<void> _saveAsWithDialog() async {
    final TextEditingController nameController = TextEditingController(text: 'untitled.txt');
    
    final fileName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('保存文件'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: '文件名',
            hintText: '输入文件名（含扩展名）',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, nameController.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    
    if (fileName == null || fileName.isEmpty) return;
    
    // 保存到项目目录
    String outputPath;
    if (_currentProjectPath != null && _currentProjectPath!.isNotEmpty) {
      outputPath = '$_currentProjectPath/$fileName';
    } else {
      // 如果没有项目路径，使用应用目录
      final appDir = await getApplicationDocumentsDirectory();
      outputPath = '${appDir.path}/$fileName';
    }
    
    try {
      final file = File(outputPath);
      // 确保目录存在
      final dir = file.parent;
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      await file.writeAsString(_controller.text);
      
      setState(() {
        if (_tabs.isEmpty) {
          _tabs.add(EditorTab(
            fileName: fileName,
            path: outputPath,
            content: _controller.text,
          ));
          _currentTabIndex = 0;
        } else {
          _tabs[_currentTabIndex] = EditorTab(
            fileName: fileName,
            path: outputPath,
            content: _controller.text,
          );
        }
        _currentFilePath = outputPath;
        _currentLanguage = _getLanguage(fileName);
        _hasChanges = false;
      });
      _showSuccess('文件已保存: $fileName');
    } catch (e) {
      _showError('保存失败: $e');
    }
  }

  /// 新建文件 - 优化：创建后直接保存到项目目录
  void _newFile() {
    // 如果有项目路径，直接创建并保存
    if (_currentProjectPath != null && _currentProjectPath!.isNotEmpty) {
      _newFileWithSave();
    } else {
      // 没有项目路径，创建临时文件（不保存）
      _newFileWithoutSave();
    }
  }
  
  /// 新建文件 - 有项目路径时，创建后直接保存
  void _newFileWithSave() {
    showDialog(
      context: context,
      builder: (context) {
        final TextEditingController nameController = TextEditingController();
        String selectedType = 'dart';
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text('新建文件'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 文件名输入框
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: '文件名',
                    hintText: '输入文件名（不含扩展名）',
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 16),
                // 文件类型下拉选择
                DropdownButtonFormField<String>(
                  value: selectedType,
                  decoration: const InputDecoration(labelText: '文件类型'),
                  items: [
                    'dart', 'java', 'kt', 'py', 'js', 'ts', 
                    'html', 'css', 'json', 'yaml', 'md', 'xml',
                    'txt', 'sql', 'sh', 'c', 'cpp', 'go', 'rs', 'php'
                  ]
                      .map((type) => DropdownMenuItem(value: type, child: Text('.$type')))
                      .toList(),
                  onChanged: (type) => setState(() => selectedType = type!),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
              FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  // 使用用户输入的文件名或默认值
                  String fileName = nameController.text.trim();
                  if (fileName.isEmpty) {
                    fileName = 'untitled';
                  }
                  if (!fileName.contains('.')) {
                    fileName = '$fileName.$selectedType';
                  }
                  _createNewFileAndSave(fileName, selectedType);
                },
                child: const Text('创建'),
              ),
            ],
          ),
        );
      },
    );
  }
  
  /// 新建文件 - 无项目路径时，创建临时文件
  void _newFileWithoutSave() {
    showDialog(
      context: context,
      builder: (context) {
        final TextEditingController nameController = TextEditingController();
        String selectedType = 'dart';
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text('新建文件'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 文件名输入框
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: '文件名',
                    hintText: '输入文件名（不含扩展名）',
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 16),
                // 文件类型下拉选择
                DropdownButtonFormField<String>(
                  value: selectedType,
                  decoration: const InputDecoration(labelText: '文件类型'),
                  items: [
                    'dart', 'java', 'kt', 'py', 'js', 'ts', 
                    'html', 'css', 'json', 'yaml', 'md', 'xml',
                    'txt', 'sql', 'sh', 'c', 'cpp', 'go', 'rs', 'php'
                  ]
                      .map((type) => DropdownMenuItem(value: type, child: Text('.$type')))
                      .toList(),
                  onChanged: (type) => setState(() => selectedType = type!),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
              FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  // 使用用户输入的文件名或默认值
                  String fileName = nameController.text.trim();
                  if (fileName.isEmpty) {
                    fileName = 'untitled';
                  }
                  _createNewFile(fileName, selectedType);
                },
                child: const Text('创建'),
              ),
            ],
          ),
        );
      },
    );
  }
  
  /// 创建新文件并保存到项目目录
  Future<void> _createNewFileAndSave(String fileName, String type) async {
    if (!fileName.endsWith('.$type')) {
      fileName = '$fileName.$type';
    }
    
    // 生成模板内容
    String template = _generateTemplate(fileName, type);
    
    try {
      // 保存到项目目录
      final filePath = p.join(_currentProjectPath!, fileName);
      final file = File(filePath);
      
      if (await file.exists()) {
        _showError('文件已存在: $fileName');
        return;
      }
      
      await file.writeAsString(template);
      _showSuccess('已创建并保存文件: $fileName');
      
      // 添加到标签页并打开
      setState(() {
        _tabs.add(EditorTab(
          fileName: fileName,
          path: filePath,
          content: template,
        ));
        _currentTabIndex = _tabs.length - 1;
        _controller.text = template;
        _currentFilePath = filePath;
        _currentLanguage = _getLanguage(fileName);
        _hasChanges = false;
        _updateSyntaxHighlighting();
      });
    } catch (e) {
      _showError('创建文件失败: $e');
    }
  }
  
  /// 生成代码模板
  String _generateTemplate(String name, String type) {
    switch (type) {
      case 'dart':
        return '// $name\n\nvoid main() {\n  // TODO: implement\n}\n';
      case 'java':
        return '// $name\n\npublic class ${name.replaceAll('.java', '')} {\n    public static void main(String[] args) {\n        // TODO: implement\n    }\n}\n';
      case 'py':
        return '# $name\n\ndef main():\n    # TODO: implement\n    pass\n\nif __name__ == "__main__":\n    main()\n';
      case 'js':
        return '// $name\n\nfunction main() {\n    // TODO: implement\n}\n\nmain();\n';
      case 'ts':
        return '// $name\n\nfunction main(): void {\n    // TODO: implement\n}\n\nmain();\n';
      case 'kt':
        return '// $name\n\nfun main() {\n    // TODO: implement\n}\n';
      case 'html':
        return '<!DOCTYPE html>\n<html>\n<head>\n    <title>$name</title>\n</head>\n<body>\n    <!-- TODO: implement -->\n</body>\n</html>\n';
      case 'css':
        return '/* $name */\n\n/* TODO: implement */\n';
      case 'json':
        return '{\n  \n}\n';
      case 'yaml':
        return '# $name\n\n';
      case 'md':
        return '# ${name.replaceAll('.md', '')}\n\n';
      case 'xml':
        return '<?xml version="1.0" encoding="UTF-8"?>\n<!-- $name -->\n';
      case 'sql':
        return '-- $name\n\n-- TODO: implement\n';
      case 'sh':
        return '#!/bin/bash\n# $name\n\n# TODO: implement\n';
      case 'c':
        return '// $name\n\n#include <stdio.h>\n\nint main() {\n    // TODO: implement\n    return 0;\n}\n';
      case 'cpp':
        return '// $name\n\n#include <iostream>\n\nint main() {\n    // TODO: implement\n    return 0;\n}\n';
      case 'go':
        return '// $name\n\npackage main\n\nimport "fmt"\n\nfunc main() {\n    // TODO: implement\n}\n';
      case 'rs':
        return '// $name\n\nfn main() {\n    // TODO: implement\n}\n';
      case 'php':
        return '<?php\n// $name\n\n// TODO: implement\n';
      default:
        return '';
    }
  }

  void _createNewFile(String name, String type) {
    if (!name.endsWith('.$type')) name = '$name.$type';
    String template = _generateTemplate(name, type);
    
    setState(() {
      _tabs.add(EditorTab(fileName: name, path: '', content: template));
      _currentTabIndex = _tabs.length - 1;
      _controller.text = template;
      _currentFilePath = '';
      _currentLanguage = _getLanguage(name);
      _hasChanges = true;
      _updateSyntaxHighlighting();
    });
  }

  void _switchTab(int index) {
    if (index < 0 || index >= _tabs.length) return;
    if (_tabs.isNotEmpty) _tabs[_currentTabIndex].content = _controller.text;
    
    setState(() {
      _currentTabIndex = index;
      _controller.text = _tabs[index].content;
      _currentFilePath = _tabs[index].path;
      _currentLanguage = _getLanguage(_tabs[index].fileName);
      _hasChanges = _tabs[index].hasChanges;
      _updateSyntaxHighlighting();
    });
  }

  void _handleMenuAction(String action) {
    switch (action) {
      case 'find':
        _showFindDialog();
        break;
      case 'selectall':
        _controller.selection = TextSelection(baseOffset: 0, extentOffset: _controller.text.length);
        break;
    }
  }

  void _showFindDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('查找'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: '输入搜索内容'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _findText(controller.text);
            },
            child: const Text('查找'),
          ),
        ],
      ),
    );
  }

  void _findText(String text) {
    if (text.isEmpty) return;
    final index = _controller.text.indexOf(text);
    if (index >= 0) {
      _controller.selection = TextSelection(baseOffset: index, extentOffset: index + text.length);
      _showSuccess('已找到');
    } else {
      _showError('未找到');
    }
  }

  void _onFileSelectedFromDirectory(String filePath) {
    _loadFile(filePath);
  }

  /// 处理来自目录面板的标签页操作
  void _handleTabOperation(String action, String? currentFilePath) {
    switch (action) {
      case 'close':
        // 关闭当前文件
        if (currentFilePath != null) {
          final index = _tabs.indexWhere((t) => t.path == currentFilePath);
          if (index >= 0) {
            _closeTab(index);
          }
        }
        break;
      case 'close_all':
        // 关闭所有文件
        _closeAllTabs();
        break;
      case 'close_others':
        // 关闭其他文件
        if (currentFilePath != null) {
          final index = _tabs.indexWhere((t) => t.path == currentFilePath);
          if (index >= 0) {
            _closeOtherTabs(index);
          }
        }
        break;
    }
  }

  /// 显示创建文件对话框
  void _showCreateFileDialog() {
    final TextEditingController nameController = TextEditingController();
    String selectedType = 'dart';
    
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.insert_drive_file, color: Colors.blue),
                SizedBox(width: 8),
                Text('创建文件'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: '文件名',
                    hintText: '输入文件名（不含扩展名）',
                    prefixIcon: Icon(Icons.edit),
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: selectedType,
                  decoration: const InputDecoration(labelText: '文件类型'),
                  items: [
                    'dart', 'java', 'kt', 'py', 'js', 'ts', 
                    'html', 'css', 'json', 'yaml', 'md', 'xml',
                    'txt', 'sql', 'sh', 'c', 'cpp', 'go', 'rs', 'php'
                  ]
                      .map((type) => DropdownMenuItem(value: type, child: Text('.$type')))
                      .toList(),
                  onChanged: (type) => setState(() => selectedType = type!),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton.icon(
                onPressed: () async {
                  Navigator.pop(context);
                  String fileName = nameController.text.trim();
                  if (fileName.isEmpty) {
                    fileName = 'untitled';
                  }
                  if (!fileName.contains('.')) {
                    fileName = '$fileName.$selectedType';
                  }
                  await _createFileInProject(fileName);
                },
                icon: const Icon(Icons.add),
                label: const Text('创建'),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 显示创建文件夹对话框
  void _showCreateFolderDialog() {
    final TextEditingController nameController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.create_new_folder, color: Colors.amber),
              SizedBox(width: 8),
              Text('创建文件夹'),
            ],
          ),
          content: TextField(
            controller: nameController,
            decoration: const InputDecoration(
              labelText: '文件夹名称',
              hintText: '输入文件夹名称',
              prefixIcon: Icon(Icons.folder),
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton.icon(
              onPressed: () async {
                Navigator.pop(context);
                final folderName = nameController.text.trim();
                if (folderName.isNotEmpty) {
                  await _createFolderInProject(folderName);
                }
              },
              icon: const Icon(Icons.add),
              label: const Text('创建'),
            ),
          ],
        );
      },
    );
  }

  /// 在项目中创建文件
  Future<void> _createFileInProject(String fileName) async {
    if (_currentProjectPath == null) {
      _showError('请先打开一个项目');
      return;
    }
    
    try {
      final filePath = p.join(_currentProjectPath!, fileName);
      final file = File(filePath);
      
      if (await file.exists()) {
        _showError('文件已存在: $fileName');
        return;
      }
      
      // 创建文件（带默认模板内容）
      String content = '';
      final ext = p.extension(fileName).toLowerCase();
      switch (ext) {
        case '.dart':
          content = '// $fileName\n\nvoid main() {\n  // TODO: implement\n}\n';
          break;
        case '.py':
          content = '# $fileName\n\ndef main():\n    pass\n\nif __name__ == "__main__":\n    main()\n';
          break;
        case '.java':
          content = '// $fileName\n\npublic class ${p.basenameWithoutExtension(fileName)} {\n    public static void main(String[] args) {\n    }\n}\n';
          break;
        case '.js':
          content = '// $fileName\n\nfunction main() {\n}\n\nmain();\n';
          break;
        case '.html':
          content = '<!DOCTYPE html>\n<html>\n<head>\n    <title>$fileName</title>\n</head>\n<body>\n</body>\n</html>\n';
          break;
        case '.json':
          content = '{\n  \n}\n';
          break;
        case '.md':
          content = '# ${p.basenameWithoutExtension(fileName)}\n\n';
          break;
        default:
          content = '';
      }
      
      await file.writeAsString(content);
      _showSuccess('已创建文件: $fileName');
      
      // 刷新文件树
      this.setState(() {});
      
      // 自动打开新创建的文件
      _loadFile(filePath);
    } catch (e) {
      _showError('创建文件失败: $e');
    }
  }

  /// 在项目中创建文件夹
  Future<void> _createFolderInProject(String folderName) async {
    if (_currentProjectPath == null) {
      _showError('请先打开一个项目');
      return;
    }
    
    try {
      final folderPath = p.join(_currentProjectPath!, folderName);
      final dir = Directory(folderPath);
      
      if (await dir.exists()) {
        _showError('文件夹已存在: $folderName');
        return;
      }
      
      await dir.create(recursive: true);
      _showSuccess('已创建文件夹: $folderName');
      
      // 刷新文件树
      setState(() {});
    } catch (e) {
      _showError('创建文件夹失败: $e');
    }
  }

  /// 显示编辑器设置对话框
  void _showEditorSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => _EditorSettingsDialog(
        settings: _editorSettings,
        onSave: (newSettings) async {
          await newSettings.save();
          setState(() {
            _editorSettings = newSettings;
            _updateSyntaxHighlighting();
          });
        },
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  /// 显示标签页上下文菜单
  void _showTabContextMenu(BuildContext context, int tabIndex) {
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final RenderBox button = context.findRenderObject() as RenderBox;
    final Offset position = button.localToGlobal(Offset.zero, ancestor: overlay);
    
    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, button.size.width, button.size.height),
        Offset.zero & overlay.size,
      ),
      items: [
        const PopupMenuItem(
          value: 'close',
          child: Row(
            children: [
              Icon(Icons.close, size: 18),
              SizedBox(width: 12),
              Text('关闭当前文件'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'close_all',
          child: Row(
            children: [
              Icon(Icons.close_fullscreen, size: 18),
              SizedBox(width: 12),
              Text('关闭所有文件'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'close_others',
          child: Row(
            children: [
              Icon(Icons.filter_alt_off, size: 18),
              SizedBox(width: 12),
              Text('关闭其他文件'),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value != null) {
        _handleTabMenuAction(value, tabIndex);
      }
    });
  }

  /// 处理标签页菜单操作
  void _handleTabMenuAction(String action, int tabIndex) {
    switch (action) {
      case 'close':
        _closeTab(tabIndex);
        break;
      case 'close_all':
        _closeAllTabs();
        break;
      case 'close_others':
        _closeOtherTabs(tabIndex);
        break;
    }
  }

  /// 关闭指定标签页
  void _closeTab(int index) {
    if (index < 0 || index >= _tabs.length) return;
    
    final tab = _tabs[index];
    
    // 如果有未保存的更改，提示用户
    if (tab.hasChanges) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('文件未保存'),
          content: Text('${tab.fileName} 有未保存的更改，是否保存？'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _removeTab(index);
              },
              child: const Text('不保存'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(context);
                // 保存并关闭
                if (index < _tabs.length) {
                  _switchTab(index);
                  await _saveCurrentFile();
                  _removeTab(index);
                }
              },
              child: const Text('保存'),
            ),
          ],
        ),
      );
    } else {
      _removeTab(index);
    }
  }

  /// 移除标签页
  void _removeTab(int index) {
    if (index < 0 || index >= _tabs.length) return;
    
    setState(() {
      _tabs.removeAt(index);
      if (_tabs.isEmpty) {
        _currentTabIndex = 0;
        _controller.clear();
        _currentFilePath = '';
        _currentLanguage = 'Text';
        _hasChanges = false;
        _highlightedSpans = [];
      } else {
        if (_currentTabIndex >= _tabs.length) {
          _currentTabIndex = _tabs.length - 1;
        }
        _controller.text = _tabs[_currentTabIndex].content;
        _currentFilePath = _tabs[_currentTabIndex].path;
        _currentLanguage = _getLanguage(_tabs[_currentTabIndex].fileName);
        _hasChanges = _tabs[_currentTabIndex].hasChanges;
        _updateSyntaxHighlighting();
      }
    });
  }

  /// 关闭所有标签页
  void _closeAllTabs() {
    // 检查是否有未保存的文件
    final unsavedTabs = _tabs.where((t) => t.hasChanges).toList();
    
    if (unsavedTabs.isNotEmpty) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('多个文件未保存'),
          content: Text('有 ${unsavedTabs.length} 个文件有未保存的更改。\n是否全部保存？'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _removeAllTabs(false);
              },
              child: const Text('不保存全部'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(context);
                // 保存所有文件
                for (int i = 0; i < _tabs.length; i++) {
                  if (_tabs[i].hasChanges && _tabs[i].path.isNotEmpty) {
                    _switchTab(i);
                    await _saveCurrentFile();
                  }
                }
                _removeAllTabs(false);
              },
              child: const Text('保存全部'),
            ),
          ],
        ),
      );
    } else {
      _removeAllTabs(false);
    }
  }

  /// 移除所有标签页
  void _removeAllTabs(bool saveChanges) {
    setState(() {
      _tabs.clear();
      _currentTabIndex = 0;
      _controller.clear();
      _currentFilePath = '';
      _currentLanguage = 'Text';
      _hasChanges = false;
      _highlightedSpans = [];
    });
    _showSuccess('已关闭所有文件');
  }

  /// 关闭其他标签页
  void _closeOtherTabs(int keepIndex) {
    if (keepIndex < 0 || keepIndex >= _tabs.length) return;
    
    final keepTab = _tabs[keepIndex];
    
    // 检查其他标签是否有未保存的更改
    final otherTabs = _tabs.where((t) => t.hasChanges && t != keepTab).toList();
    
    if (otherTabs.isNotEmpty) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('文件未保存'),
          content: Text('有 ${otherTabs.length} 个文件有未保存的更改。\n是否全部保存？'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _removeOtherTabs(keepIndex, false);
              },
              child: const Text('不保存'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(context);
                // 保存其他文件
                for (int i = 0; i < _tabs.length; i++) {
                  if (i != keepIndex && _tabs[i].hasChanges && _tabs[i].path.isNotEmpty) {
                    _switchTab(i);
                    await _saveCurrentFile();
                  }
                }
                _removeOtherTabs(keepIndex, false);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      );
    } else {
      _removeOtherTabs(keepIndex, false);
    }
  }

  /// 移除其他标签页
  void _removeOtherTabs(int keepIndex, bool saveChanges) {
    if (keepIndex < 0 || keepIndex >= _tabs.length) return;
    
    final keepTab = _tabs[keepIndex];
    final newTabs = [keepTab];
    
    setState(() {
      _tabs.clear();
      _tabs.addAll(newTabs);
      _currentTabIndex = 0;
      _controller.text = keepTab.content;
      _currentFilePath = keepTab.path;
      _currentLanguage = _getLanguage(keepTab.fileName);
      _hasChanges = keepTab.hasChanges;
      _updateSyntaxHighlighting();
    });
    _showSuccess('已关闭其他文件');
  }
}

/// 编辑器设置对话框
class _EditorSettingsDialog extends StatefulWidget {
  final EditorSettings settings;
  final Function(EditorSettings) onSave;

  const _EditorSettingsDialog({
    required this.settings,
    required this.onSave,
  });

  @override
  State<_EditorSettingsDialog> createState() => _EditorSettingsDialogState();
}

class _EditorSettingsDialogState extends State<_EditorSettingsDialog> {
  late EditorSettings _settings;
  int _selectedPresetIndex = 0;

  @override
  void initState() {
    super.initState();
    _settings = widget.settings;
    // 查找匹配的预设
    final presets = EditorColorPresets.getAllPresets();
    for (int i = 0; i < presets.length; i++) {
      if (presets[i]['background'] == _settings.backgroundColor &&
          presets[i]['text'] == _settings.textColor) {
        _selectedPresetIndex = i;
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final presets = EditorColorPresets.getAllPresets();
    return AlertDialog(
      title: const Text('编辑器设置'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 预设主题
            const Text('预设主题', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(presets.length, (index) {
                final preset = presets[index];
                final isSelected = index == _selectedPresetIndex;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedPresetIndex = index;
                      _settings.backgroundColor = preset['background'] as Color;
                      _settings.textColor = preset['text'] as Color;
                    });
                  },
                  child: Container(
                    width: 60,
                    height: 40,
                    decoration: BoxDecoration(
                      color: preset['background'] as Color,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: isSelected ? Colors.blue : Colors.grey,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Center(
                      child: Icon(
                        preset['icon'] as IconData,
                        color: preset['text'] as Color,
                        size: 20,
                      ),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            
            // 字体大小
            const Text('字体大小', style: TextStyle(fontWeight: FontWeight.bold)),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: _settings.fontSize,
                    min: 10,
                    max: 24,
                    divisions: 14,
                    label: '${_settings.fontSize.toInt()}',
                    onChanged: (value) {
                      setState(() {
                        _settings.fontSize = value;
                      });
                    },
                  ),
                ),
                Text('${_settings.fontSize.toInt()}px'),
              ],
            ),
            const SizedBox(height: 8),
            
            // 行高
            const Text('行高', style: TextStyle(fontWeight: FontWeight.bold)),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: _settings.lineHeight,
                    min: 1.0,
                    max: 2.5,
                    divisions: 15,
                    label: _settings.lineHeight.toStringAsFixed(1),
                    onChanged: (value) {
                      setState(() {
                        _settings.lineHeight = value;
                      });
                    },
                  ),
                ),
                Text(_settings.lineHeight.toStringAsFixed(1)),
              ],
            ),
            const SizedBox(height: 8),
            
            // 显示行号
            SwitchListTile(
              title: const Text('显示行号'),
              value: _settings.showLineNumbers,
              onChanged: (value) {
                setState(() {
                  _settings.showLineNumbers = value;
                });
              },
              contentPadding: EdgeInsets.zero,
            ),
            
            // 自动保存
            SwitchListTile(
              title: const Text('自动保存'),
              value: _settings.autoSave,
              onChanged: (value) {
                setState(() {
                  _settings.autoSave = value;
                });
              },
              contentPadding: EdgeInsets.zero,
            ),
            
            // 自动保存延迟
            if (_settings.autoSave) ...[
              const Text('自动保存延迟', style: TextStyle(fontWeight: FontWeight.bold)),
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: _settings.autoSaveDelay.toDouble(),
                      min: 5,
                      max: 60,
                      divisions: 11,
                      label: '${_settings.autoSaveDelay}秒',
                      onChanged: (value) {
                        setState(() {
                          _settings.autoSaveDelay = value.toInt();
                        });
                      },
                    ),
                  ),
                  Text('${_settings.autoSaveDelay}秒'),
                ],
              ),
            ],
            
            // Tab 大小
            const Text('Tab 大小', style: TextStyle(fontWeight: FontWeight.bold)),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: _settings.tabSize.toDouble(),
                    min: 2,
                    max: 8,
                    divisions: 3,
                    label: '${_settings.tabSize}',
                    onChanged: (value) {
                      setState(() {
                        _settings.tabSize = value.toInt();
                      });
                    },
                  ),
                ),
                Text('${_settings.tabSize}'),
              ],
            ),
            
            // 使用空格代替 Tab
            SwitchListTile(
              title: const Text('使用空格代替 Tab'),
              value: _settings.useSpaces,
              onChanged: (value) {
                setState(() {
                  _settings.useSpaces = value;
                });
              },
              contentPadding: EdgeInsets.zero,
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
          onPressed: () {
            widget.onSave(_settings);
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('设置已保存')),
            );
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class EditorTab {
  final String fileName;
  final String path;
  String content;
  bool hasChanges;

  EditorTab({
    required this.fileName,
    required this.path,
    required this.content,
    this.hasChanges = false,
  });
}
