// 版本更新脚本
// 运行方式: dart scripts/bump_version.dart [build|patch|minor|major]
// 或者在 Flutter 构建前自动调用

import 'dart:io';

void main(List<String> args) async {
  final versionType = args.isNotEmpty ? args[0] : 'build';
  
  // 获取项目根目录
  final projectRoot = Directory.current.path;
  final pubspecFile = File('$projectRoot/pubspec.yaml');
  
  if (!await pubspecFile.exists()) {
    print('错误: pubspec.yaml 不存在');
    exit(1);
  }
  
  // 读取当前版本
  final content = await pubspecFile.readAsString();
  final currentVersion = _parseVersion(content);
  
  print('当前版本: $currentVersion');
  
  // 根据类型递增版本
  final newVersion = _incrementVersion(currentVersion, versionType);
  print('新版本: $newVersion');
  
  // 更新 pubspec.yaml
  final newContent = content.replaceFirst(
    RegExp(r'^version:.*', multiLine: true),
    'version: $newVersion',
  );
  
  await pubspecFile.writeAsString(newContent);
  print('✓ pubspec.yaml 已更新');
  
  // 检查 git 状态并提交
  try {
    final result = await Process.run('git', ['diff', '--quiet', 'pubspec.yaml']);
    if (result.exitCode != 0) {
      await Process.run('git', ['add', 'pubspec.yaml']);
      await Process.run('git', ['commit', '-m', 'chore: bump version to $newVersion']);
      print('✓ 已提交版本更新');
    }
  } catch (e) {
    print('Git 提交跳过 (非 git 仓库或无权限)');
  }
  
  print('');
  print('==========================================');
  print('版本更新完成');
  print('==========================================');
}

String _parseVersion(String content) {
  final match = RegExp(r'^version:\s*(.+)', multiLine: true).firstMatch(content);
  if (match == null) {
    return '2.0.0+1'; // 默认版本
  }
  return match.group(1)!.trim();
}

String _incrementVersion(String version, String type) {
  // 解析版本号
  final parts = version.split('+');
  final versionParts = parts[0].split('.');
  final build = parts.length > 1 ? int.tryParse(parts[1]) ?? 1 : 1;
  
  var major = versionParts.isNotEmpty ? int.tryParse(versionParts[0]) ?? 2 : 2;
  var minor = versionParts.length > 1 ? int.tryParse(versionParts[1]) ?? 0 : 0;
  var patch = versionParts.length > 2 ? int.tryParse(versionParts[2]) ?? 0 : 0;
  
  // 根据类型递增
  switch (type) {
    case 'build':
      return '$major.$minor.$patch+${build + 1}';
    case 'patch':
      return '$major.$minor.${patch + 1}+1';
    case 'minor':
      return '$major.${minor + 1}.0+1';
    case 'major':
      return '${major + 1}.0.0+1';
    default:
      return '$major.$minor.$patch+${build + 1}';
  }
}
