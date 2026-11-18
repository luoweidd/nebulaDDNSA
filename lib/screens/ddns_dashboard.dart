import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/ddns_config.dart';

import '../providers/ddns_logs_provider.dart';
import '../providers/ddns_manager_provider.dart';
import 'ddns_config_screen.dart';

class DDNSDashboardScreen extends ConsumerStatefulWidget {
  const DDNSDashboardScreen({super.key});

  @override
  ConsumerState<DDNSDashboardScreen> createState() =>
      _DDNSDashboardScreenState();
}

class _DDNSDashboardScreenState extends ConsumerState<DDNSDashboardScreen> {
  static const _intervalOptions = <int>[60, 300, 600, 1800, 3600];

  int _intervalSeconds = 300;
  bool _isUpdating = false;
  bool _isResolvingIp = false;
  bool _isRestoringConfig = true;

  @override
  void initState() {
    super.initState();
    _restoreSavedConfig();
  }

  Future<void> _restoreSavedConfig() async {
    try {
      var config = await DDNSManagerNotifier.restoreConfig();
      if (config == null) {
        final prefs = await SharedPreferences.getInstance();
        final json = prefs.getString(DDNSManagerNotifier.configKey);
        if (json != null) config = DDNSConfig.fromJson(json);
      }
      if (config != null && mounted) {
        final status = ref.read(ddnsManagerProvider);
        if (status['isConfigured'] != true) {
          await ref.read(ddnsManagerProvider.notifier).loadConfig(config);
        }
      }
    } catch (error) {
      if (mounted) {
        ref.read(ddnsLogsProvider.notifier).add('读取已保存配置失败：$error');
        _showMessage('读取已保存配置失败，请检查配置。', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isRestoringConfig = false);
      }
    }
  }

