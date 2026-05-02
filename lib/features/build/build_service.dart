import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:archive/archive_io.dart';
import 'build_config.dart';

/// GitHub Token 存储键
const _githubTokenKey = 'github_token';

/// 构建服务核心
/// 支持 GitHub Actions 云端构建
class BuildService {
  static const String _backendApi = 'http://47.92.220.102';
  static const String _githubRepo = 'qq00150610-cpu/miss-ide-v2';
  static const _storage = FlutterSecureStorage();
  
  // GitHub Token - 从安全存储读取
  static Future<String> get _githubToken async {
    return await _storage.read(key: _githubTokenKey) ?? '';
  }

  /// 设置 GitHub Token
  static Future<void> setGitHubToken(String token) async {
    await _storage.write(key: _githubTokenKey, value: token);
  }
  
  /// 获取 GitHub Token（同步）
  static Future<String> getGitHubToken() async {
    return await _storage.read(key: _githubTokenKey) ?? '';
  }

  /// 获取带认证的请求头
  Future<Map<String, String>> _getHeaders() async {
    final token = await _githubToken;
    return {
      'Authorization': 'token $token',
      'Accept': 'application/vnd.github.v3+json',
    };
  }

  // 构建历史
  final List<BuildHistoryItem> _buildHistory = [];
  final _historyController = StreamController<List<BuildHistoryItem>>.broadcast();
  Stream<List<BuildHistoryItem>> get historyStream => _historyController.stream;
  
  // 当前构建状态
  BuildHistoryItem? _currentBuild;
  final _buildStatusController = StreamController<BuildHistoryItem?>.broadcast();
  Stream<BuildHistoryItem?> get buildStatusStream => _buildStatusController.stream;
  
  // 构建日志
  final _logController = StreamController<String>.broadcast();
  Stream<String> get logStream => _logController.stream;

  // 单例
  static final BuildService _instance = BuildService._internal();
  factory BuildService() => _instance;
  BuildService._internal() {
    _loadHistory();
  }

