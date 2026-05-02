import 'package:flutter/material.dart';

/// VS Code Dark+ 风格语法高亮工具类
/// 不使用第三方包，自己实现基础语法高亮
class SyntaxHighlighter {
  // 参考极影桌面IDE的语法高亮颜色（VS Code Dark+ 风格）
  // 关键字：蓝色
  static const Color keywordColor = Color(0xFF569CD6);
  // 函数名：橙色
  static const Color functionColor = Color(0xFFCE9178);
  // 常量和类名：紫色
  static const Color constantColor = Color(0xFFB5CEA8);
  static const Color typeColor = Color(0xFF4EC9B0);
  // 字符串：绿色
  static const Color stringColor = Color(0xFF6A9955);
  // 注释：灰色
  static const Color commentColor = Color(0xFF6A9955);
  // 数字：浅绿色
  static const Color numberColor = Color(0xFFB5CEA8);
  // 注解：金色
  static const Color annotationColor = Color(0xFFD7BA7D);
  // 操作符：白色
  static const Color operatorColor = Color(0xFFD4D4D4);
  // 变量：浅蓝色
  static const Color variableColor = Color(0xFF9CDCFE);
  
  // Dart 关键词
  static const Set<String> dartKeywords = {
    'abstract', 'as', 'assert', 'async', 'await', 'base', 'break', 'case',
    'catch', 'class', 'const', 'continue', 'covariant', 'default', 'deferred',
    'do', 'dynamic', 'else', 'enum', 'export', 'extends', 'extension',
    'external', 'factory', 'false', 'final', 'finally', 'for', 'Function',
    'get', 'hide', 'if', 'implements', 'import', 'in', 'interface', 'is',
    'late', 'library', 'mixin', 'new', 'null', 'on', 'operator', 'part',
    'required', 'rethrow', 'return', 'sealed', 'set', 'show', 'static',
    'super', 'switch', 'sync', 'this', 'throw', 'true', 'try', 'typedef',
    'var', 'void', 'when', 'while', 'with', 'yield',
  };
  
  // Java 关键词
  static const Set<String> javaKeywords = {
    'abstract', 'assert', 'boolean', 'break', 'byte', 'case', 'catch', 'char',
    'class', 'const', 'continue', 'default', 'do', 'double', 'else', 'enum',
    'extends', 'final', 'finally', 'float', 'for', 'goto', 'if', 'implements',
    'import', 'instanceof', 'int', 'interface', 'long', 'native', 'new', 'null',
    'package', 'private', 'protected', 'public', 'return', 'short', 'static',
    'strictfp', 'super', 'switch', 'synchronized', 'this', 'throw', 'throws',
    'transient', 'try', 'void', 'volatile', 'while', 'true', 'false',
  };
  
  // Python 关键词
  static const Set<String> pythonKeywords = {
    'False', 'None', 'True', 'and', 'as', 'assert', 'async', 'await', 'break',
    'class', 'continue', 'def', 'del', 'elif', 'else', 'except', 'finally',
    'for', 'from', 'global', 'if', 'import', 'in', 'is', 'lambda', 'nonlocal',
    'not', 'or', 'pass', 'raise', 'return', 'try', 'while', 'with', 'yield',
  };
  
  // JavaScript/TypeScript 关键词
  static const Set<String> jsKeywords = {
    'async', 'await', 'break', 'case', 'catch', 'class', 'const', 'continue',
    'debugger', 'default', 'delete', 'do', 'else', 'export', 'extends', 'false',
    'finally', 'for', 'function', 'if', 'import', 'in', 'instanceof', 'let',
    'new', 'null', 'return', 'static', 'super', 'switch', 'this', 'throw',
    'true', 'try', 'typeof', 'undefined', 'var', 'void', 'while', 'with', 'yield',
    'of', 'get', 'set',
  };
  
  // Kotlin 关键词
  static const Set<String> kotlinKeywords = {
    'abstract', 'actual', 'annotation', 'as', 'break', 'by', 'catch', 'class',
    'companion', 'const', 'constructor', 'continue', 'crossinline', 'data',
    'delegate', 'do', 'dynamic', 'else', 'enum', 'expect', 'external', 'false',
    'final', 'finally', 'for', 'fun', 'get', 'if', 'import', 'in', 'infix',
    'init', 'inline', 'inner', 'interface', 'internal', 'is', 'lateinit', 'noinline',
    'null', 'object', 'open', 'operator', 'out', 'override', 'package', 'private',
    'protected', 'public', 'reified', 'return', 'sealed', 'set', 'super', 'suspend',
    'tailrec', 'this', 'throw', 'true', 'try', 'typealias', 'typeof', 'val', 'var',
    'vararg', 'when', 'where', 'while',
  };
  
