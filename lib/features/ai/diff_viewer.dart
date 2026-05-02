import 'package:flutter/material.dart';
import 'dart:async';

/// 代码差异对比组件
class DiffViewer extends StatefulWidget {
  final String originalCode;
  final String modifiedCode;
  final String language;
  final VoidCallback? onApply;
  final VoidCallback? onUndo;
  final VoidCallback? onManualMerge;
  final bool showActions;

  const DiffViewer({
    super.key,
    required this.originalCode,
    required this.modifiedCode,
    this.language = '',
    this.onApply,
    this.onUndo,
    this.onManualMerge,
    this.showActions = true,
  });

  @override
  State<DiffViewer> createState() => _DiffViewerState();
}

class _DiffViewerState extends State<DiffViewer> {
  late List<DiffLine> _diffLines;
  final ScrollController _leftScrollController = ScrollController();
  final ScrollController _rightScrollController = ScrollController();
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _diffLines = _computeDiff(widget.originalCode, widget.modifiedCode);
    
    // 同步滚动
    _leftScrollController.addListener(() => _syncScroll(_leftScrollController, _rightScrollController));
    _rightScrollController.addListener(() => _syncScroll(_rightScrollController, _leftScrollController));
  }

  @override
  void dispose() {
    _leftScrollController.dispose();
    _rightScrollController.dispose();
    super.dispose();
  }

  void _syncScroll(ScrollController source, ScrollController target) {
    if (_isSyncing) return;
    _isSyncing = true;
    target.jumpTo(source.offset);
    _isSyncing = false;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 标题栏
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(width: 12, height: 12, color: Colors.red.shade200),
                    const SizedBox(width: 4),
                    const Text('原始代码', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              Container(width: 1, height: 16, color: Theme.of(context).dividerColor),
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  children: [
                    Container(width: 12, height: 12, color: Colors.green.shade200),
                    const SizedBox(width: 4),
                    const Text('修改后代码', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
        ),
        
        // 统计信息
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Row(
            children: [
              Icon(Icons.add, size: 14, color: Colors.green),
              Text(' ${_countChanges('add')} 添加', style: const TextStyle(fontSize: 10, color: Colors.green)),
              const SizedBox(width: 12),
              Icon(Icons.remove, size: 14, color: Colors.red),
              Text(' ${_countChanges('remove')} 删除', style: const TextStyle(fontSize: 10, color: Colors.red)),
              const SizedBox(width: 12),
              Icon(Icons.edit, size: 14, color: Colors.blue),
              Text(' ${_countChanges('modify')} 修改', style: const TextStyle(fontSize: 10, color: Colors.blue)),
            ],
          ),
        ),
        
        // 对比视图
        Expanded(
          child: Row(
            children: [
              // 左侧（原始）
              Expanded(child: _buildCodePanel(isOriginal: true)),
              Container(width: 1, color: Theme.of(context).dividerColor),
              // 右侧（修改）
              Expanded(child: _buildCodePanel(isOriginal: false)),
            ],
          ),
        ),
        
        // 操作按钮
        if (widget.showActions) _buildActionBar(),
      ],
    );
  }

  Widget _buildCodePanel({required bool isOriginal}) {
    final scrollController = isOriginal ? _leftScrollController : _rightScrollController;
    
    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: ListView.builder(
        controller: scrollController,
        itemCount: _diffLines.length,
        itemBuilder: (context, index) {
          final line = _diffLines[index];
          return _buildDiffLine(line, isOriginal);
        },
      ),
    );
  }

  Widget _buildDiffLine(DiffLine line, bool isOriginal) {
    Color bgColor = Colors.transparent;
    String content;
    String prefix = ' ';
    
    switch (line.type) {
      case DiffType.added:
        bgColor = Colors.green.shade50;
        prefix = '+';
        content = isOriginal ? '' : line.content;
        break;
      case DiffType.removed:
        bgColor = Colors.red.shade50;
        prefix = '-';
        content = isOriginal ? line.content : '';
        break;
      case DiffType.modified:
        bgColor = Colors.blue.shade50;
        content = line.content;
        break;
      case DiffType.unchanged:
        content = line.content;
        break;
    }
    
    if ((line.type == DiffType.added && isOriginal) || 
        (line.type == DiffType.removed && !isOriginal)) {
      bgColor = Colors.grey.shade100;
    }
    
    return Container(
      color: bgColor,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 行号
          Container(
            width: 30,
            alignment: Alignment.centerRight,
            child: Text(
              '${line.lineNumber}',
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey.shade500,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 4),
          // 前缀
          Text(
            prefix,
            style: TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
              color: line.type == DiffType.added ? Colors.green :
                     line.type == DiffType.removed ? Colors.red : Colors.grey,
            ),
          ),
          // 内容
          Expanded(
            child: Text(
              content,
              style: const TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionBar() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (widget.onUndo != null)
            TextButton.icon(
              onPressed: widget.onUndo,
              icon: const Icon(Icons.undo, size: 18),
              label: const Text('撤销'),
            ),
          const SizedBox(width: 8),
          if (widget.onManualMerge != null)
            OutlinedButton.icon(
              onPressed: widget.onManualMerge,
              icon: const Icon(Icons.merge, size: 18),
              label: const Text('手动合并'),
            ),
          const SizedBox(width: 8),
          if (widget.onApply != null)
            FilledButton.icon(
              onPressed: widget.onApply,
              icon: const Icon(Icons.check, size: 18),
              label: const Text('应用修改'),
            ),
        ],
      ),
    );
  }

  int _countChanges(String type) {
    switch (type) {
      case 'add':
        return _diffLines.where((l) => l.type == DiffType.added).length;
      case 'remove':
        return _diffLines.where((l) => l.type == DiffType.removed).length;
      case 'modify':
        return _diffLines.where((l) => l.type == DiffType.modified).length;
      default:
        return 0;
    }
  }

  /// 简单的 diff 算法
  List<DiffLine> _computeDiff(String original, String modified) {
    final originalLines = original.split('\n');
    final modifiedLines = modified.split('\n');
    final result = <DiffLine>[];
    
    int origIdx = 0;
    int modIdx = 0;
    int lineNum = 1;
    
    // 简单的 LCS 算法
    final lcs = _computeLCS(originalLines, modifiedLines);
    
    origIdx = 0;
    modIdx = 0;
    
    for (final commonLine in lcs) {
      // 添加原始文件中的删除行
      while (origIdx < originalLines.length && originalLines[origIdx] != commonLine) {
        result.add(DiffLine(
          content: originalLines[origIdx],
          type: DiffType.removed,
          lineNumber: lineNum++,
        ));
        origIdx++;
      }
      
      // 添加修改文件中的新增行
      while (modIdx < modifiedLines.length && modifiedLines[modIdx] != commonLine) {
        result.add(DiffLine(
          content: modifiedLines[modIdx],
          type: DiffType.added,
          lineNumber: lineNum++,
        ));
        modIdx++;
      }
      
      // 添加相同的行
      if (origIdx < originalLines.length && modIdx < modifiedLines.length) {
        result.add(DiffLine(
          content: originalLines[origIdx],
          type: DiffType.unchanged,
          lineNumber: lineNum++,
        ));
        origIdx++;
        modIdx++;
      }
    }
    
    // 添加剩余的行
    while (origIdx < originalLines.length) {
      result.add(DiffLine(
        content: originalLines[origIdx],
        type: DiffType.removed,
        lineNumber: lineNum++,
      ));
      origIdx++;
    }
    
    while (modIdx < modifiedLines.length) {
      result.add(DiffLine(
        content: modifiedLines[modIdx],
        type: DiffType.added,
        lineNumber: lineNum++,
      ));
      modIdx++;
    }
    
    return result;
  }

  /// 计算最长公共子序列
  List<String> _computeLCS(List<String> a, List<String> b) {
    if (a.isEmpty || b.isEmpty) return [];
    
    final m = a.length;
    final n = b.length;
    final dp = List.generate(m + 1, (_) => List.filled(n + 1, 0));
    
    for (int i = 1; i <= m; i++) {
      for (int j = 1; j <= n; j++) {
        if (a[i - 1] == b[j - 1]) {
          dp[i][j] = dp[i - 1][j - 1] + 1;
        } else {
          dp[i][j] = dp[i - 1][j] > dp[i][j - 1] ? dp[i - 1][j] : dp[i][j - 1];
        }
      }
    }
    
    // 回溯获取 LCS
    final result = <String>[];
    int i = m, j = n;
    while (i > 0 && j > 0) {
      if (a[i - 1] == b[j - 1]) {
        result.insert(0, a[i - 1]);
        i--;
        j--;
      } else if (dp[i - 1][j] > dp[i][j - 1]) {
        i--;
      } else {
        j--;
      }
    }
    
    return result;
  }
}