  /// 加载历史记录
  Future<void> _loadHistory() async {
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final historyFile = File(p.join(docDir.path, 'build_history.json'));
      
      if (await historyFile.exists()) {
        final content = await historyFile.readAsString();
        final List<dynamic> jsonList = jsonDecode(content);
        _buildHistory.clear();
        _buildHistory.addAll(jsonList.map((e) => _historyItemFromJson(e)));
        _historyController.add(_buildHistory);
      }
    } catch (e) {
      debugPrint('Failed to load build history: $e');
    }
  }

  /// 保存历史记录
  Future<void> _saveHistory() async {
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final historyFile = File(p.join(docDir.path, 'build_history.json'));
      
      final jsonList = _buildHistory.map((e) => _historyItemToJson(e)).toList();
      await historyFile.writeAsString(jsonEncode(jsonList));
    } catch (e) {
      debugPrint('Failed to save build history: $e');
    }
  }

  Map<String, dynamic> _historyItemToJson(BuildHistoryItem item) => {
    'id': item.id,
    'projectName': item.projectName,
    'buildType': item.buildType.value,
    'status': item.status.value,
    'startTime': item.startTime.toIso8601String(),
    'endTime': item.endTime?.toIso8601String(),
    'apkPath': item.apkPath,
    'errorMessage': item.errorMessage,
    'buildNumber': item.buildNumber,
  };

  BuildHistoryItem _historyItemFromJson(Map<String, dynamic> json) => BuildHistoryItem(
    id: json['id'] ?? '',
    projectName: json['projectName'] ?? '',
    buildType: BuildType.values.firstWhere(
      (e) => e.value == json['buildType'],
      orElse: () => BuildType.debug,
    ),
    status: BuildStatus.values.firstWhere(
      (e) => e.value == json['status'],
      orElse: () => BuildStatus.pending,
    ),
    startTime: DateTime.parse(json['startTime']),
    endTime: json['endTime'] != null ? DateTime.parse(json['endTime']) : null,
    apkPath: json['apkPath'],
    errorMessage: json['errorMessage'],
    buildNumber: json['buildNumber'],
  );

  /// 触发 GitHub 构建（新增方法）
  Future<BuildHistoryItem?> triggerGitHubBuild({
    required String projectName,
    BuildType buildType = BuildType.debug,
    String branch = 'main',
  }) async {
    _log('开始 GitHub Actions 构建...');
    _log('项目: $projectName');
    _log('类型: ${buildType.label}');
    _log('分支: $branch');

    final buildId = 'github_build_${DateTime.now().millisecondsSinceEpoch}';
    final startTime = DateTime.now();

    // 创建构建记录
    var buildItem = BuildHistoryItem(
      id: buildId,
      projectName: projectName,
      buildType: buildType,
      status: BuildStatus.pending,
      startTime: startTime,
    );

    _currentBuild = buildItem;
    _buildStatusController.add(buildItem);

    try {
      // 获取 GitHub Token
      final token = await _githubToken;
      if (token.isEmpty) {
        throw Exception('未配置 GitHub Token，请在设置中配置');
      }

      // 先检查 workflow 是否存在
      _log('正在连接 GitHub...');
      final workflowsResponse = await http.get(
        Uri.parse('https://api.github.com/repos/$_githubRepo/actions/workflows'),
        headers: {
          'Authorization': 'token $token',
          'Accept': 'application/vnd.github.v3+json',
        },
      );

      if (workflowsResponse.statusCode != 200) {
        throw Exception('无法访问 GitHub 仓库，Token 可能无效或权限不足');
      }

      final workflows = jsonDecode(workflowsResponse.body)['workflows'] as List;
      
      if (workflows.isEmpty) {
        throw Exception('未找到构建工作流');
      }

      // 使用第一个 workflow
      final workflow = workflows.first;
      _log('找到 Workflow: ${workflow['name']}');

      // 触发 workflow
      _log('正在触发构建...');
      final triggerResponse = await http.post(
        Uri.parse('https://api.github.com/repos/$_githubRepo/actions/workflows/${workflow['id']}/runs'),
        headers: {
          'Authorization': 'token $token',
          'Accept': 'application/vnd.github.v3+json',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'ref': branch,
          'inputs': {
            'build_type': buildType.value,
          },
        }),
      );

      if (triggerResponse.statusCode == 201) {
        final runData = jsonDecode(triggerResponse.body);
        final runId = runData['id'];
        
        buildItem = buildItem.copyWith(
          buildNumber: runId,
          status: BuildStatus.running,
        );
        _currentBuild = buildItem;
        _buildStatusController.add(buildItem);
        _log('构建已触发，Run ID: $runId');

        // 开始轮询构建状态
        await _pollGitHubBuildStatus(runId, buildItem, token);
        
        return buildItem;
      } else {
        final errorBody = utf8.decode(triggerResponse.bodyBytes);
        throw Exception('触发构建失败 (${triggerResponse.statusCode}): $errorBody');
      }
    } catch (e) {
      debugPrint('GitHub build trigger error: $e');
      _log('构建触发失败: $e');
      
      buildItem = buildItem.copyWith(
        status: BuildStatus.failure,
        endTime: DateTime.now(),
        errorMessage: e.toString(),
      );
      _currentBuild = buildItem;
      _buildStatusController.add(buildItem);
      _addToHistory(buildItem);
      
      return buildItem;
    }
  }

  /// 轮询 GitHub Actions 构建状态
  Future<void> _pollGitHubBuildStatus(int runId, BuildHistoryItem buildItem, String token) async {
    const maxAttempts = 120; // 最多等待 60 分钟
    var attempts = 0;
    
    while (attempts < maxAttempts) {
      try {
        await Future.delayed(const Duration(seconds: 30));
        
        final response = await http.get(
          Uri.parse('https://api.github.com/repos/$_githubRepo/actions/runs/$runId'),
          headers: {
            'Authorization': 'token $token',
            'Accept': 'application/vnd.github.v3+json',
          },
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final status = data['status'] as String;
          final conclusion = data['conclusion'] as String?;
          
          _log('构建状态: $status${conclusion != null ? ', 结论: $conclusion' : ''}');

          BuildStatus newStatus;
          String? apkPath;
          String? errorMsg;

          switch (conclusion) {
            case 'success':
              newStatus = BuildStatus.success;
              // 获取构建产物（APK 下载链接）
              apkPath = await _getGitHubArtifactUrl(runId, token);
              if (apkPath != null) {
                _log('APK 下载链接: $apkPath');
              }
              _log('构建成功!');
              break;
            case 'failure':
              newStatus = BuildStatus.failure;
              errorMsg = 'GitHub Actions 构建失败';
              _log('构建失败');
              break;
            case 'cancelled':
              newStatus = BuildStatus.cancelled;
              _log('构建已取消');
              break;
            default:
              newStatus = status == 'completed' 
                  ? BuildStatus.failure 
                  : BuildStatus.running;
          }

          if (newStatus != BuildStatus.running) {
            final updatedItem = buildItem.copyWith(
              status: newStatus,
              endTime: DateTime.now(),
              apkPath: apkPath,
              errorMessage: errorMsg,
            );
            _currentBuild = updatedItem;
            _buildStatusController.add(updatedItem);
            _addToHistory(updatedItem);
            return;
          }

          attempts++;
        } else {
          _log('获取状态失败: ${response.statusCode}');
          attempts++;
        }
      } catch (e) {
        debugPrint('Poll error: $e');
        _log('轮询错误: $e');
        attempts++;
      }
    }

    // 超时
    final updatedItem = buildItem.copyWith(
      status: BuildStatus.failure,
      endTime: DateTime.now(),
      errorMessage: '构建超时',
    );
    _currentBuild = updatedItem;
    _buildStatusController.add(updatedItem);
    _addToHistory(updatedItem);
  }

  /// 获取 GitHub 构建产物的下载链接
  Future<String?> _getGitHubArtifactUrl(int runId, String token) async {
    try {
      // 获取 artifacts 列表
      final response = await http.get(
        Uri.parse('https://api.github.com/repos/$_githubRepo/actions/runs/$runId/artifacts'),
        headers: {
          'Authorization': 'token $token',
          'Accept': 'application/vnd.github.v3+json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final artifacts = data['artifacts'] as List;
        
        // 查找 APK 文件
        for (final artifact in artifacts) {
          final name = artifact['name'] as String;
          if (name.contains('apk') || name.contains('app-release')) {
            // 返回下载 URL
            return artifact['archive_download_url'] as String;
          }
        }
        
        // 如果没找到特定名称，返回第一个 artifact
        if (artifacts.isNotEmpty) {
          return artifacts.first['archive_download_url'] as String;
        }
      }
    } catch (e) {
      debugPrint('Failed to get artifact URL: $e');
    }
    return null;
  }

  /// 触发构建（原有方法，保持兼容）
  Future<BuildHistoryItem?> triggerBuild({
    required String projectName,
    BuildType buildType = BuildType.debug,
    String? branch,
    String? workflowId,
    String? projectPath,
  }) async {
    _log('开始触发构建...');
    _log('项目: $projectName');
    _log('类型: ${buildType.label}');
    if (projectPath != null) {
      _log('项目路径: $projectPath');
    }

    final buildId = 'build_${DateTime.now().millisecondsSinceEpoch}';
    final startTime = DateTime.now();

    // 创建构建记录
    var buildItem = BuildHistoryItem(
      id: buildId,
      projectName: projectName,
      buildType: buildType,
      status: BuildStatus.pending,
      startTime: startTime,
    );

    _currentBuild = buildItem;
    _buildStatusController.add(buildItem);

    try {
      // 方法1: 通过 GitHub Actions API 触发
      _log('正在连接 GitHub Actions...');
      
      // 先检查 workflow 是否存在
      final workflowsResponse = await http.get(
        Uri.parse('https://api.github.com/repos/$_githubRepo/actions/workflows'),
        headers: await _getHeaders(),
      );

      if (workflowsResponse.statusCode == 200) {
        final workflows = jsonDecode(workflowsResponse.body)['workflows'] as List;
        
        if (workflows.isEmpty) {
          // 没有 workflow，尝试通过后端 API 构建
          return await _buildViaBackend(
            buildItem: buildItem,
            buildType: buildType,
            projectPath: projectPath,
          );
        }

        // 使用第一个 workflow 或指定的
        final workflow = workflowId != null
            ? workflows.firstWhere((w) => w['id'].toString() == workflowId || w['name'] == workflowId)
            : workflows.first;

        _log('找到 Workflow: ${workflow['name']}');

        // 触发 workflow
        final headers = await _getHeaders();
        final triggerResponse = await http.post(
          Uri.parse('https://api.github.com/repos/$_githubRepo/actions/workflows/${workflow['id']}/runs'),
          headers: {
            ...headers,
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'ref': branch ?? 'main',
            'inputs': {
              'build_type': buildType.value,
            },
          }),
        );

        if (triggerResponse.statusCode == 201) {
          final runData = jsonDecode(triggerResponse.body);
          final runId = runData['id'];
          
          buildItem = buildItem.copyWith(
            buildNumber: runId,
            status: BuildStatus.running,
          );
          _currentBuild = buildItem;
          _buildStatusController.add(buildItem);
          _log('构建已触发，Run ID: $runId');

          // 开始轮询构建状态
          await _pollBuildStatus(runId, buildItem);
          
          return buildItem;
        } else {
          throw Exception('触发构建失败: ${triggerResponse.statusCode}');
        }
      } else {
        // GitHub API 失败，尝试后端
        return await _buildViaBackend(
          buildItem: buildItem,
          buildType: buildType,
          projectPath: projectPath,
        );
      }
    } catch (e) {
      debugPrint('Build trigger error: $e');
      _log('构建触发失败: $e');
      
      // 尝试后端构建
      return await _buildViaBackend(
        buildItem: buildItem,
        buildType: buildType,
        projectPath: projectPath,
      );
    }
  }

  /// 通过后端 API 构建
  Future<BuildHistoryItem?> _buildViaBackend({
    required BuildHistoryItem buildItem,
    required BuildType buildType,
    String? projectPath,
  }) async {
    _log('尝试连接后端构建服务...');
    
    try {
      // 如果有项目路径，打包上传
      if (projectPath != null && projectPath.isNotEmpty) {
        return await _uploadAndBuild(projectPath, buildItem, buildType);
      }
      
      // 默认构建 miss-ide-v2
      final response = await http.post(
        Uri.parse('$_backendApi/api/build/start'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'project': 'miss-ide-v2',
          'type': buildType.value,
          'platform': 'android',
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final buildId = data['build_id'] ?? data['id'];
        
        _log('后端构建已启动，Build ID: $buildId');
        
        var updatedItem = buildItem.copyWith(
          status: BuildStatus.running,
        );
        _currentBuild = updatedItem;
        _buildStatusController.add(updatedItem);

        // 轮询构建状态
        await _pollBackendBuildStatus(buildId, updatedItem);
        
        return updatedItem;
      } else {
        // 后端也不可用，返回本地构建信息
        return await _startLocalBuild(buildItem, buildType);
      }
    } catch (e) {
      debugPrint('Backend build error: $e');
      
      // 尝试本地构建
      return await _startLocalBuild(buildItem, buildType);
    }
  }

  /// 上传项目并构建
  Future<BuildHistoryItem?> _uploadAndBuild(
    String projectPath,
    BuildHistoryItem buildItem,
    BuildType buildType,
  ) async {
    _log('正在打包项目...');
    
    try {
      // 创建项目 zip
      final projectDir = Directory(projectPath);
      if (!await projectDir.exists()) {
        throw Exception('项目目录不存在: $projectPath');
      }
      
      // 创建临时 zip 文件
      final tempDir = await getTemporaryDirectory();
      final zipPath = p.join(tempDir.path, 'project_${DateTime.now().millisecondsSinceEpoch}.zip');
      
      // 使用系统 zip 命令打包
      final zipResult = await Process.run(
        'zip',
        ['-r', zipPath, '.'],
        workingDirectory: projectPath,
      );
      
      if (zipResult.exitCode != 0) {
        // zip 命令失败，尝试手动打包
        await _createZipManually(projectPath, zipPath);
      }
      
      _log('项目已打包，正在上传...');
      
      // 上传到后端
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$_backendApi/api/build/upload'),
      );
      request.files.add(await http.MultipartFile.fromPath('project', zipPath));
      request.fields['type'] = buildType.value;
      
      final response = await request.send().timeout(const Duration(minutes: 5));
      final responseBody = await response.stream.bytesToString();
      
      // 清理临时文件
      await File(zipPath).delete();
      
      if (response.statusCode == 200) {
        final data = jsonDecode(responseBody);
        final buildId = data['build_id'];
        
        _log('上传成功，Build ID: $buildId');
        
        var updatedItem = buildItem.copyWith(
          status: BuildStatus.running,
        );
        _currentBuild = updatedItem;
        _buildStatusController.add(updatedItem);
        
        // 轮询构建状态
        await _pollBackendBuildStatus(buildId, updatedItem);
        
        return updatedItem;
      } else {
        throw Exception('上传失败: ${response.statusCode}');
      }
    } catch (e) {
      _log('上传构建失败: $e');
      return await _startLocalBuild(buildItem, buildType);
    }
  }
  
  /// 手动创建 zip 文件
  Future<void> _createZipManually(String sourceDir, String zipPath) async {
    final encoder = ZipFileEncoder();
    encoder.create(zipPath);
    
    final source = Directory(sourceDir);
    await for (final entity in source.list(recursive: true)) {
      if (entity is File) {
        final relativePath = p.relative(entity.path, from: sourceDir);
        encoder.addFile(entity, relativePath);
      }
    }
    
    encoder.close();
  }

  /// 本地构建（使用 flutter build apk）
  Future<BuildHistoryItem?> _startLocalBuild(
    BuildHistoryItem buildItem,
    BuildType buildType,
  ) async {
    _log('开始本地构建...');
    
    try {
      // 检查 flutter 是否可用
      final flutterCheck = await Process.run('which', ['flutter']);
      
      if (flutterCheck.exitCode != 0) {
        _log('Flutter SDK 未找到');
        
        buildItem = buildItem.copyWith(
          status: BuildStatus.failure,
          endTime: DateTime.now(),
          errorMessage: 'Flutter SDK 未安装或未配置 PATH',
        );
        _addToHistory(buildItem);
        return buildItem;
      }

      var updatedItem = buildItem.copyWith(status: BuildStatus.running);
      _currentBuild = updatedItem;
      _buildStatusController.add(updatedItem);

      // 检查项目目录
      final projectDir = Directory(buildItem.projectName);
      if (!await projectDir.exists()) {
        // 使用当前应用目录
        _log('使用当前应用目录进行构建');
      }

      // 执行构建命令
      final args = ['build', 'apk', '--${buildType.value}'];
      _log('执行命令: flutter ${args.join(' ')}');

      final process = await Process.start('flutter', args);

      // 监听输出
      process.stdout.transform(utf8.decoder).listen((data) {
        _log(data);
      });

      process.stderr.transform(utf8.decoder).listen((data) {
        _log('[ERROR] $data');
      });

      final exitCode = await process.exitCode;

      if (exitCode == 0) {
        // 构建成功
        final apkPath = buildType == BuildType.debug
            ? 'build/app/outputs/flutter-apk/app-debug.apk'
            : 'build/app/outputs/flutter-apk/app-release.apk';

        updatedItem = updatedItem.copyWith(
          status: BuildStatus.success,
          endTime: DateTime.now(),
          apkPath: apkPath,
        );
        _log('构建成功! APK: $apkPath');
      } else {
        updatedItem = updatedItem.copyWith(
          status: BuildStatus.failure,
          endTime: DateTime.now(),
          errorMessage: '构建失败，退出码: $exitCode',
        );
        _log('构建失败，退出码: $exitCode');
      }

      _currentBuild = updatedItem;
      _buildStatusController.add(updatedItem);
      _addToHistory(updatedItem);
      
      return updatedItem;
    } catch (e) {
      debugPrint('Local build error: $e');
      _log('本地构建错误: $e');
      
      final updatedItem = buildItem.copyWith(
        status: BuildStatus.failure,
        endTime: DateTime.now(),
        errorMessage: e.toString(),
      );
      _addToHistory(updatedItem);
      return updatedItem;
    }
  }

  /// 轮询 GitHub Actions 构建状态（原有方法，保持兼容）
  Future<void> _pollBuildStatus(int runId, BuildHistoryItem buildItem) async {
    const maxAttempts = 60; // 最多等待 30 分钟
    var attempts = 0;
    
    while (attempts < maxAttempts) {
      try {
        await Future.delayed(const Duration(seconds: 30));
        
        final response = await http.get(
          Uri.parse('https://api.github.com/repos/$_githubRepo/actions/runs/$runId'),
          headers: await _getHeaders(),
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final status = data['status'] as String;
          final conclusion = data['conclusion'] as String?;
          
          _log('构建状态: $status, 结论: $conclusion');

          BuildStatus newStatus;
          String? apkPath;
          String? errorMsg;

          switch (conclusion) {
            case 'success':
              newStatus = BuildStatus.success;
              // 获取构建产物
              apkPath = await _getBuildArtifact(runId);
              _log('构建成功!');
              break;
            case 'failure':
              newStatus = BuildStatus.failure;
              errorMsg = 'GitHub Actions 构建失败';
              _log('构建失败');
              break;
            case 'cancelled':
              newStatus = BuildStatus.cancelled;
              _log('构建已取消');
              break;
            default:
              newStatus = status == 'completed' 
                  ? BuildStatus.failure 
                  : BuildStatus.running;
          }

          if (newStatus != BuildStatus.running) {
            final updatedItem = buildItem.copyWith(
              status: newStatus,
              endTime: DateTime.now(),
              apkPath: apkPath,
              errorMessage: errorMsg,
            );
            _currentBuild = updatedItem;
            _buildStatusController.add(updatedItem);
            _addToHistory(updatedItem);
            return;
          }

          attempts++;
        } else {
          _log('获取状态失败: ${response.statusCode}');
          attempts++;
        }
      } catch (e) {
        debugPrint('Poll error: $e');
        _log('轮询错误: $e');
        attempts++;
      }
    }

    // 超时
    final updatedItem = buildItem.copyWith(
      status: BuildStatus.failure,
      endTime: DateTime.now(),
      errorMessage: '构建超时',
    );
    _currentBuild = updatedItem;
    _buildStatusController.add(updatedItem);
    _addToHistory(updatedItem);
  }

  /// 获取构建产物
  Future<String?> _getBuildArtifact(int runId) async {
    try {
      final response = await http.get(
        Uri.parse('https://api.github.com/repos/$_githubRepo/actions/runs/$runId/artifacts'),
        headers: await _getHeaders(),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final artifacts = data['artifacts'] as List;
        
        if (artifacts.isNotEmpty) {
          return artifacts.first['archive_download_url'];
        }
      }
    } catch (e) {
      debugPrint('Failed to get artifact: $e');
    }
    return null;
  }

  /// 轮询后端构建状态
  Future<void> _pollBackendBuildStatus(String buildId, BuildHistoryItem buildItem) async {
    const maxAttempts = 120;
    var attempts = 0;
    
    while (attempts < maxAttempts) {
      try {
        await Future.delayed(const Duration(seconds: 15));
        
        final response = await http.get(
          Uri.parse('$_backendApi/api/build/status/$buildId'),
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final status = data['status'] as String?;
          
          _log('后端构建状态: $status');

          BuildStatus newStatus;
          String? apkPath;
          String? errorMsg;

          switch (status) {
            case 'success':
            case 'completed':
              newStatus = BuildStatus.success;
              apkPath = data['apk_url'] ?? data['artifact_path'];
              _log('构建成功!');
              break;
            case 'failed':
            case 'failure':
              newStatus = BuildStatus.failure;
              errorMsg = data['error'] ?? '后端构建失败';
              _log('构建失败: $errorMsg');
              break;
            case 'cancelled':
              newStatus = BuildStatus.cancelled;
              _log('构建已取消');
              break;
            case 'running':
            case 'pending':
            default:
              newStatus = BuildStatus.running;
          }

          if (newStatus != BuildStatus.running) {
            final updatedItem = buildItem.copyWith(
              status: newStatus,
              endTime: DateTime.now(),
              apkPath: apkPath,
              errorMessage: errorMsg,
            );
            _currentBuild = updatedItem;
            _buildStatusController.add(updatedItem);
            _addToHistory(updatedItem);
            return;
          }

          attempts++;
        } else {
          attempts++;
        }
      } catch (e) {
        debugPrint('Backend poll error: $e');
        _log('轮询错误: $e');
        attempts++;
      }
    }

    // 超时
    final updatedItem = buildItem.copyWith(
      status: BuildStatus.failure,
      endTime: DateTime.now(),
      errorMessage: '构建超时',
    );
    _currentBuild = updatedItem;
    _buildStatusController.add(updatedItem);
    _addToHistory(updatedItem);
  }

  /// 下载 APK
  Future<String?> downloadApk(String url) async {
    try {
      _log('开始下载 APK...');
      
      final response = await http.get(
        Uri.parse(url),
        headers: await _getHeaders(),
      );

      if (response.statusCode == 200) {
        final docDir = await getApplicationDocumentsDirectory();
        final apkPath = p.join(docDir.path, 'downloads', 'miss-ide-${DateTime.now().millisecondsSinceEpoch}.apk');
        
        final file = File(apkPath);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(response.bodyBytes);
        
        _log('APK 已下载: $apkPath');
        return apkPath;
      } else {
        _log('下载失败: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('Download error: $e');
      _log('下载错误: $e');
      return null;
    }
  }

  /// 取消构建
  Future<void> cancelBuild() async {
    if (_currentBuild?.buildNumber != null) {
      try {
        final runId = _currentBuild!.buildNumber;
        await http.post(
          Uri.parse('https://api.github.com/repos/$_githubRepo/actions/runs/$runId/cancel'),
          headers: await _getHeaders(),
        );
        _log('构建已取消');
      } catch (e) {
        debugPrint('Cancel error: $e');
      }
    }
    
    final updatedItem = _currentBuild?.copyWith(
      status: BuildStatus.cancelled,
      endTime: DateTime.now(),
    );
    
    if (updatedItem != null) {
      _addToHistory(updatedItem);
    }
    
    _currentBuild = null;
    _buildStatusController.add(null);
  }

  /// 添加到历史记录
  void _addToHistory(BuildHistoryItem item) {
    _buildHistory.insert(0, item);
    if (_buildHistory.length > 50) {
      _buildHistory.removeRange(50, _buildHistory.length);
    }
    _saveHistory();
    _historyController.add(_buildHistory);
  }

  /// 记录日志
  void _log(String message) {
    final timestamp = DateTime.now().toString().substring(11, 19);
    _logController.add('[$timestamp] $message');
    debugPrint(message);
  }

  /// 获取历史记录
  List<BuildHistoryItem> getHistory() => List.from(_buildHistory);
  
  /// 清空历史记录
  Future<void> clearHistory() async {
    _buildHistory.clear();
    await _saveHistory();
    _historyController.add(_buildHistory);
  }
}

// 全局实例
final buildService = BuildService();
