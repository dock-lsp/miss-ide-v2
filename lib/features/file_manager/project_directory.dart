import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// 文件操作回调
typedef FileOperationCallback = void Function(String path, String operation);

/// 文件树项
class FileTreeItem {
  final String name;
  final String path;
  final bool isDirectory;
  final List<FileTreeItem> children;
  bool isExpanded;

  FileTreeItem({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.children = const [],
    this.isExpanded = false,
  });
}

/// 项目目录面板
class ProjectDirectoryPanel extends StatefulWidget {
  final String projectPath;
  final Function(String) onFileSelected;
  final FileOperationCallback? onFileOperation;
  /// 文件操作回调 - 用于长按菜单
  final Function(String action, String? currentFilePath)? onTabOperation;
  /// 当前打开的文件路径（用于"关闭当前文件"功能）
  final String? currentOpenFilePath;
  /// 所有打开的标签页文件路径列表
  final List<String>? openFilePaths;

  const ProjectDirectoryPanel({
    super.key,
    required this.projectPath,
    required this.onFileSelected,
    this.onFileOperation,
    this.onTabOperation,
    this.currentOpenFilePath,
    this.openFilePaths,
  });

  @override
  State<ProjectDirectoryPanel> createState() => _ProjectDirectoryPanelState();
}

