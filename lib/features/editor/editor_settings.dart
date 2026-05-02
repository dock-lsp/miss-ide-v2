import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 编辑器设置
class EditorSettings {
  Color backgroundColor;
  Color fontColor;
  double fontSize;
  double lineHeight;
  bool showLineNumbers;
  bool autoSave;
  int autoSaveDelay; // 秒
  int tabSize;
  bool useSpaces;

  EditorSettings({
    this.backgroundColor = const Color(0xFF1E1E1E),
    this.fontColor = const Color(0xFFD4D4D4),
    this.fontSize = 14.0,
    this.lineHeight = 1.5,
    this.showLineNumbers = true,
    this.autoSave = true,
    this.autoSaveDelay = 5,
    this.tabSize = 2,
    this.useSpaces = true,
  });

  /// 兼容旧代码的别名
  Color get textColor => fontColor;
  set textColor(Color value) => fontColor = value;

  EditorSettings copyWith({
    Color? backgroundColor,
    Color? fontColor,
    double? fontSize,
    double? lineHeight,
    bool? showLineNumbers,
    bool? autoSave,
    int? autoSaveDelay,
    int? tabSize,
    bool? useSpaces,
  }) {
    return EditorSettings(
      backgroundColor: backgroundColor ?? this.backgroundColor,
      fontColor: fontColor ?? this.fontColor,
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      showLineNumbers: showLineNumbers ?? this.showLineNumbers,
      autoSave: autoSave ?? this.autoSave,
      autoSaveDelay: autoSaveDelay ?? this.autoSaveDelay,
      tabSize: tabSize ?? this.tabSize,
      useSpaces: useSpaces ?? this.useSpaces,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'backgroundColor': backgroundColor.value,
      'fontColor': fontColor.value,
      'fontSize': fontSize,
      'lineHeight': lineHeight,
      'showLineNumbers': showLineNumbers,
      'autoSave': autoSave,
      'autoSaveDelay': autoSaveDelay,
      'tabSize': tabSize,
      'useSpaces': useSpaces,
    };
  }

  factory EditorSettings.fromJson(Map<String, dynamic> json) {
    return EditorSettings(
      backgroundColor: Color(json['backgroundColor'] ?? 0xFF1E1E1E),
      fontColor: Color(json['fontColor'] ?? 0xFFD4D4D4),
      fontSize: (json['fontSize'] ?? 14.0).toDouble(),
      lineHeight: (json['lineHeight'] ?? 1.5).toDouble(),
      showLineNumbers: json['showLineNumbers'] ?? true,
      autoSave: json['autoSave'] ?? true,
      autoSaveDelay: json['autoSaveDelay'] ?? 5,
      tabSize: json['tabSize'] ?? 2,
      useSpaces: json['useSpaces'] ?? true,
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('editor_settings', toJson().toString());
  }

  static Future<EditorSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString('editor_settings');
    if (data == null) return EditorSettings();
    // 简单解析
    try {
      final Map<String, dynamic> json = {};
      final content = data.replaceAll('{', '').replaceAll('}', '');
      final pairs = content.split(',');
      for (final pair in pairs) {
        final kv = pair.split(':');
        if (kv.length == 2) {
          final key = kv[0].trim();
          final value = kv[1].trim();
          if (key == 'backgroundColor' || key == 'fontColor') {
            json[key] = int.parse(value);
          } else if (key == 'fontSize' || key == 'lineHeight') {
            json[key] = double.parse(value);
          } else if (key == 'showLineNumbers' || key == 'autoSave' || key == 'useSpaces') {
            json[key] = value == 'true';
          } else {
            json[key] = int.parse(value);
          }
        }
      }
      return EditorSettings.fromJson(json);
    } catch (e) {
      return EditorSettings();
    }
  }
}

/// 预设颜色主题
class EditorColorPresets {
  static List<Map<String, dynamic>> getAllPresets() {
    return [
      {'name': '深色', 'background': const Color(0xFF1E1E1E), 'text': const Color(0xFFD4D4D4), 'icon': Icons.dark_mode},
      {'name': '更深夜色', 'background': const Color(0xFF0D0D0D), 'text': const Color(0xFFCCCCCC), 'icon': Icons.nights_stay},
      {'name': '浅色', 'background': const Color(0xFFFFFFFF), 'text': const Color(0xFF333333), 'icon': Icons.light_mode},
      {'name': '护眼绿', 'background': const Color(0xFFCCE8CF), 'text': const Color(0xFF2E4A2E), 'icon': Icons.grass},
      {'name': '海洋蓝', 'background': const Color(0xFF1E3A5F), 'text': const Color(0xFFB8D4E8), 'icon': Icons.water},
      {'name': '紫罗兰', 'background': const Color(0xFF2D1B4E), 'text': const Color(0xFFE8D8F0), 'icon': Icons.auto_awesome},
    ];
  }
}
