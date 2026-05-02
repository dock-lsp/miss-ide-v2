import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// 文件树节点
class FileTreeNode {
  final String name;
  final String path;
  final bool isDirectory;
  final List<FileTreeNode> children;
  bool isExpanded;

  FileTreeNode({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.children = const [],
    this.isExpanded = false,
  });
}

/// 项目页面 - 文件管理器风格
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

class _ProjectPageState extends State<ProjectPage> {
  List<FileTreeNode> _rootNodes = [];
  bool _isLoading = true;
  String? _selectedPath;

  // 折叠/展开状态追踪
  final Set<String> _expandedPaths = {};

  @override
  void initState() {
    super.initState();
    _loadFullTree();
  }

  /// 加载完整文件树
  Future<void> _loadFullTree() async {
    setState(() => _isLoading = true);
    try {
      final nodes = await _buildTree(widget.projectPath, depth: 0);
      setState(() {
        _rootNodes = nodes;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  /// 递归构建文件树（限制深度避免卡顿）
  Future<List<FileTreeNode>> _buildTree(String dirPath, {int depth = 0}) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) return [];

    final entities = await dir.list().toList();

    // 排序：文件夹在前，文件在后，各自按名称排序
    entities.sort((a, b) {
      final aIsDir = a is Directory;
      final bIsDir = b is Directory;
      if (aIsDir && !bIsDir) return -1;
      if (!aIsDir && bIsDir) return 1;
      return p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase());
    });

    final nodes = <FileTreeNode>[];
    for (final entity in entities) {
      final name = p.basename(entity.path);

      // 跳过隐藏文件/目录
      if (name.startsWith('.')) continue;
      // 跳过常见的大目录
      if (entity is Directory && (name == 'build' || name == '.dart_tool' || name == 'node_modules' || name == '.gradle')) continue;

      if (entity is Directory) {
        // 文件夹：深度 < 2 时预加载子项
        List<FileTreeNode> children = [];
        if (depth < 2) {
          children = await _buildTree(entity.path, depth: depth + 1);
        }
        nodes.add(FileTreeNode(
          name: name,
          path: entity.path,
          isDirectory: true,
          children: children,
        ));
      } else {
        nodes.add(FileTreeNode(
          name: name,
          path: entity.path,
          isDirectory: false,
        ));
      }
    }
    return nodes;
  }

  /// 加载子目录（懒加载深层目录）
  Future<List<FileTreeNode>> _loadChildren(String dirPath) async {
    return _buildTree(dirPath, depth: 0);
  }

  /// 获取文件图标
  IconData _getFileIcon(String name, {bool isDir = false, bool isOpen = false}) {
    if (isDir) return isOpen ? Icons.folder_open : Icons.folder;
    final ext = p.extension(name).toLowerCase();
    switch (ext) {
      case '.dart': return Icons.code;
      case '.yaml':
      case '.yml': return Icons.settings;
      case '.json': return Icons.data_object;
      case '.md': return Icons.article;
      case '.png':
      case '.jpg':
      case '.jpeg':
      case '.gif':
      case '.svg':
      case '.webp': return Icons.image;
      case '.xml': return Icons.code;
      case '.html':
      case '.css': return Icons.web;
      case '.js':
      case '.ts': return Icons.javascript;
      case '.py': return Icons.code;
      case '.java':
      case '.kt': return Icons.coffee;
      case '.gradle': return Icons.build;
      case '.txt': return Icons.text_snippet;
      case '.lock': return Icons.lock;
      case '.sh':
      case '.bat': return Icons.terminal;
      default: return Icons.insert_drive_file;
    }
  }

  /// 获取文件颜色
  Color _getFileColor(String name, {bool isDir = false}) {
    if (isDir) return Colors.amber;
    final ext = p.extension(name).toLowerCase();
    switch (ext) {
      case '.dart': return Colors.blue;
      case '.yaml':
      case '.yml': return Colors.orange;
      case '.json': return Colors.amber;
      case '.md': return Colors.teal;
      case '.png':
      case '.jpg':
      case '.jpeg':
      case '.gif':
      case '.svg':
      case '.webp': return Colors.purple;
      case '.js':
      case '.ts': return Colors.yellow.shade800;
      case '.py': return Colors.green;
      case '.java':
      case '.kt': return Colors.deepOrange;
      case '.gradle': return Colors.green.shade700;
      case '.html': return Colors.orange.shade700;
      case '.css': return Colors.blue.shade700;
      case '.xml': return Colors.red.shade400;
      case '.lock': return Colors.grey;
      case '.sh':
      case '.bat': return Colors.green.shade900;
      default: return Colors.grey.shade600;
    }
  }

  /// 获取文件大小字符串
  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// 展开全部
  void _expandAll() async {
    await _expandNodes(_rootNodes);
    setState(() {});
  }

  Future<void> _expandNodes(List<FileTreeNode> nodes) async {
    for (final node in nodes) {
      if (node.isDirectory) {
        if (node.children.isEmpty) {
          final children = await _loadChildren(node.path);
          node.children.addAll(children);
        }
        _expandedPaths.add(node.path);
        node.isExpanded = true;
        await _expandNodes(node.children.toList());
      }
    }
  }

  /// 折叠全部
  void _collapseAll() {
    _collapseNodes(_rootNodes);
    _expandedPaths.clear();
    setState(() {});
  }

  void _collapseNodes(List<FileTreeNode> nodes) {
    for (final node in nodes) {
      if (node.isDirectory) {
        node.isExpanded = false;
        _collapseNodes(node.children.toList());
      }
    }
  }

  /// 计算总文件数
  int _countFiles(List<FileTreeNode> nodes) {
    int count = 0;
    for (final node in nodes) {
      if (node.isDirectory) {
        count += _countFiles(node.children.toList());
      } else {
        count++;
      }
    }
    return count;
  }

  /// 计算总目录数
  int _countDirs(List<FileTreeNode> nodes) {
    int count = 0;
    for (final node in nodes) {
      if (node.isDirectory) {
        count += 1 + _countDirs(node.children.toList());
      }
    }
    return count;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final projectName = p.basename(widget.projectPath);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 48,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 20),
          onPressed: widget.onClose,
        ),
        title: Row(
          children: [
            Icon(Icons.folder, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                projectName,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          // 展开全部
          IconButton(
            icon: const Icon(Icons.unfold_more, size: 20),
            onPressed: _expandAll,
            tooltip: '展开全部',
          ),
          // 折叠全部
          IconButton(
            icon: const Icon(Icons.unfold_less, size: 20),
            onPressed: _collapseAll,
            tooltip: '折叠全部',
          ),
          // 刷新
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: _loadFullTree,
            tooltip: '刷新',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _rootNodes.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.folder_off, size: 56, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      Text('空目录', style: TextStyle(color: Colors.grey.shade500, fontSize: 15)),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // 路径面包屑
                    _buildBreadcrumb(theme),
                    // 文件树
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.only(bottom: 80),
                        itemCount: _rootNodes.length,
                        itemBuilder: (context, index) {
                          return _buildNode(_rootNodes[index], depth: 0);
                        },
                      ),
                    ),
                  ],
                ),
      // 底部状态栏
      bottomNavigationBar: _isLoading
          ? null
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceVariant,
                border: Border(top: BorderSide(color: theme.dividerColor, width: 0.5)),
              ),
              child: Row(
                children: [
                  Icon(Icons.folder, size: 14, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(
                    '${_countDirs(_rootNodes)} 个文件夹',
                    style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(width: 16),
                  Icon(Icons.insert_drive_file, size: 14, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(
                    '${_countFiles(_rootNodes)} 个文件',
                    style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const Spacer(),
                  Text(
                    p.basename(widget.projectPath),
                    style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
    );
  }

  /// 路径面包屑
  Widget _buildBreadcrumb(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
        border: Border(bottom: BorderSide(color: theme.dividerColor, width: 0.5)),
      ),
      child: Row(
        children: [
          Icon(Icons.home, size: 14, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              widget.projectPath,
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onSurfaceVariant,
                fontFamily: 'monospace',
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建树节点
  Widget _buildNode(FileTreeNode node, {required int depth}) {
    final theme = Theme.of(context);
    final indent = depth * 20.0;
    final isSelected = _selectedPath == node.path;

    if (node.isDirectory) {
      return _buildFolderNode(node, depth, indent, isSelected, theme);
    } else {
      return _buildFileNode(node, indent, isSelected, theme);
    }
  }

  /// 构建文件夹节点
  Widget _buildFolderNode(FileTreeNode node, int depth, double indent, bool isSelected, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 文件夹行
        Material(
          color: isSelected
              ? theme.colorScheme.primaryContainer.withOpacity(0.4)
              : Colors.transparent,
          child: InkWell(
            onTap: () async {
              setState(() {
                node.isExpanded = !node.isExpanded;
                if (node.isExpanded) {
                  _expandedPaths.add(node.path);
                } else {
                  _expandedPaths.remove(node.path);
                }
              });
              // 懒加载子目录
              if (node.isExpanded && node.children.isEmpty) {
                final children = await _loadChildren(node.path);
                setState(() {
                  node.children.addAll(children);
                });
              }
            },
            onLongPress: () => _showContextMenu(node),
            child: Container(
              height: 32,
              padding: EdgeInsets.only(left: indent + 8, right: 12),
              child: Row(
                children: [
                  // 展开/折叠箭头
                  Icon(
                    node.isExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                    size: 16,
                    color: Colors.grey.shade500,
                  ),
                  const SizedBox(width: 2),
                  // 文件夹图标
                  Icon(
                    node.isExpanded ? Icons.folder_open : Icons.folder,
                    size: 16,
                    color: Colors.amber.shade700,
                  ),
                  const SizedBox(width: 8),
                  // 文件夹名
                  Expanded(
                    child: Text(
                      node.name,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: theme.colorScheme.onSurface,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // 子项数量
                  if (node.children.isNotEmpty)
                    Text(
                      '${node.children.length}',
                      style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                    ),
                ],
              ),
            ),
          ),
        ),
        // 子节点（带动画）
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Column(
            children: node.children.map((child) => _buildNode(child, depth: depth + 1)).toList(),
          ),
          crossFadeState: node.isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200),
        ),
      ],
    );
  }

  /// 构建文件节点
  Widget _buildFileNode(FileTreeNode node, double indent, bool isSelected, ThemeData theme) {
    return Material(
      color: isSelected
          ? theme.colorScheme.primaryContainer.withOpacity(0.4)
          : Colors.transparent,
      child: InkWell(
        onTap: () {
          setState(() => _selectedPath = node.path);
          widget.onFileSelected(node.path);
        },
        onLongPress: () => _showFileContextMenu(node),
        child: Container(
          height: 32,
          padding: EdgeInsets.only(left: indent + 26, right: 12),
          child: Row(
            children: [
              // 文件图标
              Icon(
                _getFileIcon(node.name),
                size: 15,
                color: _getFileColor(node.name),
              ),
              const SizedBox(width: 8),
              // 文件名
              Expanded(
                child: Text(
                  node.name,
                  style: TextStyle(
                    fontSize: 13,
                    color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // 文件大小
              if (!node.isDirectory)
                FutureBuilder<FileStat>(
                  future: File(node.path).stat(),
                  builder: (context, snapshot) {
                    if (snapshot.hasData && snapshot.data!.type == FileSystemEntityType.file) {
                      return Text(
                        _formatSize(snapshot.data!.size),
                        style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 显示文件夹右键菜单
  void _showContextMenu(FileTreeNode node) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.folder, color: Colors.amber.shade700),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      node.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // 展开/折叠
            ListTile(
              leading: Icon(node.isExpanded ? Icons.unfold_less : Icons.unfold_more),
              title: Text(node.isExpanded ? '折叠' : '展开'),
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  node.isExpanded = !node.isExpanded;
                  if (node.isExpanded) {
                    _expandedPaths.add(node.path);
                  } else {
                    _expandedPaths.remove(node.path);
                  }
                });
              },
            ),
            // 展开全部子项
            ListTile(
              leading: const Icon(Icons.expand),
              title: const Text('展开全部子项'),
              onTap: () async {
                Navigator.pop(context);
                await _expandNodes([node]);
                setState(() {});
              },
            ),
            // 折叠全部子项
            ListTile(
              leading: const Icon(Icons.compress),
              title: const Text('折叠全部子项'),
              onTap: () {
                Navigator.pop(context);
                _collapseNodes([node]);
                setState(() {});
              },
            ),
            // 复制路径
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('复制路径'),
              onTap: () {
                Navigator.pop(context);
                _copyPath(node.path);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// 显示文件右键菜单
  void _showFileContextMenu(FileTreeNode node) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(_getFileIcon(node.name), color: _getFileColor(node.name)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      node.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // 打开
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: const Text('打开'),
              onTap: () {
                Navigator.pop(context);
                widget.onFileSelected(node.path);
              },
            ),
            // 复制路径
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('复制路径'),
              onTap: () {
                Navigator.pop(context);
                _copyPath(node.path);
              },
            ),
            // 复制文件名
            ListTile(
              leading: const Icon(Icons.text_fields),
              title: const Text('复制文件名'),
              onTap: () {
                Navigator.pop(context);
                _copyPath(node.name);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// 复制路径到剪贴板
  void _copyPath(String path) {
    Clipboard.setData(ClipboardData(text: path));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已复制: $path'),
        duration: const Duration(seconds: 1),
      ),
    );
  }
}
