import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// 文件操作服务 - 支持AI自动文件操作
class FileOperationService {
  static final FileOperationService _instance = FileOperationService._internal();
  factory FileOperationService() => _instance;
  FileOperationService._internal();

  /// 当前项目路径
  String? _currentProjectPath;

  /// 设置当前项目路径
  void setProjectPath(String? path) {
    _currentProjectPath = path;
  }

  /// 获取当前项目路径
  String? get currentProjectPath => _currentProjectPath;

  /// 读取文件内容
  Future<FileReadResult> readFile(String filePath) async {
    try {
      // 如果没有提供完整路径，尝试相对于项目路径
      String fullPath = filePath;
      if (!filePath.startsWith('/') && _currentProjectPath != null) {
        fullPath = p.join(_currentProjectPath!, filePath);
      }

      final file = File(fullPath);
      if (!await file.exists()) {
        return FileReadResult(
          success: false,
          error: '文件不存在: $fullPath',
        );
      }

      final content = await file.readAsString();
      return FileReadResult(
        success: true,
        content: content,
        filePath: fullPath,
      );
    } catch (e) {
      return FileReadResult(
        success: false,
        error: '读取失败: $e',
      );
    }
  }

  /// 写入文件内容
  Future<FileWriteResult> writeFile(String filePath, String content, {bool createDirectories = true}) async {
    try {
      // 如果没有提供完整路径，尝试相对于项目路径
      String fullPath = filePath;
      if (!filePath.startsWith('/') && _currentProjectPath != null) {
        fullPath = p.join(_currentProjectPath!, filePath);
      }

      final file = File(fullPath);
      
      // 确保父目录存在
      if (createDirectories) {
        final parentDir = file.parent;
        if (!await parentDir.exists()) {
          await parentDir.create(recursive: true);
        }
      }

      await file.writeAsString(content);
      return FileWriteResult(
        success: true,
        filePath: fullPath,
      );
    } catch (e) {
      return FileWriteResult(
        success: false,
        error: '写入失败: $e',
      );
    }
  }

  /// 编辑文件（支持diff格式）
  /// AI生成的内容可以是完整的文件内容或diff格式
  Future<FileWriteResult> editFile(String filePath, String newContent) async {
    try {
      // 如果没有提供完整路径，尝试相对于项目路径
      String fullPath = filePath;
      if (!filePath.startsWith('/') && _currentProjectPath != null) {
        fullPath = p.join(_currentProjectPath!, filePath);
      }

      final file = File(fullPath);
      
      // 检查是否是diff格式
      if (_isDiffFormat(newContent)) {
        // 解析diff并应用
        return await _applyDiff(fullPath, newContent);
      }
      
      // 直接写入完整内容
      final parentDir = file.parent;
      if (!await parentDir.exists()) {
        await parentDir.create(recursive: true);
      }
      
      await file.writeAsString(newContent);
      return FileWriteResult(
        success: true,
        filePath: fullPath,
      );
    } catch (e) {
      return FileWriteResult(
        success: false,
        error: '编辑失败: $e',
      );
    }
  }

  /// 检查是否是diff格式
  bool _isDiffFormat(String content) {
    return content.contains('---') && 
           content.contains('+++') && 
           (content.contains('@@') || content.contains('-'));
  }

  /// 应用diff到文件
  Future<FileWriteResult> _applyDiff(String filePath, String diff) async {
    try {
      final file = File(filePath);
      String originalContent = '';
      
      if (await file.exists()) {
        originalContent = await file.readAsString();
      }

      // 简单的diff解析和应用
      final lines = diff.split('\n');
      final resultLines = <String>[];
      int originalIndex = 0;
      bool inHunk = false;
      int hunkStart = 0;
      List<String> hunkContent = [];

      for (var line in lines) {
        if (line.startsWith('---') || line.startsWith('+++')) {
          // 新文件开始
          continue;
        }
        
        if (line.startsWith('@@')) {
          // 解析hunk头: @@ -start,count +start,count @@
          final match = RegExp(r'@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@').firstMatch(line);
          if (match != null) {
            // 复制到hunk开始位置之前的行
            final targetStart = int.parse(match.group(2)!) - 1;
            while (resultLines.length < targetStart) {
              if (originalIndex < originalContent.split('\n').length) {
                resultLines.add(originalContent.split('\n')[originalIndex]);
                originalIndex++;
              } else {
                resultLines.add('');
              }
            }
          }
          inHunk = true;
          hunkContent = [];
          continue;
        }

        if (inHunk) {
          if (line.startsWith('-')) {
            // 删除行
            originalIndex++;
          } else if (line.startsWith('+')) {
            // 添加行
            hunkContent.add(line.substring(1));
          } else if (line.startsWith(' ')) {
            // 保留行
            hunkContent.add(line.substring(1));
            originalIndex++;
          } else if (line.isEmpty) {
            hunkContent.add('');
          } else {
            // 可能是没有+/-前缀的上下文行
            hunkContent.add(line);
            originalIndex++;
          }
        }
      }

      // 添加剩余的hunk内容
      resultLines.addAll(hunkContent);
      
      // 添加原始文件剩余内容
      if (originalIndex < originalContent.split('\n').length) {
        resultLines.addAll(originalContent.split('\n').sublist(originalIndex));
      }

      // 写入结果
      final parentDir = file.parent;
      if (!await parentDir.exists()) {
        await parentDir.create(recursive: true);
      }
      
      await file.writeAsString(resultLines.join('\n'));
      
      return FileWriteResult(
        success: true,
        filePath: filePath,
      );
    } catch (e) {
      return FileWriteResult(
        success: false,
        error: '应用diff失败: $e',
      );
    }
  }

