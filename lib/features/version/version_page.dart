import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'version_service.dart';
import 'version_history.dart';

/// 版本历史页面
class VersionHistoryPage extends StatelessWidget {
  const VersionHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('版本历史'),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_new),
            tooltip: '查看 GitHub Releases',
            onPressed: () => _openReleasesPage(context),
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: '清空历史',
            onPressed: () => _showClearDialog(context),
          ),
        ],
      ),
      body: FutureBuilder<List<VersionHistoryItem>>(
        future: versionHistoryService.getHistory(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final history = snapshot.data ?? [];
          
          if (history.isEmpty) {
            return _buildEmptyState(context);
          }
          
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: history.length,
            itemBuilder: (context, index) {
              final item = history[index];
              return _VersionHistoryListItem(
                item: item,
                onTap: () => _showVersionDetails(context, item),
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
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            '暂无版本历史',
            style: TextStyle(
              fontSize: 18,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '构建项目以记录版本历史',
            style: TextStyle(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => _openReleasesPage(context),
            icon: const Icon(Icons.open_in_new),
            label: const Text('查看 GitHub Releases'),
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
        content: const Text('确定要清空所有版本历史吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              versionHistoryService.clearHistory();
              Navigator.pop(context);
              // 刷新页面
              (context.findAncestorStateOfType<State>() as? State)?.setState(() {});
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _showVersionDetails(BuildContext context, VersionHistoryItem item) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (item.isRelease)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'Release',
                        style: TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item.version.displayVersion,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _DetailRow(
                icon: Icons.calendar_today,
                label: '构建时间',
                value: DateFormat('yyyy-MM-dd HH:mm').format(item.createdAt),
              ),
              if (item.commitHash != null)
                _DetailRow(
                  icon: Icons.commit,
                  label: 'Commit',
                  value: item.commitHash!.substring(0, 7),
                ),
              _DetailRow(
                icon: Icons.tag,
                label: '版本号',
                value: item.version.versionString,
              ),
              if (item.changelog != null) ...[
                const SizedBox(height: 16),
                const Text(
                  '更新日志',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  item.changelog!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              if (item.isRelease)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _openReleasePage(context, item),
                    icon: const Icon(Icons.download),
                    label: const Text('下载 APK'),
                  ),
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _openReleasesPage(context),
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('查看 Releases'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _openReleasePage(BuildContext context, VersionHistoryItem item) async {
    final url = versionService.getReleaseUrl(item.version.versionString);
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  void _openReleasesPage(BuildContext context) async {
    await launchUrl(
      Uri.parse(versionService.releasesPageUrl),
      mode: LaunchMode.externalApplication,
    );
  }
}

class _VersionHistoryListItem extends StatelessWidget {
  final VersionHistoryItem item;
  final VoidCallback onTap;

  const _VersionHistoryListItem({
    required this.item,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: item.isRelease
              ? colorScheme.primary
              : colorScheme.surfaceContainerHighest,
          child: Icon(
            item.isRelease ? Icons.verified : Icons.history,
            color: item.isRelease ? Colors.white : colorScheme.onSurfaceVariant,
          ),
        ),
        title: Row(
          children: [
            Text(
              item.version.gitTag,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if (item.isRelease) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Release',
                  style: TextStyle(
                    fontSize: 10,
                    color: colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: Text(
          DateFormat('yyyy-MM-dd HH:mm').format(item.createdAt),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
