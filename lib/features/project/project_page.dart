import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

/// 文件写入历史记录项
class FileWriteRecord {
  final DateTime time;
  final String filePath;
  final String operation;
  final bool success;

  FileWriteRecord({
    required this.time,
    required this.filePath,
    required this.operation,
    this.success = true,
  });
}

/// 进程/任务项
class ProcessItem {
  final String id;
  final String name;
  final String description;
  final DateTime startTime;
  final bool isRunning;

  ProcessItem({
    required this.id,
    required this.name,
    required this.description,
    required this.startTime,
    this.isRunning = true,
  });
}

/// 文件树项
class FileTreeItem {
  final String name;
  final String path;
  final bool isDirectory;
  List<FileTreeItem> children;
  bool isExpanded;

  FileTreeItem({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.children = const [],
    this.isExpanded = false,
  });

  FileTreeItem copyWith({
    String? name,
    String? path,
    bool? isDirectory,
    List<FileTreeItem>? children,
    bool? isExpanded,
  }) {
    return FileTreeItem(
      name: name ?? this.name,
      path: path ?? this.path,
      isDirectory: isDirectory ?? this.isDirectory,
      children: children ?? this.children,
      isExpanded: isExpanded ?? this.isExpanded,
    );
  }
}

/// 项目页面 - 重新设计版本
class ProjectPage extends StatefulWidget {
  final String projectPath;
  final Function(String) onFileSelected;
  final VoidCallback? onClose;

  const ProjectPage({
    super.key,
    required this.projectPath,
    required this.onFileSelected,
    this.onClose,
  });

  @override
  State<ProjectPage> createState() => _ProjectPageState();
}

