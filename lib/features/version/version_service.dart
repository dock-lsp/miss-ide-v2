import 'dart:io';
import 'package:flutter/services.dart';

/// 版本号数据模型
class VersionInfo {
  final int major;
  final int minor;
  final int patch;
  final int buildNumber;
  final DateTime? buildTime;
  final String? commitHash;

  VersionInfo({
    required this.major,
    required this.minor,
    required this.patch,
    required this.buildNumber,
    this.buildTime,
    this.commitHash,
  });

  /// 从版本字符串解析（如 "2.0.0+1"）
  factory VersionInfo.fromVersionString(String version) {
    final parts = version.split('+');
    final versionParts = parts[0].split('.');
    final buildNumber = parts.length > 1 ? int.tryParse(parts[1]) ?? 1 : 1;

    return VersionInfo(
      major: versionParts.isNotEmpty ? int.tryParse(versionParts[0]) ?? 2 : 2,
      minor: versionParts.length > 1 ? int.tryParse(versionParts[1]) ?? 0 : 0,
      patch: versionParts.length > 2 ? int.tryParse(versionParts[2]) ?? 0 : 0,
      buildNumber: buildNumber,
    );
  }

  /// 从 Map 解析（用于 JSON 存储）
  factory VersionInfo.fromJson(Map<String, dynamic> json) {
    return VersionInfo(
      major: json['major'] ?? 2,
      minor: json['minor'] ?? 0,
      patch: json['patch'] ?? 0,
      buildNumber: json['buildNumber'] ?? 1,
      buildTime: json['buildTime'] != null 
          ? DateTime.tryParse(json['buildTime']) 
          : null,
      commitHash: json['commitHash'],
    );
  }

  /// 转换为 Map（用于 JSON 存储）
  Map<String, dynamic> toJson() {
    return {
      'major': major,
      'minor': minor,
      'patch': patch,
      'buildNumber': buildNumber,
      'buildTime': buildTime?.toIso8601String(),
      'commitHash': commitHash,
    };
  }

  /// 获取版本字符串（如 "2.0.0+1"）
  String get versionString {
    return '$major.$minor.$patch+$buildNumber';
  }

  /// 获取显示版本（如 "v2.0.0 (Build 1)"）
  String get displayVersion {
    return 'v$major.$minor.$patch (Build $buildNumber)';
  }

  /// 获取 Git tag（如 "v2.0.0"）
  String get gitTag {
    return 'v$major.$minor.$patch';
  }

  /// 创建新版本（递增 build number）
  VersionInfo incrementBuild() {
    return VersionInfo(
      major: major,
      minor: minor,
      patch: patch,
      buildNumber: buildNumber + 1,
      buildTime: DateTime.now(),
      commitHash: commitHash,
    );
  }

  /// 创建新补丁版本（递增 patch，重置 build number）
  VersionInfo incrementPatch() {
    return VersionInfo(
      major: major,
      minor: minor,
      patch: patch + 1,
      buildNumber: 1,
      buildTime: DateTime.now(),
      commitHash: commitHash,
    );
  }

  /// 创建新次版本（递增 minor，重置 patch 和 build number）
  VersionInfo incrementMinor() {
    return VersionInfo(
      major: major,
      minor: minor + 1,
      patch: 0,
      buildNumber: 1,
      buildTime: DateTime.now(),
      commitHash: commitHash,
    );
  }

  /// 创建新主版本（递增 major，重置 minor、patch 和 build number）
  VersionInfo incrementMajor() {
    return VersionInfo(
      major: major + 1,
      minor: 0,
      patch: 0,
      buildNumber: 1,
      buildTime: DateTime.now(),
      commitHash: commitHash,
    );
  }

  @override
  String toString() => versionString;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is VersionInfo &&
        other.major == major &&
        other.minor == minor &&
        other.patch == patch &&
        other.buildNumber == buildNumber;
  }

  @override
  int get hashCode => Object.hash(major, minor, patch, buildNumber);
}

/// 版本服务 - 管理版本号读取和更新
class VersionService {
  static const _pubspecPath = 'pubspec.yaml';
  
  VersionInfo? _currentVersion;
  static VersionService? _instance;

  VersionService._();

  static VersionService get instance {
    _instance ??= VersionService._();
    return _instance!;
  }

  /// 获取当前版本
  VersionInfo get currentVersion {
    if (_currentVersion != null) return _currentVersion!;
    _currentVersion = VersionInfo.fromVersionString('2.0.0+1');
    return _currentVersion!;
  }

  /// 从 pubspec.yaml 加载版本
  Future<VersionInfo?> loadFromPubspec() async {
    try {
      // 尝试从 pubspec.yaml 读取
      final file = File(_pubspecPath);
      if (await file.exists()) {
        final content = await file.readAsString();
        final version = _parseVersionFromYaml(content);
        if (version != null) {
          _currentVersion = version;
          return version;
        }
      }
    } catch (e) {
      // 如果读取失败，尝试从方法通道获取
    }
    
    // 回退到方法通道获取版本
    try {
      const channel = MethodChannel('com.misside.v2/version');
      final versionString = await channel.invokeMethod<String>('getVersion');
      if (versionString != null) {
        _currentVersion = VersionInfo.fromVersionString(versionString);
        return _currentVersion;
      }
    } catch (e) {
      // 方法通道不可用
    }
    
    return null;
  }

  /// 解析 YAML 中的版本号
  VersionInfo? _parseVersionFromYaml(String yamlContent) {
    final lines = yamlContent.split('\n');
    for (final line in lines) {
      if (line.trim().startsWith('version:')) {
        final version = line.split(':').last.trim();
        return VersionInfo.fromVersionString(version);
      }
    }
    return null;
  }

  /// 递增版本号并更新 pubspec.yaml
  Future<VersionInfo?> incrementBuildNumber() async {
    if (_currentVersion == null) {
      await loadFromPubspec();
    }
    
    final newVersion = currentVersion.incrementBuild();
    await _updatePubspecVersion(newVersion);
    _currentVersion = newVersion;
    return newVersion;
  }

  /// 更新 pubspec.yaml 中的版本号
  Future<bool> _updatePubspecVersion(VersionInfo version) async {
    try {
      final file = File(_pubspecPath);
      if (!await file.exists()) return false;
      
      final content = await file.readAsString();
      final lines = content.split('\n');
      final newLines = <String>[];
      
      for (final line in lines) {
        if (line.trim().startsWith('version:')) {
          newLines.add('version: ${version.versionString}');
        } else {
          newLines.add(line);
        }
      }
      
      await file.writeAsString(newLines.join('\n'));
      return true;
    } catch (e) {
      return false;
    }
  }

  /// 获取 GitHub Release URL
  String getReleaseUrl(String version) {
    return 'https://github.com/qq00150610-cpu/miss-ide-v2/releases/tag/v$version';
  }

  /// 获取 GitHub Releases 页面
  String get releasesPageUrl {
    return 'https://github.com/qq00150610-cpu/miss-ide-v2/releases';
  }
}

/// 全局版本服务实例
final versionService = VersionService.instance;
