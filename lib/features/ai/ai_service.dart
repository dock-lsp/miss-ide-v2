import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;

/// AI消息
class AIMessage {
  final String role;
  final String content;
  AIMessage({required this.role, required this.content});
  
  Map<String, dynamic> toJson() => {'role': role, 'content': content};
}

/// AI模型配置
class AIModelConfig {
  final String name;
  final String provider;
  final String apiEndpoint;
  final String modelId;
  
  AIModelConfig({
    required this.name,
    required this.provider,
    required this.apiEndpoint,
    required this.modelId,
  });
}

/// 项目结构模板
class ProjectTemplate {
  final String name;
  final String description;
  final Map<String, String> files; // path -> content
  
  ProjectTemplate({
    required this.name,
    required this.description,
    required this.files,
  });
}

/// AI意图识别结果
class AIIntent {
  final AIIntentType type;
  final Map<String, dynamic> params;
  
  AIIntent({required this.type, required this.params});
}

enum AIIntentType {
  createProject,
  generateCode,
  explainCode,
  chat,
  unknown,
}

/// AI服务 - 支持多模型
class AIService {
  static final AIService _instance = AIService._internal();
  factory AIService() => _instance;
  AIService._internal();

  String _selectedModel = 'DeepSeek';
  String _apiKey = '';
  bool _isInitialized = false;
  
  // AI回调函数
  Function(String)? onProjectCreated;
  Function(String, String)? onCodeGenerated;

  final Map<String, AIModelConfig> _models = {
    'DeepSeek': AIModelConfig(
      name: 'DeepSeek',
      provider: 'deepseek',
      apiEndpoint: 'https://api.deepseek.com/chat/completions',
      modelId: 'deepseek-chat',
    ),
    '通义千问': AIModelConfig(
      name: '通义千问',
      provider: 'qwen',
      apiEndpoint: 'https://dashscope.aliyuncs.com/api/v1/services/aigc/text-generation/generation',
      modelId: 'qwen-turbo',
    ),
    '豆包': AIModelConfig(
      name: '豆包',
      provider: 'doubao',
      apiEndpoint: 'https://ark.cn-beijing.volces.com/api/v3/chat/completions',
      modelId: 'doubao-pro-32k',
    ),
    'Minimax': AIModelConfig(
      name: 'Minimax',
      provider: 'minimax',
      apiEndpoint: 'https://api.minimax.chat/v1/chat/completions_v2',
      modelId: 'abab6.5-chat',
    ),
    '智谱清言': AIModelConfig(
      name: '智谱清言',
      provider: 'zhipu',
      apiEndpoint: 'https://open.bigmodel.cn/api/paas/v4/chat/completions',
      modelId: 'glm-4',
    ),
    'Gemini': AIModelConfig(
      name: 'Gemini',
      provider: 'google',
      apiEndpoint: 'https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent',
      modelId: 'gemini-pro',
    ),
    'GPT-4': AIModelConfig(
      name: 'GPT-4',
      provider: 'openai',
      apiEndpoint: 'https://api.openai.com/v1/chat/completions',
      modelId: 'gpt-4-turbo-preview',
    ),
    'Claude': AIModelConfig(
      name: 'Claude',
      provider: 'anthropic',
      apiEndpoint: 'https://api.anthropic.com/v1/messages',
      modelId: 'claude-3-sonnet-20240229',
    ),
    'Ollama': AIModelConfig(
      name: 'Ollama',
      provider: 'ollama',
      apiEndpoint: 'http://localhost:11434/api/chat',
      modelId: 'llama2',
    ),
    'MiMo': AIModelConfig(
      name: 'MiMo',
      provider: 'mimo',
      apiEndpoint: 'https://api.milooka.com/v1/chat/completions',
      modelId: 'mimo-v2-pro',
    ),
  };