  // Go 关键词
  static const Set<String> goKeywords = {
    'break', 'case', 'chan', 'const', 'continue', 'default', 'defer', 'else',
    'fallthrough', 'for', 'func', 'go', 'goto', 'if', 'import', 'interface',
    'map', 'package', 'range', 'return', 'select', 'struct', 'switch', 'type',
    'var', 'true', 'false', 'nil', 'iota',
  };
  
  // Rust 关键词
  static const Set<String> rustKeywords = {
    'as', 'async', 'await', 'break', 'const', 'continue', 'crate', 'dyn', 'else',
    'enum', 'extern', 'false', 'fn', 'for', 'if', 'impl', 'in', 'let', 'loop',
    'match', 'mod', 'move', 'mut', 'pub', 'ref', 'return', 'self', 'Self', 'static',
    'struct', 'super', 'trait', 'true', 'type', 'unsafe', 'use', 'where', 'while',
  };
  
  // C/C++ 关键词
  static const Set<String> cKeywords = {
    'auto', 'break', 'case', 'char', 'const', 'continue', 'default', 'do', 'double',
    'else', 'enum', 'extern', 'float', 'for', 'goto', 'if', 'inline', 'int', 'long',
    'register', 'restrict', 'return', 'short', 'signed', 'sizeof', 'static', 'struct',
    'switch', 'typedef', 'union', 'unsigned', 'void', 'volatile', 'while', 'NULL',
    'true', 'false', 'class', 'public', 'private', 'protected', 'virtual', 'template',
    'namespace', 'using', 'new', 'delete', 'this', 'throw', 'try', 'catch',
  };
  
  /// 根据语言类型获取关键词集合
  static Set<String> getKeywords(String language) {
    switch (language.toLowerCase()) {
      case 'dart':
        return dartKeywords;
      case 'java':
        return javaKeywords;
      case 'python':
        return pythonKeywords;
      case 'javascript':
      case 'typescript':
      case 'js':
      case 'ts':
        return jsKeywords;
      case 'kotlin':
      case 'kt':
        return kotlinKeywords;
      case 'go':
        return goKeywords;
      case 'rust':
      case 'rs':
        return rustKeywords;
      case 'c':
      case 'c++':
      case 'cpp':
        return cKeywords;
      default:
        return dartKeywords;
    }
  }
  
  /// 对代码文本进行语法高亮
  static List<TextSpan> highlight(String code, String language, {
    Color defaultColor = Colors.white,
    double fontSize = 14,
  }) {
    final keywords = getKeywords(language);
    final spans = <TextSpan>[];
    
    // 正则表达式 - 简化模式
    final stringRegex = RegExp(r'"[^"]*"|' + r"'[^']*'");
    final singleLineCommentRegex = RegExp(r'//.*$', multiLine: true);
    final multiLineCommentRegex = RegExp(r'/\*[\s\S]*?\*/');
    final numberRegex = RegExp(r'\b\d+\.?\d*\b');
    final wordRegex = RegExp(r'\b\w+\b');
    final annotationRegex = RegExp(r'@\w+');
    
    // 收集所有需要高亮的区域
    final regions = <_HighlightRegion>[];
    
    // 匹配字符串
    for (final match in stringRegex.allMatches(code)) {
      regions.add(_HighlightRegion(
        start: match.start,
        end: match.end,
        color: stringColor,
        type: 'string',
      ));
    }
    
    // 匹配单行注释
    for (final match in singleLineCommentRegex.allMatches(code)) {
      // 排除字符串内的注释标记
      bool inString = regions.any((r) => 
        r.type == 'string' && match.start >= r.start && match.start < r.end
      );
      if (!inString) {
        regions.add(_HighlightRegion(
          start: match.start,
          end: match.end,
          color: commentColor,
          type: 'comment',
        ));
      }
    }
    
    // 匹配多行注释
    for (final match in multiLineCommentRegex.allMatches(code)) {
      regions.add(_HighlightRegion(
        start: match.start,
        end: match.end,
        color: commentColor,
        type: 'comment',
      ));
    }
    
    // 匹配注解 (主要用于 Java/Kotlin/Dart)
    for (final match in annotationRegex.allMatches(code)) {
      bool inCommentOrString = regions.any((r) =>
        (r.type == 'comment' || r.type == 'string') &&
        match.start >= r.start && match.end <= r.end
      );
      if (!inCommentOrString) {
        regions.add(_HighlightRegion(
          start: match.start,
          end: match.end,
          color: annotationColor,
          type: 'annotation',
        ));
      }
    }
    
    // 匹配数字
    for (final match in numberRegex.allMatches(code)) {
      bool inCommentOrString = regions.any((r) =>
        (r.type == 'comment' || r.type == 'string') &&
        match.start >= r.start && match.end <= r.end
      );
      if (!inCommentOrString) {
        regions.add(_HighlightRegion(
          start: match.start,
          end: match.end,
          color: numberColor,
          type: 'number',
        ));
      }
    }
    
    // 匹配关键词和标识符
    for (final match in wordRegex.allMatches(code)) {
      bool inCommentOrString = regions.any((r) =>
        (r.type == 'comment' || r.type == 'string') &&
        match.start >= r.start && match.end <= r.end
      );
      if (!inCommentOrString) {
        final word = match.group(0)!;
        
        // 检查是否是关键词
        if (keywords.contains(word)) {
          regions.add(_HighlightRegion(
            start: match.start,
            end: match.end,
            color: keywordColor,
            type: 'keyword',
          ));
        }
        // 检查是否是函数调用（后面跟着括号）
        else if (_isFunctionCall(code, match.end)) {
          regions.add(_HighlightRegion(
            start: match.start,
            end: match.end,
            color: functionColor,
            type: 'function',
          ));
        }
        // 检查是否是大写开头的类型
        else if (word.isNotEmpty && word[0] == word[0].toUpperCase() && word.contains(RegExp(r'[a-z]'))) {
          regions.add(_HighlightRegion(
            start: match.start,
            end: match.end,
            color: typeColor,
            type: 'type',
          ));
        }
      }
    }
    
    // 按起始位置排序
    regions.sort((a, b) => a.start.compareTo(b.start));
    
    // 去除重叠区域（保留高优先级）
    final priorityMap = {'keyword': 5, 'type': 4, 'function': 3, 'number': 2, 'string': 2, 'comment': 1, 'annotation': 3};
    final filteredRegions = _removeOverlapping(regions, priorityMap);
    
    // 构建 TextSpan 列表
    int currentPos = 0;
    for (final region in filteredRegions) {
      // 添加未高亮的文本
      if (region.start > currentPos) {
        spans.add(TextSpan(
          text: code.substring(currentPos, region.start),
          style: TextStyle(color: defaultColor, fontSize: fontSize),
        ));
      }
      // 添加高亮文本
      spans.add(TextSpan(
        text: code.substring(region.start, region.end),
        style: TextStyle(color: region.color, fontSize: fontSize),
      ));
      currentPos = region.end;
    }
    
    // 添加剩余文本
    if (currentPos < code.length) {
      spans.add(TextSpan(
        text: code.substring(currentPos),
        style: TextStyle(color: defaultColor, fontSize: fontSize),
      ));
    }
    
    return spans.isEmpty 
        ? [TextSpan(text: code, style: TextStyle(color: defaultColor, fontSize: fontSize))]
        : spans;
  }
  
