import 'package:flutter/material.dart';
import 'build_config.dart';
import 'build_service.dart';
import 'build_progress.dart';

/// 构建历史页面
class BuildHistoryPage extends StatelessWidget {
  final VoidCallback? onItemTap;

  const BuildHistoryPage({super.key, this.onItemTap});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('构建历史'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: '清空历史',
            onPressed: () => _showClearDialog(context),
          ),
        ],
      ),
      body: StreamBuilder<List<BuildHistoryItem>>(
        stream: buildService.historyStream,
        initialData: buildService.getHistory(),
        builder: (context, snapshot) {
          final history = snapshot.data ?? [];
          
          if (history.isEmpty) {
            return _buildEmptyState(context);
          }
          
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: history.length,
            itemBuilder: (context, index) {
              final item = history[index];
              return BuildHistoryListItem(
                item: item,
                onTap: () => onItemTap?.call(),
                onDelete: () => _deleteItem(context, index),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history,
            size: 80,
            color: colorScheme.onSurfaceVariant.withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          Text(
            '暂无构建记录',
            style: TextStyle(
              fontSize: 18,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '开始构建以查看历史记录',
            style: TextStyle(
              color: colorScheme.onSurfaceVariant.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }

  void _showClearDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空历史'),
        content: const Text('确定要清空所有构建历史吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              buildService.clearHistory();
              Navigator.pop(context);
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('清空'),
          ),
        ],
      ),
    );
  }

  void _deleteItem(BuildContext context, int index) {
    final history = buildService.getHistory();
    if (index < 0 || index >= history.length) return;
    
    final item = history[index];
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除记录'),
        content: Text('确定要删除 "${item.projectName}" 的构建记录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              // 删除指定记录
              // 注意：当前实现是清空所有，实际可以改进为删除单条
              Navigator.pop(context);
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}
