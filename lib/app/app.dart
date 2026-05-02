import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'theme.dart';
import 'package:miss_ide/features/editor/code_editor.dart';
import 'package:miss_ide/features/ai/ai_chat.dart';
import 'package:miss_ide/features/settings/settings_page.dart';
import 'package:miss_ide/features/file_manager/file_browser.dart';
import 'package:miss_ide/features/project/project_page.dart';
import 'package:miss_ide/features/build/build.dart';

/// 全局主题模式通知器
final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier(ThemeMode.system);

/// 初始化主题设置
Future<void> initThemeMode() async {
  const storage = FlutterSecureStorage();
  final savedMode = await storage.read(key: 'theme_mode');
  if (savedMode != null) {
    final index = int.tryParse(savedMode) ?? 0;
    themeModeNotifier.value = ThemeMode.values[index];
  }
}

class MissIDEApp extends StatelessWidget {
  const MissIDEApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, mode, child) {
        return MaterialApp(
          title: 'Miss IDE v2',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: mode,
          home: const MainPage(),
        );
      },
    );
  }
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => MainPageState();
}

class MainPageState extends State<MainPage> {
  int _currentIndex = 0;
  String? _currentProjectPath;
  String? _currentProjectName;
  bool _showProjectDetail = false;
  String? _currentFilePath; // 当前选中的文件路径

  void _onProjectSelected(String path, String name) {
    setState(() {
      _currentProjectPath = path;
      _currentProjectName = name;
      _showProjectDetail = true; // 显示项目详情页面
      _currentIndex = 1; // 切换到编辑器页面
    });
  }

  /// 关闭项目详情，返回项目列表
  void _closeProjectDetail() {
    setState(() {
      _showProjectDetail = false;
      _currentIndex = 0; // 返回项目列表
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          // 项目列表页面
          FileBrowserPage(onProjectSelected: _onProjectSelected),
          // 项目详情页面（文件/进程/历史）
          if (_showProjectDetail && _currentProjectPath != null)
            ProjectPage(
              projectPath: _currentProjectPath!,
              onFileSelected: (filePath) {
                // 打开文件并切换到编辑器
                setState(() {
                  _showProjectDetail = false;
                  _currentFilePath = filePath;
                  _currentIndex = 1; // 切换到编辑器页面
                });
              },
              onClose: _closeProjectDetail,
            )
          else if (_currentProjectPath != null)
            CodeEditorPage(
              projectPath: _currentProjectPath,
              filePath: _currentFilePath,
            )
          else
            const CodeEditorPage(),
          // 其他页面保持不变
          const BuildPage(),
          AIChatPage(projectPath: _currentProjectPath),
          const SettingsPage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
            // 如果切换到编辑页面且有项目，显示项目详情
            if (index == 1 && _currentProjectPath != null) {
              _showProjectDetail = true;
            }
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder),
            label: '项目',
          ),
          NavigationDestination(
            icon: Icon(Icons.code_outlined),
            selectedIcon: Icon(Icons.code),
            label: '编辑',
          ),
          NavigationDestination(
            icon: Icon(Icons.build_outlined),
            selectedIcon: Icon(Icons.build),
            label: '构建',
          ),
          NavigationDestination(
            icon: Icon(Icons.smart_toy_outlined),
            selectedIcon: Icon(Icons.smart_toy),
            label: 'AI',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '设置',
          ),
        ],
      ),
    );
  }
}
