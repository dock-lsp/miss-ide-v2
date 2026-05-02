import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'app/app.dart';
import 'features/ai/ai_service.dart';

Future<void> requestPermissions() async {
  // 请求存储权限
  await [
    Permission.storage,
    Permission.manageExternalStorage,
  ].request();
  
  // 检查是否有管理外部存储权限（Android 11+）
  if (!await Permission.manageExternalStorage.isGranted) {
    // 如果没有，尝试请求
    await Permission.manageExternalStorage.request();
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 请求必要权限
  await requestPermissions();
  
  // 初始化AI服务
  await aiService.init();
  
  // 初始化主题设置
  await initThemeMode();
  
  runApp(
    const ProviderScope(
      child: MissIDEApp(),
    ),
  );
}