  /// 项目模板库
  final Map<String, ProjectTemplate> _projectTemplates = {
    'flutter': ProjectTemplate(
      name: 'Flutter App',
      description: '创建一个基本的Flutter应用',
      files: {
        'lib/main.dart': '''import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'My App',
      home: Scaffold(
        appBar: AppBar(title: const Text('Home')),
        body: const Center(child: Text('Hello Flutter!')),
      ),
    );
  }
}
''',
        'pubspec.yaml': '''name: my_app
description: A new Flutter project.
version: 1.0.0+1

environment:
  sdk: '>=3.0.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter

flutter:
  uses-material-design: true
''',
      },
    ),
    'python': ProjectTemplate(
      name: 'Python Project',
      description: '创建一个Python项目',
      files: {
        'main.py': '''#!/usr/bin/env python3
"""
Main application file
"""

def main():
    print("Hello, Python!")

if __name__ == '__main__':
    main()
''',
        'requirements.txt': '',
        'README.md': '# Python Project\n',
      },
    ),
    'nodejs': ProjectTemplate(
      name: 'Node.js Project',
      description: '创建一个Node.js项目',
      files: {
        'index.js': '''/**
 * Main application file
 */

function main() {
  console.log("Hello, Node.js!");
}

main();
''',
        'package.json': '''{
  "name": "my-app",
  "version": "1.0.0",
  "main": "index.js",
  "scripts": {
    "start": "node index.js"
  }
}
''',
      },
    ),
  };

  /// 初始化
  Future<void> init() async {
    if (_isInitialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _selectedModel = prefs.getString('ai_selected_model') ?? 'DeepSeek';
      _apiKey = prefs.getString('ai_api_key_$_selectedModel') ?? '';
    } catch (e) {
      debugPrint('AI Service init error: $e');
    }
    _isInitialized = true;
  }

  /// 获取当前选择的模型
  String get selectedModel => _selectedModel;

  /// 获取当前API Key
  String get apiKey => _apiKey;
  
  /// 检查是否已配置
  bool get isConfigured => _apiKey.isNotEmpty;

  /// 获取所有模型名称
  List<String> get modelNames => _models.keys.toList();

  /// 获取所有项目模板名称
  List<String> get templateNames => _projectTemplates.keys.toList();