  /// 检查是否是函数调用
  static bool _isFunctionCall(String code, int position) {
    if (position >= code.length) return false;
    
    // 跳过空白字符
    int pos = position;
    while (pos < code.length && (code[pos] == ' ' || code[pos] == '\t')) {
      pos++;
    }
    
    // 检查是否有左括号
    return pos < code.length && code[pos] == '(';
  }
  
  /// 去除重叠区域，保留高优先级
  static List<_HighlightRegion> _removeOverlapping(
    List<_HighlightRegion> regions,
    Map<String, int> priorityMap,
  ) {
    final result = <_HighlightRegion>[];
    
    for (final region in regions) {
      bool overlaps = false;
      for (final existing in result) {
        if (region.start < existing.end && region.end > existing.start) {
          // 区域重叠
          final regionPriority = priorityMap[region.type] ?? 0;
          final existingPriority = priorityMap[existing.type] ?? 0;
          
          if (regionPriority > existingPriority) {
            // 用新的替换旧的
            result.remove(existing);
            break;
          } else {
            overlaps = true;
            break;
          }
        }
      }
      
      if (!overlaps) {
        result.add(region);
      }
    }
    
    return result;
  }
  
  /// 获取语言对应的文件扩展名
  static String getLanguageFromExtension(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'dart':
        return 'Dart';
      case 'java':
        return 'Java';
      case 'kt':
        return 'Kotlin';
      case 'py':
        return 'Python';
      case 'js':
        return 'JavaScript';
      case 'ts':
        return 'TypeScript';
      case 'html':
        return 'HTML';
      case 'css':
        return 'CSS';
      case 'json':
        return 'JSON';
      case 'yaml':
      case 'yml':
        return 'YAML';
      case 'md':
        return 'Markdown';
      case 'xml':
        return 'XML';
      case 'sql':
        return 'SQL';
      case 'sh':
        return 'Shell';
      case 'c':
        return 'C';
      case 'cpp':
      case 'cxx':
      case 'cc':
        return 'C++';
      case 'go':
        return 'Go';
      case 'rs':
        return 'Rust';
      case 'php':
        return 'PHP';
      case 'rb':
        return 'Ruby';
      case 'swift':
        return 'Swift';
      case 'txt':
        return 'Text';
      default:
        return 'Text';
    }
  }
}

/// 高亮区域
class _HighlightRegion {
  final int start;
  final int end;
  final Color color;
  final String type;
  
  _HighlightRegion({
    required this.start,
    required this.end,
    required this.color,
    required this.type,
  });
}
