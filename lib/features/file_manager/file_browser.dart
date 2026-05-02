import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import 'package:archive/archive.dart';
import 'project_directory.dart';

class FileBrowserPage extends StatefulWidget {
  final void Function(String path, String name)? onProjectSelected;

  const FileBrowserPage({super.key, this.onProjectSelected});

  @override
  State<FileBrowserPage> createState() => _FileBrowserPageState();
}

class _FileBrowserPageState extends State<FileBrowserPage> {
  List<ProjectItem> _recentProjects = [];
  bool _isLoading = false;
  
  // 视图模式切换
  bool _isTreeView = false;
  
  // 文件树展开状态
  final Map<String, bool> _projectExpandedStates = {};
  final Map<String, List<FileTreeItem>> _projectTreeCache = {};
  
  // 密度控制：0=默认, 1=紧凑, 2=超紧凑
  int _densityLevel = 0;

  @override
  void initState() {
    super.initState();
    _loadProjects();
  }

  Future<void> _loadProjects() async {
    final prefs = await SharedPreferences.getInstance();
    final projects = prefs.getStringList('recent_projects') ?? [];
    setState(() {
      _recentProjects = projects.map((json) {
        final parts = json.split('|||');
        return ProjectItem(
          name: parts[0],
          path: parts[1],
          type: ProjectType.values.firstWhere(
            (t) => t.name == parts[2],
            orElse: () => ProjectType.flutter,
          ),
          lastModified: parts.length > 3 ? parts[3] : '',
        );
      }).toList();
    });
  }