  /// 切换模型
  Future<void> setModel(String modelName) async {
    if (!_models.containsKey(modelName)) return;
    _selectedModel = modelName;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('ai_selected_model', modelName);
      _apiKey = prefs.getString('ai_api_key_$modelName') ?? '';
    } catch (e) {
      debugPrint('Set model error: $e');
    }
  }

  /// 保存API Key
  Future<bool> saveApiKey(String apiKey) async {
    try {
      _apiKey = apiKey.trim();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('ai_api_key_$_selectedModel', apiKey.trim());
      debugPrint('API Key saved for $_selectedModel');
      return true;
    } catch (e) {
      debugPrint('Failed to save API Key: $e');
      return false;
    }
  }

  /// 识别用户意图
  AIIntent recognizeIntent(String message) {
    final lowerMessage = message.toLowerCase();
    
    // 创建项目意图
    if (lowerMessage.contains('创建') && 
        (lowerMessage.contains('项目') || lowerMessage.contains('工程'))) {
      String template = 'flutter';
      if (lowerMessage.contains('python')) template = 'python';
      if (lowerMessage.contains('node') || lowerMessage.contains('nodejs')) template = 'nodejs';
      
      // 尝试提取项目名称
      String projectName = 'my_project';
      final nameMatch = RegExp(r'(?:叫|名称|名字为?|名为)([^，,。\s]+)').firstMatch(message);
      if (nameMatch != null) {
        projectName = nameMatch.group(1) ?? 'my_project';
      }
      
      return AIIntent(
        type: AIIntentType.createProject,
        params: {'template': template, 'name': projectName},
      );
    }
    
    // 生成代码意图
    if (lowerMessage.contains('生成') && 
        (lowerMessage.contains('代码') || lowerMessage.contains('写'))) {
      String language = 'dart';
      if (lowerMessage.contains('python') || lowerMessage.contains('.py')) language = 'python';
      if (lowerMessage.contains('java')) language = 'java';
      if (lowerMessage.contains('javascript') || lowerMessage.contains('.js')) language = 'javascript';
      if (lowerMessage.contains('go') || lowerMessage.contains('.go')) language = 'go';
      
      return AIIntent(
        type: AIIntentType.generateCode,
        params: {'language': language, 'description': message},
      );
    }
    
    // 解释代码意图
    if (lowerMessage.contains('解释') || 
        lowerMessage.contains('说明') ||
        lowerMessage.contains('看懂')) {
      if (lowerMessage.contains('代码')) {
        return AIIntent(
          type: AIIntentType.explainCode,
          params: {},
        );
      }
    }
    
    return AIIntent(type: AIIntentType.chat, params: {});
  }

  /// 创建项目
  Future<String> createProject(String projectPath, String templateName) async {
    final template = _projectTemplates[templateName];
    if (template == null) {
      return '未找到模板: $templateName';
    }
    
    try {
      // 创建项目目录
      final dir = Directory(projectPath);
      if (await dir.exists()) {
        return '目录已存在: $projectPath';
      }
      
      await dir.create(recursive: true);
      
      // 创建所有文件
      for (final entry in template.files.entries) {
        final filePath = p.join(projectPath, entry.key);
        final file = File(filePath);
        await file.parent.create(recursive: true);
        await file.writeAsString(entry.value);
      }
      
      // 回调通知
      onProjectCreated?.call(projectPath);
      
      return '项目已创建: $projectPath\n\n模板: ${template.name}\n文件数: ${template.files.length}';
    } catch (e) {
      return '创建失败: $e';
    }
  }

  /// 使用AI生成项目
  Future<String> generateProjectWithAI(String projectPath, String description) async {
    if (!isConfigured) {
      return '请先配置AI API Key';
    }
    
    try {
      // 向AI询问项目结构
      final prompt = '''请为以下项目生成代码结构：
      
描述: $description

请生成一个完整的项目结构，包括所有必要的文件。
回复格式要求：
1. 首先说明项目类型和建议的文件结构
2. 然后列出每个文件的完整内容
3. 使用以下标记格式：

【文件: 文件路径】
文件内容...
【文件结束】

请确保代码可以直接使用。''';
      
      final response = await chat(prompt);
      
      // 解析AI响应并创建文件
      final filePattern = RegExp(r'【文件:\s*(.+?)】(.*?)【文件结束】', dotAll: true);
      final matches = filePattern.allMatches(response);
      
      if (matches.isEmpty) {
        // 没有找到文件格式，返回原始响应
        return response;
      }
      
      // 创建项目目录
      final dir = Directory(projectPath);
      await dir.create(recursive: true);
      
      // 创建每个文件
      for (final match in matches) {
        final filePath = match.group(1)?.trim() ?? '';
        final content = match.group(2)?.trim() ?? '';
        
        if (filePath.isNotEmpty && content.isNotEmpty) {
          final fullPath = p.join(projectPath, filePath);
          final file = File(fullPath);
          await file.parent.create(recursive: true);
          await file.writeAsString(content);
        }
      }
      
      // 回调通知
      onProjectCreated?.call(projectPath);
      
      return '项目已创建: $projectPath\n\n共生成 ${matches.length} 个文件';
    } catch (e) {
      return '生成失败: $e';
    }
  }

  /// 从AI响应中解析并创建多个文件
  /// 返回创建的文件路径列表
  Future<List<String>> parseAndCreateFiles(String response, String basePath) async {
    final createdFiles = <String>[];
    
    // 匹配【文件: 路径】...【文件结束】格式
    final pattern1 = RegExp(r'【文件:\s*(.+?)】(.*?)【文件结束】', dotAll: true);
    final matches1 = pattern1.allMatches(response);
    
    // 匹配 ```语言\n文件路径\n代码\n``` 格式
    final pattern2 = RegExp(r'```[\w]*\s*([^\n]+)\n([\s\S]*?)```', multiLine: true);
    final matches2 = pattern2.allMatches(response);
    
    // 处理【文件: 路径】格式
    for (final match in matches1) {
      final filePath = match.group(1)?.trim() ?? '';
      final content = match.group(2)?.trim() ?? '';
      
      if (filePath.isNotEmpty && content.isNotEmpty) {
        final success = await _createFile(basePath, filePath, content);
        if (success) {
          createdFiles.add(p.join(basePath, filePath));
        }
      }
    }
    
    // 处理 ```路径\n代码``` 格式
    for (final match in matches2) {
      final filePath = match.group(1)?.trim() ?? '';
      final content = match.group(2)?.trim() ?? '';
      
      // 跳过文件名注释等非文件路径
      if (filePath.contains('.') && !filePath.contains('：') && content.isNotEmpty) {
        final success = await _createFile(basePath, filePath, content);
        if (success) {
          createdFiles.add(p.join(basePath, filePath));
        }
      }
    }
    
    return createdFiles;
  }

  /// 创建单个文件
  Future<bool> _createFile(String basePath, String filePath, String content) async {
    try {
      // 清理文件路径（移除可能的注释前缀）
      String cleanPath = filePath;
      if (cleanPath.contains('：')) {
        cleanPath = cleanPath.split('：').last.trim();
      }
      cleanPath = cleanPath.trim();
      
      if (cleanPath.isEmpty) return false;
      
      final fullPath = p.join(basePath, cleanPath);
      final file = File(fullPath);
      await file.parent.create(recursive: true);
      await file.writeAsString(content);
      debugPrint('Created file: $fullPath');
      return true;
    } catch (e) {
      debugPrint('Failed to create file: $filePath, error: $e');
      return false;
    }
  }

  /// 使用AI生成代码
  Future<String> generateCode(String language, String description) async {
    if (!isConfigured) {
      return '请先配置AI API Key';
    }
    
    try {
      final prompt = '''请生成一段 $language 代码：

需求: $description

请生成完整可用的代码，并简要说明使用方法。''';
      
      final response = await chat(prompt);
      
      // 如果AI生成了代码，触发回调
      if (response.contains('```')) {
        onCodeGenerated?.call(language, response);
      }
      
      return response;
    } catch (e) {
      return '生成失败: $e';
    }
  }

  /// 解释代码
  Future<String> explainCode(String code) async {
    if (!isConfigured) {
      return '请先配置AI API Key';
    }
    
    try {
      final prompt = '''请解释以下代码的功能和工作原理：

\`\`\`
$code
\`\`\`

请用简洁易懂的语言解释，包括：
1. 代码的主要功能
2. 关键代码段的作用
3. 代码的运行流程''';
      
      return await chat(prompt);
    } catch (e) {
      return '解释失败: $e';
    }
  }

  /// 发送消息并获取AI响应
  Future<String> chat(String userMessage, {List<AIMessage>? history}) async {
    final config = _models[_selectedModel];
    if (config == null) {
      return '错误：未知的模型配置';
    }

    if (_apiKey.isEmpty && config.provider != 'ollama') {
      return '请先在设置中配置 ${config.name} 的 API Key。\n\n获取地址：${_getKeyUrl(config.name)}';
    }

    try {
      debugPrint('Sending request to ${config.name}...');
      String response;
      
      switch (config.provider) {
        case 'deepseek':
          response = await _chatDeepSeek(config, userMessage, history);
          break;
        case 'qwen':
          response = await _chatQwen(config, userMessage, history);
          break;
        case 'zhipu':
          response = await _chatZhipu(config, userMessage, history);
          break;
        case 'gemini':
          response = await _chatGemini(config, userMessage, history);
          break;
        case 'claude':
          response = await _chatClaude(config, userMessage, history);
          break;
        case 'ollama':
          response = await _chatOllama(config, userMessage, history);
          break;
        case 'openai':
          response = await _chatOpenAI(config, userMessage, history);
          break;
        case 'mimo':
          response = await _chatMiMo(config, userMessage, history);
          break;
        default:
          response = await _chatDeepSeek(config, userMessage, history);
      }
      
      debugPrint('Response received');
      return response;
    } catch (e) {
      debugPrint('Chat error: $e');
      return '请求失败: $e\n\n请检查API Key是否正确';
    }
  }

  String _getKeyUrl(String modelName) {
    const urls = {
      'DeepSeek': 'platform.deepseek.com',
      '通义千问': 'dashscope.aliyuncs.com',
      '豆包': 'console.volcengine.com/ark',
      'Minimax': 'api.minimax.chat',
      '智谱清言': 'open.bigmodel.cn',
      'Gemini': 'makersuite.google.com',
      'GPT-4': 'platform.openai.com',
      'Claude': 'console.anthropic.com',
      'MiMo': 'mimo.xiaomi.com',
    };
    return urls[modelName] ?? '';
  }

  /// DeepSeek API
  Future<String> _chatDeepSeek(
    AIModelConfig config,
    String userMessage,
    List<AIMessage>? history,
  ) async {
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': '你是一个专业的编程助手，帮助用户解决代码问题。请用中文回答。'},
      if (history != null) ...history.map((m) => m.toJson()),
      {'role': 'user', 'content': userMessage},
    ];

    final response = await http.post(
      Uri.parse(config.apiEndpoint),
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'Authorization': 'Bearer $_apiKey',
      },
      body: utf8.encode(jsonEncode({
        'model': config.modelId,
        'messages': messages,
        'temperature': 0.7,
        'max_tokens': 4096,
      })),
    );

    debugPrint('DeepSeek response status: ${response.statusCode}');
    
    if (response.statusCode == 200) {
      final body = utf8.decode(response.bodyBytes);
      final data = jsonDecode(body);
      return data['choices'][0]['message']['content'] ?? '无响应内容';
    } else {
      final body = utf8.decode(response.bodyBytes);
      return 'API错误 (${response.statusCode}): $body';
    }
  }

  /// OpenAI API
  Future<String> _chatOpenAI(
    AIModelConfig config,
    String userMessage,
    List<AIMessage>? history,
  ) async {
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': '你是一个专业的编程助手。'},
      if (history != null) ...history.map((m) => m.toJson()),
      {'role': 'user', 'content': userMessage},
    ];

    final response = await http.post(
      Uri.parse(config.apiEndpoint),
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'Authorization': 'Bearer $_apiKey',
      },
      body: utf8.encode(jsonEncode({
        'model': config.modelId,
        'messages': messages,
        'temperature': 0.7,
        'max_tokens': 4096,
      })),
    );

    if (response.statusCode == 200) {
      final body = utf8.decode(response.bodyBytes);
      final data = jsonDecode(body);
      return data['choices'][0]['message']['content'] ?? '无响应内容';
    } else {
      final body = utf8.decode(response.bodyBytes);
      return 'API错误 (${response.statusCode}): $body';
    }
  }

  /// 通义千问API
  Future<String> _chatQwen(
    AIModelConfig config,
    String userMessage,
    List<AIMessage>? history,
  ) async {
    final response = await http.post(
      Uri.parse(config.apiEndpoint),
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'Authorization': 'Bearer $_apiKey',
      },
      body: utf8.encode(jsonEncode({
        'model': config.modelId,
        'input': {
          'messages': [
            {'role': 'system', 'content': '你是一个专业的编程助手。'},
            {'role': 'user', 'content': userMessage},
          ],
        },
      })),
    );

    if (response.statusCode == 200) {
      final body = utf8.decode(response.bodyBytes);
      final data = jsonDecode(body);
      if (data['output'] != null) {
        return data['output']['text'] ?? 
               data['output']['choices']?[0]?['message']?['content'] ?? 
               '无响应';
      }
      return '响应格式错误: $body';
    } else {
      final body = utf8.decode(response.bodyBytes);
      return 'API错误 (${response.statusCode}): $body';
    }
  }

  /// 智谱清言API
  Future<String> _chatZhipu(
    AIModelConfig config,
    String userMessage,
    List<AIMessage>? history,
  ) async {
    final response = await http.post(
      Uri.parse(config.apiEndpoint),
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'Authorization': 'Bearer $_apiKey',
      },
      body: utf8.encode(jsonEncode({
        'model': config.modelId,
        'messages': [
          {'role': 'user', 'content': userMessage},
        ],
      })),
    );

    if (response.statusCode == 200) {
      final body = utf8.decode(response.bodyBytes);
      final data = jsonDecode(body);
      return data['choices'][0]['message']['content'] ?? '无响应';
    } else {
      final body = utf8.decode(response.bodyBytes);
      return 'API错误 (${response.statusCode}): $body';
    }
  }

  /// Gemini API
  Future<String> _chatGemini(
    AIModelConfig config,
    String userMessage,
    List<AIMessage>? history,
  ) async {
    final url = '${config.apiEndpoint}?key=$_apiKey';
    
    final response = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
      body: utf8.encode(jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': userMessage}
            ]
          }
        ]
      })),
    );

    if (response.statusCode == 200) {
      final body = utf8.decode(response.bodyBytes);
      final data = jsonDecode(body);
      return data['candidates'][0]['content']['parts'][0]['text'] ?? '无响应';
    } else {
      final body = utf8.decode(response.bodyBytes);
      return 'API错误 (${response.statusCode}): $body';
    }
  }

  /// Claude API
  Future<String> _chatClaude(
    AIModelConfig config,
    String userMessage,
    List<AIMessage>? history,
  ) async {
    final response = await http.post(
      Uri.parse(config.apiEndpoint),
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'x-api-key': _apiKey,
        'anthropic-version': '2023-06-01',
      },
      body: utf8.encode(jsonEncode({
        'model': config.modelId,
        'max_tokens': 4096,
        'messages': [
          {'role': 'user', 'content': userMessage}
        ],
      })),
    );

    if (response.statusCode == 200) {
      final body = utf8.decode(response.bodyBytes);
      final data = jsonDecode(body);
      return data['content'][0]['text'] ?? '无响应';
    } else {
      final body = utf8.decode(response.bodyBytes);
      return 'API错误 (${response.statusCode}): $body';
    }
  }

  /// Ollama本地API
  Future<String> _chatOllama(
    AIModelConfig config,
    String userMessage,
    List<AIMessage>? history,
  ) async {
    final response = await http.post(
      Uri.parse(config.apiEndpoint),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
      body: utf8.encode(jsonEncode({
        'model': config.modelId,
        'messages': [
          {'role': 'user', 'content': userMessage}
        ],
        'stream': false,
      })),
    );

    if (response.statusCode == 200) {
      final body = utf8.decode(response.bodyBytes);
      final data = jsonDecode(body);
      return data['message']['content'] ?? '无响应';
    } else {
      return 'Ollama连接失败，请确保Ollama服务正在运行 (localhost:11434)';
    }
  }

  /// 小米MiMo API
  Future<String> _chatMiMo(
    AIModelConfig config,
    String userMessage,
    List<AIMessage>? history,
  ) async {
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': '你是一个专业的编程助手，帮助用户解决代码问题。请用中文回答。'},
      if (history != null) ...history.map((m) => m.toJson()),
      {'role': 'user', 'content': userMessage},
    ];

    final response = await http.post(
      Uri.parse(config.apiEndpoint),
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'Authorization': 'Bearer $_apiKey',
      },
      body: utf8.encode(jsonEncode({
        'model': config.modelId,
        'messages': messages,
        'temperature': 0.7,
        'max_tokens': 4096,
      })),
    );

    debugPrint('MiMo response status: ${response.statusCode}');

    if (response.statusCode == 200) {
      final body = utf8.decode(response.bodyBytes);
      final data = jsonDecode(body);
      return data['choices'][0]['message']['content'] ?? '无响应内容';
    } else {
      final body = utf8.decode(response.bodyBytes);
      return 'API错误 (${response.statusCode}): $body';
    }
  }
}

// 全局实例
final aiService = AIService();
