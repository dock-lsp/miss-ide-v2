import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'build_config.dart';

/// 签名管理器
/// 负责密钥库生成、签名配置管理
class SigningManager {
  static const _storage = FlutterSecureStorage();
  static const _signingConfigKey = 'signing_configs';
  
  /// 保存签名配置
  static Future<void> saveSigningConfig(String name, SigningConfig config) async {
    final configs = await _loadAllConfigs();
    configs[name] = config;
    await _storage.write(
      key: _signingConfigKey,
      value: jsonEncode(configs.map((k, v) => MapEntry(k, v.toJson()))),
    );
  }

  /// 获取签名配置
  static Future<SigningConfig?> getSigningConfig(String name) async {
    final configs = await _loadAllConfigs();
    return configs[name];
  }

  /// 获取所有签名配置名称
  static Future<List<String>> getSigningConfigNames() async {
    final configs = await _loadAllConfigs();
    return configs.keys.toList();
  }

  /// 删除签名配置
  static Future<void> deleteSigningConfig(String name) async {
    final configs = await _loadAllConfigs();
    configs.remove(name);
    await _storage.write(
      key: _signingConfigKey,
      value: jsonEncode(configs.map((k, v) => MapEntry(k, v.toJson()))),
    );
  }

  /// 加载所有配置
  static Future<Map<String, SigningConfig>> _loadAllConfigs() async {
    final data = await _storage.read(key: _signingConfigKey);
    if (data == null) return {};
    
    try {
      final Map<String, dynamic> json = jsonDecode(data);
      return json.map((k, v) => MapEntry(
        k,
        SigningConfig.fromJson(v as Map<String, dynamic>),
      ));
    } catch (e) {
      debugPrint('Failed to load signing configs: $e');
      return {};
    }
  }

  /// 生成新的密钥库
  /// 使用 keytool 命令生成
  static Future<String?> generateKeystore({
    required String keystorePath,
    required String keystorePassword,
    required String keyAlias,
    required String keyPassword,
    String? commonName,
    String? organization,
    String? locality,
    String? state,
    String? country,
  }) async {
    try {
      // 检查 keytool 是否可用
      final keytoolCheck = await Process.run('which', ['keytool']);
      if (keytoolCheck.exitCode != 0) {
        // keytool 不可用，返回生成密钥信息供手动使用
        debugPrint('keytool not found, generating keystore info');
        return _generateKeystoreInfo(
          keystorePath: keystorePath,
          keystorePassword: keystorePassword,
          keyAlias: keyAlias,
          keyPassword: keyPassword,
          commonName: commonName,
          organization: organization,
          locality: locality,
          state: state,
          country: country,
        );
      }

      // 生成密钥库
      final args = [
        '-genkey',
        '-v',
        '-keystore', keystorePath,
        '-alias', keyAlias,
        '-keyalg', 'RSA',
        '-keysize', '2048',
        '-validity', '10000',
        '-storepass', keystorePassword,
        '-keypass', keyPassword,
        '-dname', _buildDname(
          commonName: commonName ?? 'Android Debug',
          organization: organization ?? 'Unknown',
          locality: locality ?? 'Unknown',
          state: state ?? 'Unknown',
          country: country ?? 'US',
        ),
      ];

      final result = await Process.run('keytool', args);
      
      if (result.exitCode == 0) {
        debugPrint('Keystore generated successfully: $keystorePath');
        return keystorePath;
      } else {
        debugPrint('keytool error: ${result.stderr}');
        return null;
      }
    } catch (e) {
      debugPrint('Failed to generate keystore: $e');
      return null;
    }
  }

  /// 构建 DNAME 参数
  static String _buildDname({
    required String commonName,
    required String organization,
    required String locality,
    required String state,
    required String country,
  }) {
    return 'CN=$commonName, O=$organization, L=$locality, ST=$state, C=$country';
  }

