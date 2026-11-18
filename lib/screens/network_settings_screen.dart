import 'package:flutter/material.dart';

import '../services/ip_resolver.dart';
import '../services/network_settings.dart';

class NetworkSettingsScreen extends StatefulWidget {
  const NetworkSettingsScreen({super.key});

  @override
  State<NetworkSettingsScreen> createState() => _NetworkSettingsScreenState();
}

class _NetworkSettingsScreenState extends State<NetworkSettingsScreen> {
  final _rangesController = TextEditingController();
  final _ipv4QueryUrlsController = TextEditingController();
  final _ipv6QueryUrlsController = TextEditingController();
  bool _ipv6OnlyMode = false;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _rangesController.dispose();
    _ipv4QueryUrlsController.dispose();
    _ipv6QueryUrlsController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await NetworkSettingsStore.load();
      if (!mounted) return;
      setState(() {
        _ipv6OnlyMode = settings.ipv6OnlyMode;
        _rangesController.text = settings.customInternalRanges.join('\n');
        _ipv4QueryUrlsController.text = settings.customIPv4QueryUrls.join('\n');
        _ipv6QueryUrlsController.text = settings.customIPv6QueryUrls.join('\n');
      });
    } catch (error) {
      if (mounted) setState(() => _error = '加载网络设置失败：$error');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<String>? _parseRanges() {
    try {
      final values = _rangesController.text
          .split(RegExp(r'[\s,;]+'))
          .where((value) => value.isNotEmpty)
          .map((value) => IpNetworkRange.parse(value).normalized)
          .toSet()
          .toList();
      _error = null;
      return values;
    } on FormatException catch (error) {
      setState(() => _error = error.message);
      return null;
    }
  }

  List<String>? _parseQueryUrls(
    TextEditingController controller,
    String addressFamily,
  ) {
    final urls = controller.text
        .split(RegExp(r'[\r\n]+'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
    for (final url in urls) {
      final uri = Uri.tryParse(url);
      if (uri == null ||
          !uri.hasAuthority ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          (uri.scheme != 'http' && uri.scheme != 'https')) {
        setState(() => _error = '$addressFamily 查询地址无效：$url');
        return null;
      }
    }
    return urls;
  }

  Future<void> _saveSettings() async {
    final ranges = _parseRanges();
    if (ranges == null) return;
    final ipv4QueryUrls = _parseQueryUrls(_ipv4QueryUrlsController, 'IPv4');
    if (ipv4QueryUrls == null) return;
    final ipv6QueryUrls = _parseQueryUrls(_ipv6QueryUrlsController, 'IPv6');
    if (ipv6QueryUrls == null) return;

    setState(() => _isSaving = true);
    try {
      await NetworkSettingsStore.save(
        NetworkSettings(
          ipv6OnlyMode: _ipv6OnlyMode,
          customInternalRanges: ranges,
          customIPv4QueryUrls: ipv4QueryUrls,
          customIPv6QueryUrls: ipv6QueryUrls,
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('网络设置已保存并立即生效。')));
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) setState(() => _error = '保存网络设置失败：$error');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('网络设置'),
        actions: [
          TextButton.icon(
            onPressed: _isLoading || _isSaving ? null : _saveSettings,
            icon: _isSaving
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(_isSaving ? '保存中' : '保存'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('IPv6-only DDNS 模式'),
                  subtitle: const Text(
                    '保留现有 IPv4 A 记录；只更新已经配置好的 IPv6 AAAA 记录。公网 IPv6 未通过验证时将停止更新。',
                  ),
                  value: _ipv6OnlyMode,
                  onChanged: (value) => setState(() => _ipv6OnlyMode = value),
                ),
                const SizedBox(height: 8),
                Text(
                  '启用后，Cloudflare 需选择现有 AAAA 记录；DuckDNS 使用 IPv6 参数；自定义 API 需在请求参数中设置 ip_type 为 ipv6。未明确支持 IPv6 的内置服务会拒绝更新，不会回退修改 A 记录。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                Text('自定义内网地址范围', style: theme.textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(
                  '每行填写一个 IPv4/IPv6 地址或 CIDR 网段。命中这些范围的解析结果会被排除，包括使用公网格式地址配置的内网网段。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _rangesController,
                  key: const Key('internalRangesInput'),
                  minLines: 4,
                  maxLines: 8,
                  keyboardType: TextInputType.multiline,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: '例如：\n10.20.0.0/16\n2001:db8:1234::/48',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 24),
                Text('自定义公网 IP 查询地址', style: theme.textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(
                  'IPv4、IPv6 分别配置，每行一个 HTTP(S) 地址，响应内容应为纯 IP。留空时使用内置查询源；填写后替换该协议的内置查询源。配置多条时会并发查询，至少两条有效结果一致且所有有效结果必须一致。单条配置直接使用该结果。网络错误和无效结果会被忽略。建议使用 HTTPS。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _ipv4QueryUrlsController,
                  key: const Key('ipv4QueryUrlsInput'),
                  minLines: 2,
                  maxLines: 5,
                  keyboardType: TextInputType.multiline,
                  decoration: const InputDecoration(
                    labelText: 'IPv4 查询地址',
                    border: OutlineInputBorder(),
                    hintText: 'https://api.ipify.org',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _ipv6QueryUrlsController,
                  key: const Key('ipv6QueryUrlsInput'),
                  minLines: 2,
                  maxLines: 5,
                  keyboardType: TextInputType.multiline,
                  decoration: const InputDecoration(
                    labelText: 'IPv6 查询地址',
                    border: OutlineInputBorder(),
                    hintText:
                        'https://api6.ipify.org\nhttps://ipv6.icanhazip.com',
                    alignLabelWithHint: true,
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
              ],
            ),
    );
  }
}
