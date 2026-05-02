import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'build_config.dart';
import 'build_service.dart';

/// 构建进度组件
/// 显示构建过程中的实时状态和日志
class BuildProgressWidget extends StatefulWidget {
  final BuildHistoryItem buildItem;
  final VoidCallback? onCancel;
  final VoidCallback? onClose;
  final Function(String)? onDownloadApk;

  const BuildProgressWidget({
    super.key,
    required this.buildItem,
    this.onCancel,
    this.onClose,
    this.onDownloadApk,
  });

  @override
  State<BuildProgressWidget> createState() => _BuildProgressWidgetState();
}

class _BuildProgressWidgetState extends State<BuildProgressWidget> {
  final List<String> _logs = [];
  final ScrollController _scrollController = ScrollController();
  StreamSubscription<String>? _logSubscription;
  StreamSubscription<BuildHistoryItem?>? _statusSubscription;
  BuildHistoryItem? _currentBuild;

  @override
  void initState() {
    super.initState();
    _currentBuild = widget.buildItem;
    _initListeners();
  }

  void _initListeners() {
    // 监听日志
    _logSubscription = buildService.logStream.listen((log) {
      if (mounted) {
        setState(() {
          _logs.add(log);
        });
        _scrollToBottom();
      }
    });

    // 监听构建状态
    _statusSubscription = buildService.buildStatusStream.listen((item) {
      if (item != null && mounted) {
        setState(() {
          _currentBuild = item;
        });
        
        // 构建完成时自动滚动到底部
        if (item.status != BuildStatus.running && 
            item.status != BuildStatus.pending) {
          _scrollToBottom();
        }
      }
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _logSubscription?.cancel();
    _statusSubscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isBuilding = _currentBuild?.status == BuildStatus.running ||
        _currentBuild?.status == BuildStatus.pending;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 标题栏
          _buildHeader(colorScheme),
          
          // 状态显示
          _buildStatusSection(colorScheme),
          
          // 日志区域
          Expanded(
            child: _buildLogArea(colorScheme),
          ),
          
          // 操作按钮
          _buildActions(colorScheme, isBuilding),
        ],
      ),
    );
  }

  Widget _buildHeader(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceVariant,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.construction,
            color: colorScheme.primary,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '构建 ${_currentBuild?.projectName ?? '项目'}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 18),
            tooltip: '复制日志',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _logs.join('\n')));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('日志已复制')),
              );
            },
          ),
          if (widget.onClose != null)
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              tooltip: '关闭',
              onPressed: widget.onClose,
            ),
        ],
      ),
    );
  }

  Widget _buildStatusSection(ColorScheme colorScheme) {
    final status = _currentBuild?.status ?? BuildStatus.pending;
    final buildType = _currentBuild?.buildType ?? BuildType.debug;
    
    Color statusColor;
    IconData statusIcon;
    
    switch (status) {
      case BuildStatus.success:
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case BuildStatus.failure:
        statusColor = Colors.red;
        statusIcon = Icons.error;
        break;
      case BuildStatus.cancelled:
        statusColor = Colors.orange;
        statusIcon = Icons.cancel;
        break;
      case BuildStatus.running:
        statusColor = colorScheme.primary;
        statusIcon = Icons.sync;
        break;
      case BuildStatus.pending:
      default:
        statusColor = colorScheme.secondary;
        statusIcon = Icons.schedule;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          // 状态图标
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: status == BuildStatus.running
                ? SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: statusColor,
                    ),
                  )
                : Icon(statusIcon, color: statusColor, size: 24),
          ),
          const SizedBox(width: 16),
          
          // 状态文字
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status.label,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _buildChip(buildType.label, colorScheme.primaryContainer),
                    const SizedBox(width: 8),
                    if (_currentBuild?.durationString != '--')
                      Text(
                        _currentBuild!.durationString,
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 13,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12),
      ),
    );
  }

  Widget _buildLogArea(ColorScheme colorScheme) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(8),
      ),
      child: _logs.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.terminal,
                    size: 48,
                    color: colorScheme.onSurfaceVariant.withOpacity(0.5),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '等待构建开始...',
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant.withOpacity(0.5),
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              itemCount: _logs.length,
              itemBuilder: (context, index) {
                final log = _logs[index];
                Color textColor = Colors.white70;
                
                if (log.contains('[ERROR]')) {
                  textColor = Colors.redAccent;
                } else if (log.contains('成功') || log.contains('success')) {
                  textColor = Colors.greenAccent;
                } else if (log.contains('失败') || log.contains('error')) {
                  textColor = Colors.orangeAccent;
                } else if (log.contains('警告') || log.contains('warning')) {
                  textColor = Colors.yellowAccent;
                }

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Text(
                    log,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: textColor,
                      height: 1.4,
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildActions(ColorScheme colorScheme, bool isBuilding) {
    final status = _currentBuild?.status ?? BuildStatus.pending;
    final hasApk = _currentBuild?.apkPath != null && 
        _currentBuild!.apkPath!.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          // 取消按钮
          if (isBuilding && widget.onCancel != null)
            Expanded(
              child: OutlinedButton.icon(
                onPressed: widget.onCancel,
                icon: const Icon(Icons.stop),
                label: const Text('取消构建'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          
          if (isBuilding) const SizedBox(width: 12),
          
          // 主操作按钮
          Expanded(
            flex: 2,
            child: FilledButton.icon(
              onPressed: () {
                if (status == BuildStatus.success && hasApk) {
                  widget.onDownloadApk?.call(_currentBuild!.apkPath!);
                } else if (!isBuilding) {
                  widget.onClose?.call();
                }
              },
              icon: Icon(
                status == BuildStatus.success
                    ? Icons.download
                    : status == BuildStatus.failure
                        ? Icons.refresh
                        : Icons.home,
              ),
              label: Text(
                status == BuildStatus.success
                    ? '下载 APK'
                    : status == BuildStatus.failure
                        ? '重新构建'
                        : '返回',
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 构建历史列表项
class BuildHistoryListItem extends StatelessWidget {
  final BuildHistoryItem item;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  const BuildHistoryListItem({
    super.key,
    required this.item,
    this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    Color statusColor;
    IconData statusIcon;
    
    switch (item.status) {
      case BuildStatus.success:
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case BuildStatus.failure:
        statusColor = Colors.red;
        statusIcon = Icons.error;
        break;
      case BuildStatus.cancelled:
        statusColor = Colors.orange;
        statusIcon = Icons.cancel;
        break;
      case BuildStatus.running:
        statusColor = colorScheme.primary;
        statusIcon = Icons.sync;
        break;
      case BuildStatus.pending:
      default:
        statusColor = colorScheme.secondary;
        statusIcon = Icons.schedule;
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // 状态图标
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: item.status == BuildStatus.running
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: statusColor,
                        ),
                      )
                    : Icon(statusIcon, color: statusColor, size: 20),
              ),
              const SizedBox(width: 16),
              
              // 信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.projectName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _buildChip(item.buildType.label, colorScheme.primaryContainer),
                        const SizedBox(width: 8),
                        Text(
                          _formatTime(item.startTime),
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    if (item.durationString != '--') ...[
                      const SizedBox(height: 4),
                      Text(
                        '耗时: ${item.durationString}',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (item.errorMessage != null && item.errorMessage!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        item.errorMessage!,
                        style: TextStyle(
                          fontSize: 12,
                          color: statusColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              
              // 删除按钮
              if (onDelete != null && item.status != BuildStatus.running)
                IconButton(
                  icon: Icon(Icons.delete_outline, color: colorScheme.error),
                  onPressed: onDelete,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 10),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    
    if (diff.inMinutes < 1) {
      return '刚刚';
    } else if (diff.inHours < 1) {
      return '${diff.inMinutes}分钟前';
    } else if (diff.inDays < 1) {
      return '${diff.inHours}小时前';
    } else {
      return '${time.month}/${time.day} ${time.hour}:${time.minute.toString().padLeft(2, '0')}';
    }
  }
}
