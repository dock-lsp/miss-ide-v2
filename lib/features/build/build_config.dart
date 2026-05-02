/// 构建配置模型
/// 定义构建所需的配置信息

enum BuildType {
  debug('debug', '调试构建'),
  release('release', '发布构建');
	
  final String value;
  final String label;
  const BuildType(this.value, this.label);
}

enum BuildStatus {
  pending('pending', '等待中'),
  running('running', '构建中'),
  success('success', '构建成功'),
  failure('failure', '构建失败'),
  cancelled('cancelled', '已取消');

  final String value;
  final String label;
  const BuildStatus(this.value, this.label);
}

class SigningConfig {
  final String keystorePath;
  final String keystorePassword;
  final String keyAlias;
  final String keyPassword;
  final bool isDebug;

  const SigningConfig({
    this.keystorePath = '',
    this.keystorePassword = '',
    this.keyAlias = '',
    this.keyPassword = '',
    this.isDebug = true,
  });

  SigningConfig copyWith({
    String? keystorePath,
    String? keystorePassword,
    String? keyAlias,
    String? keyPassword,
    bool? isDebug,
  }) {
    return SigningConfig(
      keystorePath: keystorePath ?? this.keystorePath,
      keystorePassword: keystorePassword ?? this.keystorePassword,
      keyAlias: keyAlias ?? this.keyAlias,
      keyPassword: keyPassword ?? this.keyPassword,
      isDebug: isDebug ?? this.isDebug,
    );
  }

  Map<String, dynamic> toJson() => {
    'keystorePath': keystorePath,
    'keystorePassword': keystorePassword,
    'keyAlias': keyAlias,
    'keyPassword': keyPassword,
    'isDebug': isDebug,
  };

  factory SigningConfig.fromJson(Map<String, dynamic> json) {
    return SigningConfig(
      keystorePath: json['keystorePath'] ?? '',
      keystorePassword: json['keystorePassword'] ?? '',
      keyAlias: json['keyAlias'] ?? '',
      keyPassword: json['keyPassword'] ?? '',
      isDebug: json['isDebug'] ?? true,
    );
  }

  static SigningConfig get debugDefault => const SigningConfig(
    isDebug: true,
    keystorePath: 'debug.keystore',
    keystorePassword: 'android',
    keyAlias: 'androiddebugkey',
    keyPassword: 'android',
  );

  bool get isValid =>
    keystorePath.isNotEmpty &&
    keystorePassword.isNotEmpty &&
    keyAlias.isNotEmpty &&
    keyPassword.isNotEmpty;
}

class BuildConfig {
  final String projectName;
  final String projectPath;
  final BuildType buildType;
  final SigningConfig signingConfig;
  final String outputPath;
  final bool enableProguard;
  final bool useGitHubBuild;  // 新增：是否使用 GitHub 构建
	
  const BuildConfig({
    required this.projectName,
    required this.projectPath,
    this.buildType = BuildType.debug,
    this.signingConfig = const SigningConfig(),
    this.outputPath = '/storage/emulated/0/Download',
    this.enableProguard = false,
    this.useGitHubBuild = true,  // 默认使用 GitHub 构建
  });

  BuildConfig copyWith({
    String? projectName,
    String? projectPath,
    BuildType? buildType,
    SigningConfig? signingConfig,
    String? outputPath,
    bool? enableProguard,
    bool? useGitHubBuild,
  }) {
    return BuildConfig(
      projectName: projectName ?? this.projectName,
      projectPath: projectPath ?? this.projectPath,
      buildType: buildType ?? this.buildType,
      signingConfig: signingConfig ?? this.signingConfig,
      outputPath: outputPath ?? this.outputPath,
      enableProguard: enableProguard ?? this.enableProguard,
      useGitHubBuild: useGitHubBuild ?? this.useGitHubBuild,
    );
  }

  Map<String, dynamic> toJson() => {
    'projectName': projectName,
    'projectPath': projectPath,
    'buildType': buildType.value,
    'signingConfig': signingConfig.toJson(),
    'outputPath': outputPath,
    'enableProguard': enableProguard,
    'useGitHubBuild': useGitHubBuild,
  };

  factory BuildConfig.fromJson(Map<String, dynamic> json) {
    return BuildConfig(
      projectName: json['projectName'] ?? '',
      projectPath: json['projectPath'] ?? '',
      buildType: BuildType.values.firstWhere(
        (e) => e.value == json['buildType'],
        orElse: () => BuildType.debug,
      ),
      signingConfig: SigningConfig.fromJson(json['signingConfig'] ?? {}),
      outputPath: json['outputPath'] ?? '/storage/emulated/0/Download',
      enableProguard: json['enableProguard'] ?? false,
      useGitHubBuild: json['useGitHubBuild'] ?? true,
    );
  }
}

class BuildHistoryItem {
  final String id;
  final String projectName;
  final BuildType buildType;
  final BuildStatus status;
  final DateTime startTime;
  final DateTime? endTime;
  final String? apkPath;
  final String? errorMessage;
  final int? buildNumber;

  const BuildHistoryItem({
    required this.id,
    required this.projectName,
    required this.buildType,
    required this.status,
    required this.startTime,
    this.endTime,
    this.apkPath,
    this.errorMessage,
    this.buildNumber,
  });

  Duration? get duration {
    if (endTime == null) return null;
    return endTime!.difference(startTime);
  }

  String get durationString {
    final d = duration;
    if (d == null) return '--';
    if (d.inHours > 0) {
      return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
    } else if (d.inMinutes > 0) {
      return '${d.inMinutes}m ${d.inSeconds.remainder(60)}s';
    } else {
      return '${d.inSeconds}s';
    }
  }

  BuildHistoryItem copyWith({
    String? id,
    String? projectName,
    BuildType? buildType,
    BuildStatus? status,
    DateTime? startTime,
    DateTime? endTime,
    String? apkPath,
    String? errorMessage,
    int? buildNumber,
  }) {
    return BuildHistoryItem(
      id: id ?? this.id,
      projectName: projectName ?? this.projectName,
      buildType: buildType ?? this.buildType,
      status: status ?? this.status,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      apkPath: apkPath ?? this.apkPath,
      errorMessage: errorMessage ?? this.errorMessage,
      buildNumber: buildNumber ?? this.buildNumber,
    );
  }
}