class _ProjectDirectoryPanelState extends State<ProjectDirectoryPanel> {
  List<FileTreeItem>? _rootItems;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDirectory();
  }

  Future<void> _loadDirectory() async {
    try {
      final items = await _readDirectory(widget.projectPath);
      setState(() {
        _rootItems = items;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

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
        children: entity is Directory ? [] : const [],
      ));
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceVariant,
      child: Column(
        children: [
          // 标题栏
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
            ),
            child: Row(
              children: [
                const Icon(Icons.folder, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    p.basename(widget.projectPath),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 16),
                  onPressed: () {
                    setState(() {
                      _isLoading = true;
                    });
                    _loadDirectory();
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                ),
              ],
            ),
          ),
          // 文件树
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _rootItems == null || _rootItems!.isEmpty
                    ? const Center(child: Text('空目录', style: TextStyle(fontSize: 12)))
                    : ListView.builder(
                        itemCount: _rootItems!.length,
                        itemBuilder: (context, index) {
                          return _buildTreeItem(_rootItems![index], 0);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildTreeItem(FileTreeItem item, int level) {
    final indent = level * 16.0;

    if (item.isDirectory) {
      return InkWell(
        onLongPress: () => _showDirectoryContextMenu(context, item),
        child: ExpansionTile(
          tilePadding: EdgeInsets.only(left: indent, right: 8),
          leading: Icon(
            item.isExpanded ? Icons.folder_open : Icons.folder,
            size: 18,
            color: Colors.amber,
          ),
          title: Text(
            item.name,
            style: const TextStyle(fontSize: 12),
          ),
          onExpansionChanged: (expanded) async {
            if (expanded && item.children.isEmpty) {
              final children = await _readDirectory(item.path);
              setState(() {
                item.children.clear();
                item.children.addAll(children);
                item.isExpanded = true;
              });
            }
          },
          children: item.children.map((child) => _buildTreeItem(child, level + 1)).toList(),
        ),
      );
    } else {
      return InkWell(
        onTap: () => widget.onFileSelected(item.path),
        onLongPress: () => _showFileContextMenu(context, item),
        child: Padding(
          padding: EdgeInsets.only(left: indent + 28, top: 8, bottom: 8, right: 8),
          child: Row(
            children: [
              Icon(_getFileIcon(item.name), size: 16, color: _getFileColor(item.name)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.name,
                  style: const TextStyle(fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  /// 显示目录上下文菜单
  void _showDirectoryContextMenu(BuildContext context, FileTreeItem item) {
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final RenderBox button = context.findRenderObject() as RenderBox;
    final Offset position = button.localToGlobal(Offset.zero, ancestor: overlay);
    
    // 检查是否有打开的文件
    final hasOpenFiles = widget.openFilePaths != null && widget.openFilePaths!.isNotEmpty;
    final hasCurrentFile = widget.currentOpenFilePath != null && widget.currentOpenFilePath!.isNotEmpty;
    
    final menuItems = <PopupMenuEntry<String>>[
      if (hasOpenFiles) ...[
        PopupMenuItem(
          value: 'close',
          child: Row(
            children: [
              const Icon(Icons.close, size: 18),
              const SizedBox(width: 12),
              Text(hasCurrentFile ? '关闭当前文件' : '关闭文件'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'close_all',
          child: Row(
            children: [
              const Icon(Icons.close_fullscreen, size: 18),
              const SizedBox(width: 12),
              const Text('关闭所有文件'),
            ],
          ),
        ),
        if (hasOpenFiles && widget.openFilePaths!.length > 1)
          PopupMenuItem(
            value: 'close_others',
            child: Row(
              children: [
                const Icon(Icons.filter_alt_off, size: 18),
                const SizedBox(width: 12),
                const Text('关闭其他文件'),
              ],
            ),
          ),
        const PopupMenuDivider(),
      ],
      const PopupMenuItem(
        value: 'refresh',
        child: Row(
          children: [
            Icon(Icons.refresh, size: 18),
            SizedBox(width: 12),
            Text('刷新目录'),
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
    ];
    
    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, button.size.width, button.size.height),
        Offset.zero & overlay.size,
      ),
      items: menuItems,
    ).then((value) {
      if (value != null) {
        _handleDirectoryMenuAction(value, item);
      }
    });
  }

  /// 处理目录菜单操作
  void _handleDirectoryMenuAction(String action, FileTreeItem item) {
    switch (action) {
      case 'close':
        // 关闭当前文件
        if (widget.currentOpenFilePath != null) {
          widget.onTabOperation?.call('close', widget.currentOpenFilePath);
        }
        break;
      case 'close_all':
        // 关闭所有文件
        widget.onTabOperation?.call('close_all', null);
        break;
      case 'close_others':
        // 关闭其他文件
        widget.onTabOperation?.call('close_others', widget.currentOpenFilePath);
        break;
      case 'refresh':
        _loadDirectory();
        break;
      case 'expand_all':
        _expandAllDirectories(item);
        break;
      case 'collapse_all':
        _collapseAllDirectories(item);
        break;
    }
  }

  /// 展开所有目录
  void _expandAllDirectories(FileTreeItem item) async {
    if (item.isDirectory && !item.isExpanded) {
      final children = await _readDirectory(item.path);
      setState(() {
        item.children.clear();
        item.children.addAll(children);
        item.isExpanded = true;
      });
    }
    for (var child in item.children) {
      _expandAllDirectories(child);
    }
  }

  /// 折叠所有目录
  void _collapseAllDirectories(FileTreeItem item) {
    item.isExpanded = false;
    for (var child in item.children) {
      _collapseAllDirectories(child);
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
      items: _buildContextMenuItems(item),
    ).then((value) {
      if (value != null) {
        _handleContextMenuAction(item, value);
      }
    });
  }

  /// 构建上下文菜单项
  List<PopupMenuEntry<String>> _buildContextMenuItems(FileTreeItem item) {
    final ext = p.extension(item.name).toLowerCase();
    final isCodeFile = ['.dart', '.java', '.kt', '.py', '.js', '.ts', '.xml', '.json', '.yaml', '.yml', '.gradle', '.md'].contains(ext);
    
    return [
      PopupMenuItem(
        value: 'open',
        child: Row(
          children: [
            const Icon(Icons.open_in_new, size: 18),
            const SizedBox(width: 12),
            const Text('打开'),
          ],
        ),
      ),
      if (isCodeFile) ...[
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'ai_edit',
          child: Row(
            children: [
              Icon(Icons.auto_fix_high, size: 18, color: Colors.purple),
              const SizedBox(width: 12),
              const Text('AI 编辑'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'ai_explain',
          child: Row(
            children: [
              Icon(Icons.psychology, size: 18, color: Colors.blue),
              const SizedBox(width: 12),
              const Text('AI 解释'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'ai_refactor',
          child: Row(
            children: [
              Icon(Icons.transform, size: 18, color: Colors.green),
              const SizedBox(width: 12),
              const Text('AI 重构'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'ai_fix',
          child: Row(
            children: [
              Icon(Icons.build, size: 18, color: Colors.orange),
              const SizedBox(width: 12),
              const Text('AI 修复'),
            ],
          ),
        ),
      ],
      const PopupMenuDivider(),
      PopupMenuItem(
        value: 'copy_path',
        child: Row(
          children: [
            const Icon(Icons.copy, size: 18),
            const SizedBox(width: 12),
            const Text('复制路径'),
          ],
        ),
      ),
      PopupMenuItem(
        value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete, size: 18, color: Colors.red),
              const SizedBox(width: 12),
              Text('删除', style: TextStyle(color: Colors.red)),
            ],
          ),
      ),
    ];
  }

  /// 处理菜单操作
  void _handleContextMenuAction(FileTreeItem item, String action) {
    switch (action) {
      case 'open':
        widget.onFileSelected(item.path);
        break;
      case 'ai_edit':
      case 'ai_explain':
      case 'ai_refactor':
      case 'ai_fix':
        widget.onFileOperation?.call(item.path, action);
        break;
      case 'copy_path':
        Clipboard.setData(ClipboardData(text: item.path));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('路径已复制'), duration: Duration(seconds: 1)),
        );
        break;
      case 'delete':
        _confirmDelete(item);
        break;
    }
  }

  /// 确认删除文件
  void _confirmDelete(FileTreeItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除 "${item.name}" 吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      try {
        final file = File(item.path);
        await file.delete();
        _loadDirectory();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已删除: ${item.name}')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('删除失败: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  IconData _getFileIcon(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'dart': return Icons.code;
      case 'java': return Icons.coffee;
      case 'kt': return Icons.code;
      case 'py': return Icons.code;
      case 'js': return Icons.javascript;
      case 'html': return Icons.html;
      case 'css': return Icons.style;
      case 'json': return Icons.data_object;
      case 'yaml':
      case 'yml': return Icons.settings;
      case 'md': return Icons.description;
      case 'xml': return Icons.code;
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'gif': return Icons.image;
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
      case 'json': return Colors.amber;
      case 'yaml':
      case 'yml': return Colors.cyan;
      default: return Colors.grey;
    }
  }
}

/// 文件树对话框
class FileTreeDialog extends StatelessWidget {
  final String projectPath;
  final String projectName;

  const FileTreeDialog({
    super.key,
    required this.projectPath,
    required this.projectName,
  });

  Future<List<FileTreeItem>> _readDirectory(String path, int maxDepth) async {
    final dir = Directory(path);
    if (!await dir.exists() || maxDepth <= 0) return [];

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
        children: entity is Directory ? await _readDirectory(entity.path, maxDepth - 1) : [],
      ));
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.folder_open),
          const SizedBox(width: 8),
          Expanded(child: Text(projectName, overflow: TextOverflow.ellipsis)),
        ],
      ),
      content: SizedBox(
        width: 300,
        height: 400,
        child: FutureBuilder<List<FileTreeItem>>(
          future: _readDirectory(projectPath, 3),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            return ListView.builder(
              itemCount: snapshot.data!.length,
              itemBuilder: (context, index) {
                return _buildTreeItem(snapshot.data![index], 0);
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  Widget _buildTreeItem(FileTreeItem item, int level) {
    final indent = level * 16.0;
    return Padding(
      padding: EdgeInsets.only(left: indent),
      child: item.isDirectory
          ? ExpansionTile(
              leading: const Icon(Icons.folder, size: 18, color: Colors.amber),
              title: Text(item.name, style: const TextStyle(fontSize: 12)),
              children: item.children.map((c) => _buildTreeItem(c, level + 1)).toList(),
            )
          : Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(Icons.insert_drive_file, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 8),
                  Text(item.name, style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
    );
  }
}