  /// 生成密钥库信息（供手动创建）
  static String _generateKeystoreInfo({
    required String keystorePath,
    required String keystorePassword,
    required String keyAlias,
    required String keyPassword,
    String? commonName,
    String? organization,
    String? locality,
    String? state,
    String? country,
  }) {
    // 返回命令行供用户手动执行
    return '''密钥库生成命令:

keytool -genkey -v \\
  -keystore "$keystorePath" \\
  -alias "$keyAlias" \\
  -keyalg RSA \\
  -keysize 2048 \\
  -validity 10000 \\
  -storepass "$keystorePassword" \\
  -keypass "$keyPassword" \\
  -dname "CN=${commonName ?? 'Android Debug'}, O=${organization ?? 'Unknown'}, L=${locality ?? 'Unknown'}, ST=${state ?? 'Unknown'}, C=${country ?? 'US'}"

配置信息已保存:
- 密钥库路径: $keystorePath
- 密钥库密码: $keystorePassword
- 别名: $keyAlias
- 别名密码: $keyPassword
''';
  }

  /// 验证密钥库是否存在且有效
  static Future<bool> validateKeystore({
    required String keystorePath,
    required String keystorePassword,
    required String keyAlias,
  }) async {
    try {
      final keytoolCheck = await Process.run('which', ['keytool']);
      if (keytoolCheck.exitCode != 0) {
        // 无法验证，只检查文件是否存在
        final file = File(keystorePath);
        return await file.exists();
      }

      final result = await Process.run('keytool', [
        '-list',
        '-keystore', keystorePath,
        '-alias', keyAlias,
        '-storepass', keystorePassword,
      ]);

      return result.exitCode == 0;
    } catch (e) {
      debugPrint('Keystore validation error: $e');
      return false;
    }
  }

  /// 列出密钥库中的所有别名
  static Future<List<String>> listKeystoreAliases({
    required String keystorePath,
    required String keystorePassword,
  }) async {
    try {
      final keytoolCheck = await Process.run('which', ['keytool']);
      if (keytoolCheck.exitCode != 0) {
        return [];
      }

      final result = await Process.run('keytool', [
        '-list',
        '-keystore', keystorePath,
        '-storepass', keystorePassword,
      ]);

      if (result.exitCode == 0) {
        final output = result.stdout as String;
        final aliases = <String>[];
        final lines = output.split('\n');
        
        for (final line in lines) {
          if (line.contains('PrivateKeyEntry') || line.contains('TrustedCertEntry')) {
            final match = RegExp(r'^([^,]+)').firstMatch(line.trim());
            if (match != null) {
              aliases.add(match.group(1)!);
            }
          }
        }
        
        return aliases;
      }
      return [];
    } catch (e) {
      debugPrint('List aliases error: $e');
      return [];
    }
  }

  /// 导出 Debug 签名信息（用于其他项目使用相同签名）
  static Future<Map<String, String>?> exportDebugSigningInfo() async {
    final homeDir = Platform.environment['HOME'] ?? '';
    final defaultDebugKeystore = p.join(homeDir, '.android', 'debug.keystore');
    
    final file = File(defaultDebugKeystore);
    if (!await file.exists()) {
      return null;
    }

    return {
      'keystorePath': defaultDebugKeystore,
      'keystorePassword': 'android',
      'keyAlias': 'androiddebugkey',
      'keyPassword': 'android',
    };
  }

  /// 获取默认的签名配置路径
  static Future<String> getDefaultKeystorePath() async {
    final docDir = await getApplicationDocumentsDirectory();
    return p.join(docDir.path, 'keystore', 'release.keystore');
  }

  /// 导出签名配置
  static Future<String?> exportSigningConfig(SigningConfig config, String exportPath) async {
    try {
      final file = File(exportPath);
      await file.writeAsString(jsonEncode(config.toJson()));
      return exportPath;
    } catch (e) {
      debugPrint('Failed to export signing config: $e');
      return null;
    }
  }

  /// 导入签名配置
  static Future<SigningConfig?> importSigningConfig(String importPath) async {
    try {
      final file = File(importPath);
      if (!await file.exists()) return null;
      
      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      return SigningConfig.fromJson(json);
    } catch (e) {
      debugPrint('Failed to import signing config: $e');
      return null;
    }
  }
}