  Future<void> _openConfiguration() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const DDNSConfigScreen()),
    );
  }

  Future<void> _updateNow() async {
    if (ref.read(ddnsManagerProvider)['isConfigured'] != true) {
      _showMessage('请先完成 DDNS 配置。', isError: true);
      return;
    }
    setState(() => _isUpdating = true);
    try {
      final success = await ref.read(ddnsManagerProvider.notifier).updateNow();
      if (mounted) {
        _showMessage(
          success ? 'DDNS 更新成功。' : 'DDNS 更新失败，请查看最近日志。',
          isError: !success,
        );
      }
    } catch (error) {
      if (mounted) _showMessage('执行更新时发生错误：$error', isError: true);
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  Future<void> _resolvePublicIp() async {
    setState(() => _isResolvingIp = true);
    try {
      final ip = await ref.read(ddnsManagerProvider.notifier).getPublicIP();
      if (mounted) {
        _showMessage(
          ip == null ? '暂时无法获取公网 IP。' : '公网 IP 已刷新。',
          isError: ip == null,
        );
      }
    } catch (error) {
      if (mounted) _showMessage('获取公网 IP 失败：$error', isError: true);
    } finally {
      if (mounted) setState(() => _isResolvingIp = false);
    }
  }

  Future<void> _toggleService(bool isRunning) async {
    final notifier = ref.read(ddnsManagerProvider.notifier);
    if (!isRunning && ref.read(ddnsManagerProvider)['isConfigured'] != true) {
      _showMessage('请先配置服务商和域名，再启动 DDNS。', isError: true);
      return;
    }
    try {
      if (isRunning) {
        await notifier.stopService();
      } else {
        await notifier.startService(_intervalSeconds);
      }
    } catch (error) {
      if (mounted) _showMessage('服务状态切换失败：$error', isError: true);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(ddnsManagerProvider);
    final logs = ref.watch(ddnsLogsProvider);
    final isConfigured = status['isConfigured'] == true;
    final isRunning = status['isRunning'] == true;
    final lastUpdate = _parseDate(status['lastUpdateTime']);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nebula DDNS'),
        actions: [
          IconButton(
            tooltip: '配置 DDNS',
            onPressed: _openConfiguration,
            icon: const Icon(Icons.tune_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isRestoringConfig
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 960;
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1440),
                    child: SingleChildScrollView(
                      padding: EdgeInsets.all(isWide ? 32 : 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildPageHeading(
                            context,
                            isRunning: isRunning,
                            isConfigured: isConfigured,
                          ),
                          const SizedBox(height: 24),
                          _buildOverview(
                            context,
                            isRunning: isRunning,
                            isConfigured: isConfigured,
                            serviceType: status['serviceType'] as String?,
                            publicIp: status['publicIP'] as String?,
                            lastUpdate: lastUpdate,
                          ),
                          const SizedBox(height: 24),
                          if (isWide)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 5,
                                  child: _buildControls(
                                    context,
                                    isRunning: isRunning,
                                    isConfigured: isConfigured,
                                    status: status,
                                  ),
                                ),
                                const SizedBox(width: 20),
                                Expanded(
                                  flex: 4,
                                  child: _buildConfigurationSummary(
                                    context,
                                    isConfigured: isConfigured,
                                    hostname: status['hostname'] as String?,
                                    serviceType:
                                        status['serviceType'] as String?,
                                    startOnSystemBoot:
                                        status['startOnSystemBoot'] == true,
                                  ),
                                ),
                              ],
                            )
                          else ...[
                            _buildControls(
                              context,
                              isRunning: isRunning,
                              isConfigured: isConfigured,
                              status: status,
                            ),
                            const SizedBox(height: 16),
                            _buildConfigurationSummary(
                              context,
                              isConfigured: isConfigured,
                              hostname: status['hostname'] as String?,
                              serviceType: status['serviceType'] as String?,
                              startOnSystemBoot:
                                  status['startOnSystemBoot'] == true,
                            ),
                          ],
                          const SizedBox(height: 24),
                          _buildLogs(context, logs),
                          const SizedBox(height: 24),
                          Text(
                            '状态数据来自本机运行状态与 DDNS 操作记录。',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildPageHeading(
    BuildContext context, {
    required bool isRunning,
    required bool isConfigured,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final statusColor = !isConfigured
        ? colorScheme.outline
        : isRunning
            ? colorScheme.primary
            : colorScheme.tertiary;
    final statusText = !isConfigured
        ? '尚未配置'
        : isRunning
            ? '服务运行中'
            : '服务已停止';

    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      runSpacing: 12,
      spacing: 16,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '运行概览',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '集中管理动态 DNS、运行状态与最近活动。',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        _StatusBadge(
          label: statusText,
          color: statusColor,
          icon: !isConfigured
              ? Icons.settings_outlined
              : isRunning
                  ? Icons.check_circle_outline_rounded
                  : Icons.pause_circle_outline_rounded,
        ),
      ],
    );
  }

  Widget _buildOverview(
    BuildContext context, {
    required bool isRunning,
    required bool isConfigured,
    required String? serviceType,
    required String? publicIp,
    required DateTime? lastUpdate,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 16.0;
        final columns = constraints.maxWidth >= 900
            ? 4
            : constraints.maxWidth >= 560
                ? 2
                : 1;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            SizedBox(
              width: width,
              child: _MetricCard(
                title: '公网 IP',
                value: publicIp ?? '尚未获取',
                subtitle: publicIp == null ? '按需查询当前出口地址' : '最近一次查询结果',
                icon: Icons.public_rounded,
                action: IconButton(
                  tooltip: '刷新公网 IP',
                  onPressed: _isResolvingIp ? null : _resolvePublicIp,
                  icon: _isResolvingIp
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded),
                ),
              ),
            ),
            SizedBox(
              width: width,
              child: _MetricCard(
                title: '上次更新',
                value:
                    lastUpdate == null ? '暂无记录' : _formatDateTime(lastUpdate),
                subtitle: lastUpdate == null ? '尚未执行成功的更新' : '最近一次成功更新时间',
                icon: Icons.schedule_rounded,
              ),
            ),
            SizedBox(
              width: width,
              child: _MetricCard(
                title: '服务商',
                value: isConfigured ? _serviceName(serviceType) : '未选择',
                subtitle: '当前 DDNS 更新服务',
                icon: Icons.dns_rounded,
              ),
            ),
            SizedBox(
              width: width,
              child: _MetricCard(
                title: '运行状态',
                value: !isConfigured
                    ? '待配置'
                    : isRunning
                        ? '自动更新已启用'
                        : '自动更新已暂停',
                subtitle: isRunning ? '将按设定间隔检查并更新' : '可手动执行一次更新',
                icon: isRunning
                    ? Icons.sync_rounded
                    : Icons.pause_circle_outline_rounded,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildControls(
    BuildContext context, {
    required bool isRunning,
    required bool isConfigured,
    required Map<String, dynamic> status,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final interval = status['updateIntervalSeconds'] is int
        ? status['updateIntervalSeconds'] as int
        : _intervalSeconds;
    if (_intervalOptions.contains(interval)) _intervalSeconds = interval;

    return _SectionCard(
      title: '服务控制',
      description: '管理自动调度或立即触发一次 DDNS 更新。',
      icon: Icons.tune_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<int>(
            initialValue: _intervalSeconds,
            decoration: const InputDecoration(
              labelText: '自动更新间隔',
              prefixIcon: Icon(Icons.timer_outlined),
            ),
            items: _intervalOptions
                .map(
                  (seconds) => DropdownMenuItem<int>(
                    value: seconds,
                    child: Text(_formatInterval(seconds)),
                  ),
                )
                .toList(),
            onChanged: isRunning
                ? null
                : (seconds) {
                    if (seconds != null) {
                      setState(() => _intervalSeconds = seconds);
                    }
                  },
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color:
                  colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(
                  isRunning
                      ? Icons.autorenew_rounded
                      : Icons.info_outline_rounded,
                  color: isRunning
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    isRunning
                        ? '调度器正在运行，您仍可随时手动更新。'
                        : isConfigured
                            ? '服务启动后将按选定间隔自动更新。'
                            : '先添加服务配置，之后即可启用自动更新。',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: isConfigured
                    ? () => _toggleService(isRunning)
                    : _openConfiguration,
                icon: Icon(
                  isRunning
                      ? Icons.stop_circle_outlined
                      : isConfigured
                          ? Icons.play_circle_outline_rounded
                          : Icons.add_rounded,
                ),
                label: Text(
                  isRunning
                      ? '停止服务'
                      : isConfigured
                          ? '启动服务'
                          : '添加配置',
                ),
              ),
              OutlinedButton.icon(
                onPressed: !isConfigured || _isUpdating ? null : _updateNow,
                icon: _isUpdating
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.flash_on_outlined),
                label: Text(_isUpdating ? '正在更新' : '立即更新'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildConfigurationSummary(
    BuildContext context, {
    required bool isConfigured,
    required String? hostname,
    required String? serviceType,
    required bool startOnSystemBoot,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return _SectionCard(
      title: '当前配置',
      description: '查看当前生效的服务商与域名信息。',
      icon: Icons.settings_ethernet_rounded,
      trailing: TextButton.icon(
        onPressed: _openConfiguration,
        icon: const Icon(Icons.edit_outlined, size: 18),
        label: const Text('管理'),
      ),
      child: isConfigured
          ? Column(
              children: [
                _InfoRow(
                  label: '服务商',
                  value: _serviceName(serviceType),
                  icon: Icons.dns_outlined,
                ),
                const SizedBox(height: 14),
                _InfoRow(
                  label: '主机名',
                  value:
                      hostname?.trim().isNotEmpty == true ? hostname! : '未设置',
                  icon: Icons.language_rounded,
                ),
                const SizedBox(height: 14),
                _InfoRow(
                  label: '开机自启',
                  value: startOnSystemBoot ? '已启用' : '未启用',
                  icon: Icons.power_settings_new_rounded,
                ),
              ],
            )
          : Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color:
                    colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '还没有 DDNS 配置',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '添加服务商、域名与凭据后，即可开始管理动态解析。',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: _openConfiguration,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('配置 DDNS'),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildLogs(BuildContext context, List<String> logs) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final recentLogs = logs.take(8).toList(growable: false);
    return _SectionCard(
      title: '最近活动',
      description: '展示本机最近的 DDNS 操作与运行日志。',
      icon: Icons.receipt_long_rounded,
      trailing: TextButton.icon(
        onPressed: logs.isEmpty
            ? null
            : () => ref.read(ddnsManagerProvider.notifier).clearLogs(),
        icon: const Icon(Icons.delete_outline_rounded, size: 18),
        label: const Text('清空'),
      ),
      child: recentLogs.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: Text(
                  '暂无活动记录。启动服务或执行手动更新后，日志会显示在这里。',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          : Column(
              children: [
                for (var index = 0; index < recentLogs.length; index++) ...[
                  _LogRow(message: recentLogs[index]),
                  if (index != recentLogs.length - 1)
                    Divider(
                      height: 1,
                      color: colorScheme.outlineVariant.withValues(alpha: 0.55),
                    ),
                ],
              ],
            ),
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }

  static String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    final date =
        '${local.year}-${_twoDigits(local.month)}-${_twoDigits(local.day)}';
    final time = '${_twoDigits(local.hour)}:${_twoDigits(local.minute)}';
    return '$date $time';
  }

  static String _twoDigits(int value) => value.toString().padLeft(2, '0');

  static String _formatInterval(int seconds) {
    if (seconds < 60) return '$seconds 秒';
    final minutes = seconds ~/ 60;
    if (minutes < 60) return '$minutes 分钟';
    return '${minutes ~/ 60} 小时';
  }

  static String _serviceName(String? type) {
    switch (type?.toLowerCase()) {
      case 'no-ip':
      case 'noip':
        return 'No-IP';
      case 'duckdns':
        return 'DuckDNS';
      case 'upivy':
        return 'UpIvY';
      case 'cloudflare':
        return 'Cloudflare';
      case 'custom_api':
      case 'custom':
        return '自定义 API';
      case null:
      case '':
        return '未选择';
      default:
        return type!;
    }
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.label,
    required this.color,
    required this.icon,
  });

  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    this.action,
  });

  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (action != null) action!,
              ],
            ),
            const SizedBox(height: 12),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.child,
    this.trailing,
  });

  final String title;
  final String description;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    color: colorScheme.onPrimaryContainer,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        description,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 20),
            child,
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Row(
      children: [
        Icon(icon, size: 19, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 10),
        SizedBox(
          width: 76,
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final lowerMessage = message.toLowerCase();
    final isError = lowerMessage.contains('error') ||
        lowerMessage.contains('failed') ||
        lowerMessage.contains('失败');
    final iconColor = isError ? colorScheme.error : colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError
                ? Icons.error_outline_rounded
                : Icons.check_circle_outline_rounded,
            size: 19,
            color: iconColor,
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(message, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
