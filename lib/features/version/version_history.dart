import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'version_service.dart';

/// 版本历史记录项
class VersionHistoryItem {
  final VersionInfo version;
  final DateTime createdAt;
  final String? commitHash;
  final String? changelog;
  final bool isRelease;

  VersionHistoryItem({
    required this.version,
    required this.createdAt,
    this.commitHash,
    this.changelog,
    this.isRelease = false,
  });

  factory VersionHistoryItem.fromJson(Map<String, dynamic> json) {
    return VersionHistoryItem(
      version: VersionInfo.fromJson(json['version']),
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
      commitHash: json['commitHash'],
      changelog: json['changelog'],
      isRelease: json['isRelease'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'version': version.toJson(),
      'createdAt': createdAt.toIso8601String(),
      'commitHash': commitHash,
      'changelog': changelog,
      'isRelease': isRelease,
    };
  }
}

/// 版本历史存储服务
class VersionHistoryService {
  static const _storageKey = 'version_history';
  static const _maxHistorySize = 20;
  
  static VersionHistoryService? _instance;
  SharedPreferences? _prefs;

  VersionHistoryService._();

  static VersionHistoryService get instance {
    _instance ??= VersionHistoryService._();
    return _instance!;
  }

  /// 初始化
  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  /// 获取所有版本历史
  Future<List<VersionHistoryItem>> getHistory() async {
    await init();
    
    final jsonString = _prefs?.getString(_storageKey);
    if (jsonString == null || jsonString.isEmpty) {
      return [];
    }
    
    try {
      final List<dynamic> jsonList = json.decode(jsonString);
      return jsonList
          .map((e) => VersionHistoryItem.fromJson(e))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } catch (e) {
      return [];
    }
  }

  /// 添加版本记录
  Future<void> addVersion(VersionInfo version, {
    String? commitHash,
    String? changelog,
    bool isRelease = false,
  }) async {
    await init();
    
    final history = await getHistory();
    
    // 检查是否已存在相同版本
    final existingIndex = history.indexWhere(
      (item) => item.version.versionString == version.versionString,
    );
    
    if (existingIndex != -1) {
      // 更新现有记录
      history[existingIndex] = VersionHistoryItem(
        version: version,
        createdAt: history[existingIndex].createdAt,
        commitHash: commitHash ?? history[existingIndex].commitHash,
        changelog: changelog ?? history[existingIndex].changelog,
        isRelease: isRelease,
      );
    } else {
      // 添加新记录
      history.insert(
        0,
        VersionHistoryItem(
          version: version,
          createdAt: DateTime.now(),
          commitHash: commitHash,
          changelog: changelog,
          isRelease: isRelease,
        ),
      );
    }
    
    // 限制历史记录数量
    final trimmedHistory = history.take(_maxHistorySize).toList();
    
    // 保存
    final jsonString = json.encode(trimmedHistory.map((e) => e.toJson()).toList());
    await _prefs?.setString(_storageKey, jsonString);
  }

  /// 获取最新发布版本
  Future<VersionHistoryItem?> getLatestRelease() async {
    final history = await getHistory();
    try {
      return history.firstWhere((item) => item.isRelease);
    } catch (e) {
      return null;
    }
  }

  /// 获取所有发布版本
  Future<List<VersionHistoryItem>> getReleases() async {
    final history = await getHistory();
    return history.where((item) => item.isRelease).toList();
  }

  /// 清空历史记录
  Future<void> clearHistory() async {
    await init();
    await _prefs?.remove(_storageKey);
  }

  /// 删除单条记录
  Future<void> deleteItem(String versionString) async {
    await init();
    
    final history = await getHistory();
    history.removeWhere((item) => item.version.versionString == versionString);
    
    final jsonString = json.encode(history.map((e) => e.toJson()).toList());
    await _prefs?.setString(_storageKey, jsonString);
  }
}

/// 全局版本历史服务实例
final versionHistoryService = VersionHistoryService.instance;