/// 差异行类型
enum DiffType {
  unchanged,
  added,
  removed,
  modified,
}

/// 差异行数据
class DiffLine {
  final String content;
  final DiffType type;
  final int lineNumber;

  DiffLine({
    required this.content,
    required this.type,
    required this.lineNumber,
  });
}

/// Diff 对话框
class DiffDialog extends StatelessWidget {
  final String originalCode;
  final String modifiedCode;
  final String language;
  final String title;

  const DiffDialog({
    super.key,
    required this.originalCode,
    required this.modifiedCode,
    this.language = '',
    this.title = '代码对比',
  });

  static Future<bool?> show({
    required BuildContext context,
    required String originalCode,
    required String modifiedCode,
    String language = '',
    String title = '代码对比',
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => DiffDialog(
        originalCode: originalCode,
        modifiedCode: modifiedCode,
        language: language,
        title: title,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: double.maxFinite,
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
            // 标题栏
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
              ),
              child: Row(
                children: [
                  const Icon(Icons.compare, size: 20),
                  const SizedBox(width: 8),
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context, false),
                  ),
                ],
              ),
            ),
            // Diff 视图
            Expanded(
              child: DiffViewer(
                originalCode: originalCode,
                modifiedCode: modifiedCode,
                language: language,
                onApply: () => Navigator.pop(context, true),
                onUndo: () => Navigator.pop(context, false),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