  Future<void> _saveProjects() async {
    final prefs = await SharedPreferences.getInstance();
    final projects = _recentProjects.map((p) => 
      '${p.name}|||${p.path}|||${p.type.name}|||${p.lastModified}'
    ).toList();
    await prefs.setStringList('recent_projects', projects);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Miss IDE'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadProjects),
          // 视图切换按钮
          IconButton(
            icon: Icon(_isTreeView ? Icons.view_list : Icons.account_tree),
            onPressed: () => setState(() => _isTreeView = !_isTreeView),
            tooltip: _isTreeView ? '切换为列表视图' : '切换为文件树视图',
          ),
          // 密度控制
          PopupMenuButton<int>(
            icon: const Icon(Icons.density_small),
            tooltip: '调整密度',
            onSelected: (level) => setState(() => _densityLevel = level),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 0,
                child: Row(
                  children: [
                    if (_densityLevel == 0) const Icon(Icons.check, size: 16, color: Colors.green),
                    if (_densityLevel != 0) const SizedBox(width: 16),
                    const SizedBox(width: 8),
                    const Text('默认密度'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 1,
                child: Row(
                  children: [
                    if (_densityLevel == 1) const Icon(Icons.check, size: 16, color: Colors.green),
                    if (_densityLevel != 1) const SizedBox(width: 16),
                    const SizedBox(width: 8),
                    const Text('紧凑'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 2,
                child: Row(
                  children: [
                    if (_densityLevel == 2) const Icon(Icons.check, size: 16, color: Colors.green),
                    if (_densityLevel != 2) const SizedBox(width: 16),
                    const SizedBox(width: 8),
                    const Text('超紧凑'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // 快捷操作
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _buildQuickAction(Icons.folder_open, '导入目录', Colors.blue, _importFromDirectory),
                const SizedBox(width: 12),
                _buildQuickAction(Icons.archive, '导入压缩包', Colors.green, _importFromArchive),
                const SizedBox(width: 12),
                _buildQuickAction(Icons.create_new_folder, '新建项目', Colors.orange, _createProject),
              ],
            ),
          ),
          // 最近项目
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text('最近项目', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                if (_recentProjects.isNotEmpty)
                  TextButton(onPressed: _clearProjects, child: const Text('清空')),
              ],
            ),
          ),
          // 项目列表
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _recentProjects.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.folder_open, size: 64, color: Colors.grey),
                            SizedBox(height: 16),
                            Text('暂无项目'),
                            SizedBox(height: 8),
                            Text('点击上方按钮导入或创建项目'),
                          ],
                        ),
                      )
                    : _isTreeView
                        ? _buildTreeView()
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: _recentProjects.length,
                            itemBuilder: (context, index) {
                              return _buildProjectCard(_recentProjects[index], index);
                            },
                          ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createProject,
        icon: const Icon(Icons.add),
        label: const Text('新建项目'),
      ),
    );
  }

  Widget _buildQuickAction(IconData icon, String label, Color color, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Icon(icon, color: color),
              const SizedBox(height: 4),
              Text(label, style: TextStyle(fontSize: 12, color: color)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProjectCard(ProjectItem project, int index) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _getProjectColor(project.type).withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(_getProjectIcon(project.type), color: _getProjectColor(project.type)),
        ),
        title: Text(project.name),
        subtitle: Text(project.path, style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis),
        trailing: PopupMenuButton<String>(
          onSelected: (value) => _handleProjectAction(value, index),
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'open', child: Text('打开')),
            const PopupMenuItem(value: 'tree', child: Text('查看文件树')),
            const PopupMenuItem(value: 'remove', child: Text('移除')),
          ],
        ),
        onTap: () => _openProject(project),
      ),
    );
  }

  /// 构建文件树视图
  Widget _buildTreeView() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      itemCount: _recentProjects.length,
      itemBuilder: (context, index) {
        return _buildProjectTreeItem(_recentProjects[index], index);
      },
    );
  }

  /// 构建项目树形项
  Widget _buildProjectTreeItem(ProjectItem project, int index) {
    final isExpanded = _projectExpandedStates[project.path] ?? false;
    final indent = _getIndentSize();
    final fontSize = _getFontSize();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 项目根节点
        InkWell(
          onTap: () async {
            setState(() {
              _projectExpandedStates[project.path] = !isExpanded;
            });
            if (isExpanded && !_projectTreeCache.containsKey(project.path)) {
              // 加载项目文件树
              final tree = await _loadProjectTree(project.path);
              _projectTreeCache[project.path] = tree;
            }
          },
          onLongPress: () => _showProjectContextMenu(context, project, index),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: 8,
              vertical: _densityLevel == 2 ? 4 : 8,
            ),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  isExpanded ? Icons.folder_open : Icons.folder,
                  size: 18,
                  color: _getProjectColor(project.type),
                ),
                const SizedBox(width: 8),
                Icon(_getProjectIcon(project.type), size: 16, color: _getProjectColor(project.type)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    project.name,
                    style: TextStyle(
                      fontSize: fontSize,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  isExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
        
        // 文件树内容
        if (isExpanded) ...[
          FutureBuilder<List<FileTreeItem>>(
            future: _projectTreeCache.containsKey(project.path)
                ? Future.value(_projectTreeCache[project.path])
                : _loadProjectTree(project.path),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return Padding(
                  padding: EdgeInsets.only(left: indent),
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                );
              }
              
              // 缓存文件树
              if (!_projectTreeCache.containsKey(project.path)) {
                _projectTreeCache[project.path] = snapshot.data!;
              }
              
              return Column(
                children: snapshot.data!.map((item) {
                  return _buildFileTreeNode(item, indent);
                }).toList(),
              );
            },
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  /// 构建文件树节点
  Widget _buildFileTreeNode(FileTreeItem item, double baseIndent) {
    final fontSize = _getFontSize();
    final indent = baseIndent + _getIndentSize();
    
    if (item.isDirectory) {
      return ExpansionTile(
        key: PageStorageKey(item.path),
        tilePadding: EdgeInsets.only(left: indent),
        leading: Icon(
          item.isExpanded ? Icons.folder_open : Icons.folder,
          size: 16,
          color: Colors.amber,
        ),
        title: Text(
          item.name,
          style: TextStyle(fontSize: fontSize),
        ),
        onExpansionChanged: (expanded) async {
          if (expanded && item.children.isEmpty) {
            final children = await _loadTreeNodeChildren(item.path);
            setState(() {
              item.children.clear();
              item.children.addAll(children);
              item.isExpanded = true;
            });
          }
        },
        children: item.children.map((child) => _buildFileTreeNode(child, indent + 12)).toList(),
      );
    } else {
      return InkWell(
        onTap: () => _openFileFromTree(item),
        onLongPress: () => _showFileContextMenuFromTree(context, item),
        child: Padding(
          padding: EdgeInsets.only(left: indent + 20),
          child: Row(
            children: [
              Icon(
                _getFileIcon(item.name),
                size: 14,
                color: _getFileColor(item.name),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: _densityLevel == 2 ? 4 : 6),
                  child: Text(
                    item.name,
                    style: TextStyle(fontSize: fontSize),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  /// 加载项目文件树
  Future<List<FileTreeItem>> _loadProjectTree(String path) async {
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

  /// 加载树节点子项
  Future<List<FileTreeItem>> _loadTreeNodeChildren(String path) async {
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

  /// 获取缩进大小
  double _getIndentSize() {
    switch (_densityLevel) {
      case 0: return 16.0;
      case 1: return 12.0;
      case 2: return 8.0;
      default: return 16.0;
    }
  }

  /// 获取字体大小
  double _getFontSize() {
    switch (_densityLevel) {
      case 0: return 14.0;
      case 1: return 12.0;
      case 2: return 11.0;
      default: return 14.0;
    }
  }

  /// 从文件树打开文件
  void _openFileFromTree(FileTreeItem item) {
    // 调用回调，传递项目路径
    final projectPath = _findProjectPath(item.path);
    if (projectPath != null) {
      widget.onProjectSelected?.call(item.path, item.name);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已打开: ${item.name}')),
      );
    }
  }

  /// 查找文件所属项目路径
  String? _findProjectPath(String filePath) {
    for (var project in _recentProjects) {
      if (filePath.startsWith(project.path)) {
        return project.path;
      }
    }
    return null;
  }

  /// 显示项目上下文菜单（从文件树）
  void _showProjectContextMenu(BuildContext context, ProjectItem project, int index) {
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(100, 100, 100, 100),
      items: [
        const PopupMenuItem(value: 'open', child: Text('打开')),
        const PopupMenuItem(value: 'refresh', child: Text('刷新')),
        const PopupMenuItem(value: 'remove', child: Text('移除')),
      ],
    ).then((value) {
      if (value == 'open') {
        _openProject(project);
      } else if (value == 'refresh') {
        _projectTreeCache.remove(project.path);
        _projectExpandedStates[project.path] = false;
        setState(() {});
      } else if (value == 'remove') {
        setState(() {
          _recentProjects.removeAt(index);
          _projectTreeCache.remove(project.path);
          _projectExpandedStates.remove(project.path);
        });
        _saveProjects();
      }
    });
  }

  /// 显示文件上下文菜单（从文件树）
  void _showFileContextMenuFromTree(BuildContext context, FileTreeItem item) {
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        overlay.size.width / 2,
        overlay.size.height / 2,
        overlay.size.width / 2,
        overlay.size.height / 2,
      ),
      items: [
        const PopupMenuItem(value: 'open', child: Text('打开')),
        const PopupMenuItem(value: 'copy_path', child: Text('复制路径')),
      ],
    ).then((value) {
      if (value == 'open') {
        _openFileFromTree(item);
      } else if (value == 'copy_path') {
        Clipboard.setData(ClipboardData(text: item.path));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('路径已复制')),
        );
      }
    });
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
      case 'txt': return Icons.text_snippet;
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
      case 'html': return Colors.orange;
      case 'css': return Colors.blue;
      default: return Colors.grey;
    }
  }

  Color _getProjectColor(ProjectType type) {
    switch (type) {
      case ProjectType.flutter: return Colors.blue;
      case ProjectType.android: return Colors.green;
      case ProjectType.python: return Colors.green;
      case ProjectType.nodejs: return Colors.yellow;
      default: return Colors.grey;
    }
  }

  IconData _getProjectIcon(ProjectType type) {
    switch (type) {
      case ProjectType.flutter: return Icons.flutter_dash;
      case ProjectType.android: return Icons.android;
      case ProjectType.python: return Icons.code;
      case ProjectType.nodejs: return Icons.javascript;
      default: return Icons.folder;
    }
  }

  Future<void> _importFromDirectory() async {
    try {
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
      if (selectedDirectory == null) return;

      final projectName = p.basename(selectedDirectory);
      final projectType = _detectProjectType(selectedDirectory);

      final project = ProjectItem(
        name: projectName,
        path: selectedDirectory,
        type: projectType,
        lastModified: DateTime.now().toString().substring(0, 10),
      );

      setState(() {
        _recentProjects.removeWhere((p) => p.path == selectedDirectory);
        _recentProjects.insert(0, project);
      });

      await _saveProjects();
      _showSuccess('项目已导入: $projectName');
      
      // 显示文件树
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => FileTreeDialog(
            projectPath: selectedDirectory,
            projectName: projectName,
          ),
        );
      }
    } catch (e) {
      _showError('导入失败: $e');
    }
  }

  Future<void> _importFromArchive() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip', 'rar', 'tar', 'gz', 'tgz', '7z'],
      );
      
      if (result == null || result.files.isEmpty) return;
      
      final filePath = result.files.first.path;
      if (filePath == null) return;
      
      // 选择解压目录
      String? outputDir = await FilePicker.platform.getDirectoryPath();
      if (outputDir == null) return;
      
      final fileName = result.files.first.name;
      final projectName = fileName.replaceAll(RegExp(r'\.(zip|rar|tar|gz|tgz|7z)$'), '');
      final projectPath = p.join(outputDir, projectName);
      
      setState(() => _isLoading = true);
      
      // 解压zip文件
      if (filePath.endsWith('.zip')) {
        await _extractZip(filePath, projectPath);
      } else {
        _showError('暂不支持此格式，请使用zip');
        return;
      }
      
      final projectType = _detectProjectType(projectPath);
      final project = ProjectItem(
        name: projectName,
        path: projectPath,
        type: projectType,
        lastModified: DateTime.now().toString().substring(0, 10),
      );

      setState(() {
        _recentProjects.insert(0, project);
        _isLoading = false;
      });

      await _saveProjects();
      _showSuccess('项目已解压导入: $projectName');
      
      // 显示文件树
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => FileTreeDialog(
            projectPath: projectPath,
            projectName: projectName,
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('解压失败: $e');
    }
  }

  Future<void> _extractZip(String zipPath, String outputPath) async {
    final bytes = File(zipPath).readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes);
    
    for (final file in archive) {
      final filePath = p.join(outputPath, file.name);
      if (file.isFile) {
        File(filePath)
          ..createSync(recursive: true)
          ..writeAsBytesSync(file.content as List<int>);
      } else {
        Directory(filePath).createSync(recursive: true);
      }
    }
  }

  Future<void> _createProject() async {
    final nameController = TextEditingController(text: 'my_project');
    String selectedType = 'flutter';
    
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('新建项目'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: '项目名称', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: selectedType,
                decoration: const InputDecoration(labelText: '项目类型', border: OutlineInputBorder()),
                items: ['flutter', 'android', 'python', 'nodejs'].map((type) {
                  return DropdownMenuItem(value: type, child: Text(type.toUpperCase()));
                }).toList(),
                onChanged: (type) => setState(() => selectedType = type!),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('创建')),
          ],
        ),
      ),
    );

    if (result != true) return;

    try {
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
      if (selectedDirectory == null) return;

      final projectName = nameController.text.trim();
      final projectPath = p.join(selectedDirectory, projectName);
      final dir = Directory(projectPath);

      if (await dir.exists()) {
        _showError('目录已存在');
        return;
      }

      await dir.create(recursive: true);
      await _createProjectFiles(projectPath, selectedType);

      final project = ProjectItem(
        name: projectName,
        path: projectPath,
        type: ProjectType.values.firstWhere((t) => t.name == selectedType, orElse: () => ProjectType.flutter),
        lastModified: DateTime.now().toString().substring(0, 10),
      );

      setState(() => _recentProjects.insert(0, project));
      await _saveProjects();
      _showSuccess('项目已创建: $projectName');
    } catch (e) {
      _showError('创建失败: $e');
    }
  }

  Future<void> _createProjectFiles(String path, String type) async {
    switch (type) {
      case 'flutter':
        await File(p.join(path, 'lib', 'main.dart')).create(recursive: true);
        await File(p.join(path, 'pubspec.yaml')).create(recursive: true);
        break;
      case 'python':
        await File(p.join(path, 'main.py')).create(recursive: true);
        await File(p.join(path, 'requirements.txt')).create(recursive: true);
        break;
      case 'nodejs':
        await File(p.join(path, 'index.js')).create(recursive: true);
        await File(p.join(path, 'package.json')).create(recursive: true);
        break;
    }
  }

  void _openProject(ProjectItem project) {
    // 调用回调，传递项目路径和名称
    widget.onProjectSelected?.call(project.path, project.name);
    _showSuccess('已打开: ${project.name}');
  }

  void _handleProjectAction(String action, int index) {
    switch (action) {
      case 'open':
        _openProject(_recentProjects[index]);
        break;
      case 'tree':
        showDialog(
          context: context,
          builder: (context) => FileTreeDialog(
            projectPath: _recentProjects[index].path,
            projectName: _recentProjects[index].name,
          ),
        );
        break;
      case 'remove':
        setState(() => _recentProjects.removeAt(index));
        _saveProjects();
        break;
    }
  }

  Future<void> _clearProjects() async {
    setState(() => _recentProjects.clear());
    await _saveProjects();
  }

  ProjectType _detectProjectType(String path) {
    if (File(p.join(path, 'pubspec.yaml')).existsSync()) return ProjectType.flutter;
    if (File(p.join(path, 'build.gradle')).existsSync()) return ProjectType.android;
    if (File(p.join(path, 'requirements.txt')).existsSync() || 
        Directory(path).listSync().any((f) => f.path.endsWith('.py'))) return ProjectType.python;
    if (File(p.join(path, 'package.json')).existsSync()) return ProjectType.nodejs;
    return ProjectType.other;
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
}

enum ProjectType { flutter, android, python, nodejs, other }

class ProjectItem {
  final String name;
  final String path;
  final ProjectType type;
  final String lastModified;

  ProjectItem({
    required this.name,
    required this.path,
    required this.type,
    required this.lastModified,
  });
}