class _ProjectPageState extends State<ProjectPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  
  List<FileTreeItem> _rootItems = [];
  List<FileTreeItem> _filteredItems = [];
  bool _isLoading = true;
  String _searchQuery = '';

  // 模拟数据：当前进程列表
  final List<ProcessItem> _processes = [];

  // 模拟数据：文件写入历史
  final List<FileWriteRecord> _writeHistory = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadDirectory();
    _loadMockData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// 加载模拟数据
  void _loadMockData() {
    // 模拟进程数据
    _processes.addAll([
      ProcessItem(
        id: '1',
        name: 'Flutter Build',
        description: '正在构建应用...',
        startTime: DateTime.now().subtract(const Duration(minutes: 2)),
        isRunning: true,
      ),
      ProcessItem(
        id: '2',
        name: 'Dependencies Check',
        description: '检查依赖项...',
        startTime: DateTime.now().subtract(const Duration(minutes: 1)),
        isRunning: true,
      ),
    ]);

    // 模拟写入历史
    _writeHistory.addAll([
      FileWriteRecord(
        time: DateTime.now().subtract(const Duration(minutes: 5)),
        filePath: 'lib/main.dart',
        operation: '保存',
      ),
      FileWriteRecord(
        time: DateTime.now().subtract(const Duration(minutes: 10)),
        filePath: 'pubspec.yaml',
        operation: '保存',
      ),
      FileWriteRecord(
        time: DateTime.now().subtract(const Duration(minutes: 15)),
        filePath: 'lib/app/theme.dart',
        operation: '新建',
      ),
    ]);
  }

  /// 加载目录结构
  Future<void> _loadDirectory() async {
    try {
      final items = await _readDirectory(widget.projectPath);
      setState(() {
        _rootItems = items;
        _filteredItems = items;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// 读取目录内容
  Future<List<FileTreeItem>> _readDirectory(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) return [];

    final entities = await dir.list().toList();
    entities.sort((a, b) {
      if (a is Directory && b is! Directory) return -1;
      if (a is! Directory && b is Directory) return 1;
      return p.basename(a.path).compareTo(p.basename(b.path));
    });

    final items = <FileTreeItem>[];
    for (var entity in entities) {
      final name = p.basename(entity.path);
      if (name.startsWith('.')) continue;

      items.add(FileTreeItem(
        name: name,
        path: entity.path,
        isDirectory: entity is Directory,
        children: entity is Directory ? [] : [],
      ));
    }
    return items;
  }

  /// 搜索文件
  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query.toLowerCase();
      if (query.isEmpty) {
        _filteredItems = _rootItems;
      } else {
        _filteredItems = _filterItems(_rootItems, query.toLowerCase());
      }
    });
  }

  /// 递归过滤文件项
  List<FileTreeItem> _filterItems(List<FileTreeItem> items, String query) {
    final result = <FileTreeItem>[];
    for (var item in items) {
      if (item.isDirectory) {
        final filteredChildren = _filterItems(item.children, query);
        if (item.name.toLowerCase().contains(query) || filteredChildren.isNotEmpty) {
          result.add(item.copyWith(children: filteredChildren, isExpanded: true));
        }
      } else {
        if (item.name.toLowerCase().contains(query)) {
          result.add(item);
        }
      }
    }
    return result;
  }

  /// 格式化时间
  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    return '${diff.inDays}天前';
  }

  /// 获取文件图标
  IconData _getFileIcon(String fileName) {
    final ext = p.extension(fileName).toLowerCase();
    switch (ext) {
      case '.dart':
        return Icons.code;
      case '.yaml':
      case '.yml':
        return Icons.settings;
      case '.json':
        return Icons.data_object;
      case '.md':
        return Icons.article;
      case '.png':
      case '.jpg':
      case '.jpeg':
      case '.gif':
      case '.svg':
        return Icons.image;
      case '.txt':
        return Icons.text_snippet;
      case '.xml':
        return Icons.code;
      case '.html':
      case '.css':
        return Icons.web;
      default:
        return Icons.insert_drive_file;
    }
  }

  /// 获取文件图标颜色
  Color _getFileColor(String fileName) {
    final ext = p.extension(fileName).toLowerCase();
    switch (ext) {
      case '.dart':
        return Colors.blue;
      case '.yaml':
      case '.yml':
        return Colors.orange;
      case '.json':
        return Colors.amber;
      case '.md':
        return Colors.teal;
      case '.png':
      case '.jpg':
      case '.jpeg':
      case '.gif':
      case '.svg':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  /// 下载整个项目
  Future<void> _downloadProject() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('正在打包项目...'),
        duration: Duration(seconds: 2),
      ),
    );
    // TODO: 实现项目下载功能
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 48,
        title: Row(
          children: [
            const Icon(Icons.folder, size: 20),
            const SizedBox(width: 8),
            Text(
              p.basename(widget.projectPath),
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: widget.onClose,
            tooltip: '关闭',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelStyle: const TextStyle(fontSize: 12),
          indicatorSize: TabBarIndicatorSize.tab,
          tabs: const [
            Tab(text: '文件'),
            Tab(text: '当前进程'),
            Tab(text: '文件写入'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildFilesTab(),
          _buildProcessTab(),
          _buildWriteHistoryTab(),
        ],
      ),
    );
  }

  /// 文件标签页
  Widget _buildFilesTab() {
    return Column(
      children: [
        // 搜索栏和下载按钮
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceVariant,
          ),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: '搜索文件...',
                      hintStyle: const TextStyle(fontSize: 13),
                      prefixIcon: const Icon(Icons.search, size: 18),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surface,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.download, size: 20),
                onPressed: _downloadProject,
                tooltip: '下载项目',
                style: IconButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                ),
              ),
            ],
          ),
        ),
        // 文件树
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _filteredItems.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _searchQuery.isEmpty ? Icons.folder_off : Icons.search_off,
                            size: 48,
                            color: Colors.grey,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _searchQuery.isEmpty ? '空目录' : '未找到文件',
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _filteredItems.length,
                      itemBuilder: (context, index) {
                        return _buildTreeItem(_filteredItems[index], 0);
                      },
                    ),
        ),
      ],
    );
  }

  /// 构建文件树项
  Widget _buildTreeItem(FileTreeItem item, int level) {
    final indent = level * 16.0;

    if (item.isDirectory) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () async {
              setState(() {
                item.isExpanded = !item.isExpanded;
              });
              if (item.isExpanded && item.children.isEmpty) {
                final children = await _readDirectory(item.path);
                setState(() {
                  item.children = children;
                });
              }
            },
            onLongPress: () => _showDirectoryContextMenu(context, item),
            child: Container(
              padding: EdgeInsets.only(
                left: indent + 8,
                right: 8,
                top: 8,
                bottom: 8,
              ),
              child: Row(
                children: [
                  Icon(
                    item.isExpanded ? Icons.expand_more : Icons.chevron_right,
                    size: 18,
                    color: Colors.grey,
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    item.isExpanded ? Icons.folder_open : Icons.folder,
                    size: 18,
                    color: Colors.amber,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item.name,
                      style: const TextStyle(fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _buildItemActions(item, isDirectory: true),
                ],
              ),
            ),
          ),
          if (item.isExpanded)
            ...item.children.map((child) => _buildTreeItem(child, level + 1)),
        ],
      );
    } else {
      return InkWell(
        onTap: () => widget.onFileSelected(item.path),
        onLongPress: () => _showFileContextMenu(context, item),
        child: Container(
          padding: EdgeInsets.only(
            left: indent + 30,
            right: 8,
            top: 8,
            bottom: 8,
          ),
          child: Row(
            children: [
              Icon(
                _getFileIcon(item.name),
                size: 16,
                color: _getFileColor(item.name),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.name,
                  style: TextStyle(
                    fontSize: 13,
                    color: _searchQuery.isNotEmpty &&
                            item.name.toLowerCase().contains(_searchQuery)
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _buildItemActions(item, isDirectory: false),
            ],
          ),
        ),
      );
    }
  }

  /// 构建项目操作按钮
  Widget _buildItemActions(FileTreeItem item, {required bool isDirectory}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!isDirectory) ...[
          IconButton(
            icon: const Icon(Icons.open_in_new, size: 16),
            onPressed: () => widget.onFileSelected(item.path),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            tooltip: '打开',
          ),
        ],
        IconButton(
          icon: const Icon(Icons.download, size: 16),
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('下载 ${item.name}...'),
                duration: const Duration(seconds: 1),
              ),
            );
          },
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          tooltip: '下载',
        ),
      ],
    );
  }

  /// 显示目录上下文菜单
  void _showDirectoryContextMenu(BuildContext context, FileTreeItem item) {
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
          value: 'download',
          child: Row(
            children: [
              Icon(Icons.download, size: 18),
              SizedBox(width: 12),
              Text('下载目录'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'refresh',
          child: Row(
            children: [
              Icon(Icons.refresh, size: 18),
              SizedBox(width: 12),
              Text('刷新'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'expand_all',
          child: Row(
            children: [
              Icon(Icons.unfold_more, size: 18),
              SizedBox(width: 12),
              Text('展开全部'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'collapse_all',
          child: Row(
            children: [
              Icon(Icons.unfold_less, size: 18),
              SizedBox(width: 12),
              Text('折叠全部'),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value != null) {
        _handleDirectoryMenuAction(value, item);
      }
    });
  }

  /// 处理目录菜单操作
  void _handleDirectoryMenuAction(String action, FileTreeItem item) {
    switch (action) {
      case 'download':
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('下载 ${item.name}...')),
        );
        break;
      case 'refresh':
        _loadDirectory();
        break;
      case 'expand_all':
        _expandAll(_rootItems);
        break;
      case 'collapse_all':
        _collapseAll(_rootItems);
        break;
    }
  }

  /// 展开全部
  void _expandAll(List<FileTreeItem> items) async {
    for (var item in items) {
      if (item.isDirectory) {
        if (item.children.isEmpty) {
          item.children = await _readDirectory(item.path);
        }
        item.isExpanded = true;
        _expandAll(item.children);
      }
    }
    setState(() {});
  }

  /// 折叠全部
  void _collapseAll(List<FileTreeItem> items) {
    for (var item in items) {
      if (item.isDirectory) {
        item.isExpanded = false;
        _collapseAll(item.children);
      }
    }
    setState(() {});
  }

  /// 显示文件上下文菜单
  void _showFileContextMenu(BuildContext context, FileTreeItem item) {
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
          value: 'open',
          child: Row(
            children: [
              Icon(Icons.open_in_new, size: 18),
              SizedBox(width: 12),
              Text('打开'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'download',
          child: Row(
            children: [
              Icon(Icons.download, size: 18),
              SizedBox(width: 12),
              Text('下载'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'copy_path',
          child: Row(
            children: [
              Icon(Icons.copy, size: 18),
              SizedBox(width: 12),
              Text('复制路径'),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value != null) {
        _handleFileMenuAction(value, item);
      }
    });
  }

  /// 处理文件菜单操作
  void _handleFileMenuAction(String action, FileTreeItem item) {
    switch (action) {
      case 'open':
        widget.onFileSelected(item.path);
        break;
      case 'download':
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('下载 ${item.name}...')),
        );
        break;
      case 'copy_path':
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已复制路径: ${item.path}')),
        );
        break;
    }
  }

  /// 当前进程标签页
  Widget _buildProcessTab() {
    if (_processes.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 48, color: Colors.green),
            SizedBox(height: 16),
            Text(
              '暂无运行中的任务',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _processes.length,
      itemBuilder: (context, index) {
        final process = _processes[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 40,
                  height: 40,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                const Icon(Icons.sync, size: 20),
              ],
            ),
            title: Text(
              process.name,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  process.description,
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  '开始于 ${_formatTime(process.startTime)}',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
            trailing: IconButton(
              icon: const Icon(Icons.cancel, color: Colors.red),
              onPressed: () {
                _cancelProcess(process);
              },
              tooltip: '取消任务',
            ),
          ),
        );
      },
    );
  }

  /// 取消进程
  void _cancelProcess(ProcessItem process) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('取消任务'),
        content: Text('确定要取消 "${process.name}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('否'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _processes.removeWhere((p) => p.id == process.id);
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('已取消 ${process.name}')),
              );
            },
            child: const Text('是'),
          ),
        ],
      ),
    );
  }

  /// 文件写入历史标签页
  Widget _buildWriteHistoryTab() {
    if (_writeHistory.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 48, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              '暂无写入历史',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _writeHistory.length,
      itemBuilder: (context, index) {
        final record = _writeHistory[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: record.success
                    ? Colors.green.withOpacity(0.1)
                    : Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                record.success ? Icons.check : Icons.error,
                color: record.success ? Colors.green : Colors.red,
              ),
            ),
            title: Text(
              record.filePath,
              style: const TextStyle(fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.operation,
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatTime(record.time),
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
            trailing: IconButton(
              icon: const Icon(Icons.undo, size: 20),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('还原功能开发中...')),
                );
              },
              tooltip: '还原',
            ),
          ),
        );
      },
    );
  }
}