  /// 创建新文件
  Future<FileWriteResult> createFile(String filePath, String content) async {
    return writeFile(filePath, content);
  }

  /// 删除文件
  Future<FileDeleteResult> deleteFile(String filePath) async {
    try {
      String fullPath = filePath;
      if (!filePath.startsWith('/') && _currentProjectPath != null) {
        fullPath = p.join(_currentProjectPath!, filePath);
      }

      final file = File(fullPath);
      if (await file.exists()) {
        await file.delete();
        return FileDeleteResult(
          success: true,
          filePath: fullPath,
        );
      }
      return FileDeleteResult(
        success: false,
        error: '文件不存在',
      );
    } catch (e) {
      return FileDeleteResult(
        success: false,
        error: '删除失败: $e',
      );
    }
  }

  /// 列出项目目录
  Future<List<FileInfo>> listDirectory([String? relativePath]) async {
    try {
      String fullPath = _currentProjectPath ?? '';
      if (relativePath != null && relativePath.isNotEmpty) {
        fullPath = p.join(fullPath, relativePath);
      }

      if (fullPath.isEmpty) {
        return [];
      }

      final dir = Directory(fullPath);
      if (!await dir.exists()) {
        return [];
      }

      final entities = await dir.list().toList();
      final result = <FileInfo>[];

      for (var entity in entities) {
        final name = p.basename(entity.path);
        if (name.startsWith('.')) continue;

        result.add(FileInfo(
          name: name,
          path: entity.path,
          isDirectory: entity is Directory,
          relativePath: relativePath != null 
              ? p.join(relativePath, name)
              : name,
        ));
      }

      // 排序：目录在前，文件在后
      result.sort((a, b) {
        if (a.isDirectory && !b.isDirectory) return -1;
        if (!a.isDirectory && b.isDirectory) return 1;
        return a.name.compareTo(b.name);
      });

      return result;
    } catch (e) {
      debugPrint('列出目录失败: $e');
      return [];
    }
  }

  /// 根据语言获取文件扩展名
  String getExtension(String language) {
    const extensions = {
      'dart': '.dart',
      'python': '.py',
      'python3': '.py',
      'java': '.java',
      'javascript': '.js',
      'js': '.js',
      'typescript': '.ts',
      'ts': '.ts',
      'kotlin': '.kt',
      'swift': '.swift',
      'go': '.go',
      'rust': '.rs',
      'c': '.c',
      'cpp': '.cpp',
      'c++': '.cpp',
      'csharp': '.cs',
      'c#': '.cs',
      'html': '.html',
      'css': '.css',
      'scss': '.scss',
      'json': '.json',
      'xml': '.xml',
      'yaml': '.yaml',
      'yml': '.yml',
      'sql': '.sql',
      'shell': '.sh',
      'bash': '.sh',
      'markdown': '.md',
      'md': '.md',
      'txt': '.txt',
      'text': '.txt',
    };
    return extensions[language.toLowerCase()] ?? '.txt';
  }

  /// 从文件路径推断语言
  String inferLanguage(String filePath) {
    final ext = p.extension(filePath).toLowerCase();
    const languageMap = {
      '.dart': 'dart',
      '.py': 'python',
      '.java': 'java',
      '.js': 'javascript',
      '.ts': 'typescript',
      '.kt': 'kotlin',
      '.swift': 'swift',
      '.go': 'go',
      '.rs': 'rust',
      '.c': 'c',
      '.cpp': 'cpp',
      '.cs': 'csharp',
      '.html': 'html',
      '.css': 'css',
      '.scss': 'scss',
      '.json': 'json',
      '.xml': 'xml',
      '.yaml': 'yaml',
      '.yml': 'yaml',
      '.sql': 'sql',
      '.sh': 'shell',
      '.md': 'markdown',
    };
    return languageMap[ext] ?? 'text';
  }

  /// 获取文件名（不含扩展名）
  String getBaseName(String filePath) {
    return p.basenameWithoutExtension(filePath);
  }

  /// 获取文件扩展名
  String getExtensionFromPath(String filePath) {
    return p.extension(filePath);
  }
}

/// 文件读取结果
class FileReadResult {
  final bool success;
  final String? content;
  final String? filePath;
  final String? error;

  FileReadResult({
    required this.success,
    this.content,
    this.filePath,
    this.error,
  });
}

/// 文件写入结果
class FileWriteResult {
  final bool success;
  final String? filePath;
  final String? error;

  FileWriteResult({
    required this.success,
    this.filePath,
    this.error,
  });
}

/// 文件删除结果
class FileDeleteResult {
  final bool success;
  final String? filePath;
  final String? error;

  FileDeleteResult({
    required this.success,
    this.filePath,
    this.error,
  });
}

/// 文件信息
class FileInfo {
  final String name;
  final String path;
  final bool isDirectory;
  final String relativePath;

  FileInfo({
    required this.name,
    required this.path,
    required this.isDirectory,
    required this.relativePath,
  });
}

// 全局实例
final fileOperationService = FileOperationService();
