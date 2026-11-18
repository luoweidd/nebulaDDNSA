import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/ddns_config.dart';
import '../providers/ddns_manager_provider.dart';

class DDNSConfigScreen extends ConsumerStatefulWidget {
  const DDNSConfigScreen({super.key});

  @override
  ConsumerState<DDNSConfigScreen> createState() => _DDNSConfigScreenState();
}

class _DDNSConfigScreenState extends ConsumerState<DDNSConfigScreen> {
  static const _defaultEndpoints = <String, String>{
    'no-ip': 'https://api.noip.com/noip/1.1/domain/update',
    'duckdns': 'https://www.duckdns.org/update',
    'upivy': 'https://ipv4.upvy.net/json',
    'cloudflare': 'https://api.cloudflare.com/client/v4',
    'custom_api': '',
  };

  final _formKey = GlobalKey<FormState>();
  final _hostnameController = TextEditingController();
  final _apiUrlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _requestConfigController = TextEditingController(text: '{}');

  String _serviceType = 'custom_api';
  bool _startOnSystemBoot = false;
  bool _isSaving = false;
  bool _isLoading = true;
  bool _showApiKey = false;
  String? _requestConfigError;

  @override
  void initState() {
    super.initState();
    _loadSavedConfig();
  }

  @override
  void dispose() {
    _hostnameController.dispose();
    _apiUrlController.dispose();
    _apiKeyController.dispose();
    _requestConfigController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedConfig() async {
    try {
      var config = await DDNSManagerNotifier.restoreConfig();
      if (config == null) {
        final prefs = await SharedPreferences.getInstance();
        final json = prefs.getString(DDNSManagerNotifier.configKey);
        if (json != null) config = DDNSConfig.fromJson(json);
      }
      if (config != null) {
        _hostnameController.text = config.hostname;
        _apiUrlController.text = config.apiUrl;
        _apiKeyController.text = config.apiKey;
        _requestConfigController.text = const JsonEncoder.withIndent('  ')
            .convert(config.updateRequestConfig);
        _serviceType = config.serviceType;
        _startOnSystemBoot = config.startOnSystemBoot;
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('加载已保存配置失败：$error'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _selectService(String serviceType) {
    setState(() {
      _serviceType = serviceType;
      final defaultEndpoint = _defaultEndpoints[serviceType];
      if (defaultEndpoint != null &&
          (_apiUrlController.text.isEmpty ||
              _defaultEndpoints.values.contains(_apiUrlController.text))) {
        _apiUrlController.text = defaultEndpoint;
      }
    });
  }

  Map<String, dynamic>? _decodeRequestConfig() {
    try {
      final decoded = jsonDecode(_requestConfigController.text);
      if (decoded is! Map) {
        setState(() => _requestConfigError = '请求参数必须是 JSON 对象。');
        return null;
      }
      _requestConfigError = null;
      return decoded.cast<String, dynamic>();
    } on FormatException catch (error) {
      setState(() => _requestConfigError = 'JSON 格式错误：${error.message}');
      return null;
    }
  }

  Future<void> _saveConfig() async {
    if (!_formKey.currentState!.validate()) return;
    final requestConfig = _decodeRequestConfig();
    if (requestConfig == null) {
      setState(() {});
      return;
    }

    final config = DDNSConfig(
      hostname: _hostnameController.text.trim(),
      serviceType: _serviceType,
      apiUrl: _apiUrlController.text.trim(),
      apiKey: _apiKeyController.text,
      updateRequestConfig: requestConfig,
      startOnSystemBoot: _startOnSystemBoot,
    );
    final validation = config.validate();
    final errors = validation['errors'] as List<String>;
    if (errors.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errors.join('；')),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final notifier = ref.read(ddnsManagerProvider.notifier);
      if (ref.read(ddnsManagerProvider)['isRunning'] == true) {
        notifier.stopService();
      }
      await notifier.loadConfig(config);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('配置已保存并生效。'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存配置失败：$error'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('DDNS 配置'),
        actions: [
          TextButton.icon(
            onPressed: _isSaving ? null : _saveConfig,
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
          : LayoutBuilder(
              builder: (context, constraints) {
                final horizontalPadding =
                    constraints.maxWidth >= 800 ? 40.0 : 20.0;
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 920),
                    child: Form(
                      key: _formKey,
                      child: ListView(
                        padding: EdgeInsets.fromLTRB(
                          horizontalPadding,
                          20,
                          horizontalPadding,
                          36,
                        ),
                        children: [
                          Text(
                            '连接动态 DNS 服务',
                            style: theme.textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '选择服务商，填写域名与凭据。凭据保存在本机，请勿分享配置导出内容。',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 24),
                          _buildSection(
                            context,
                            title: '服务商',
                            description: '选择内置适配器或自定义 API。',
                            icon: Icons.dns_outlined,
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: DDNSConfig.presets.map((preset) {
                                final type = preset['type']! as String;
                                return ChoiceChip(
                                  label: Text(preset['name']! as String),
                                  selected: _serviceType == type,
                                  onSelected: (_) => _selectService(type),
                                );
                              }).toList(),
                            ),
                          ),
                          const SizedBox(height: 16),
                          _buildSection(
                            context,
                            title: '连接信息',
                            description: 'API 密钥仅用于当前服务请求。',
                            icon: Icons.link_rounded,
                            child: Column(
                              children: [
                                TextFormField(
                                  controller: _hostnameController,
                                  decoration: const InputDecoration(
                                    labelText: '主机名 / 域名',
                                    hintText: '例如：home.example.com',
                                    prefixIcon: Icon(Icons.language_rounded),
                                  ),
                                  validator: (value) =>
                                      value == null || value.trim().isEmpty
                                          ? '请输入主机名或域名'
                                          : null,
                                ),
                                const SizedBox(height: 14),
                                TextFormField(
                                  controller: _apiUrlController,
                                  keyboardType: TextInputType.url,
                                  decoration: const InputDecoration(
                                    labelText: 'API 端点',
                                    hintText: 'https://api.example.com/update',
                                    prefixIcon: Icon(Icons.link_rounded),
                                  ),
                                  validator: (value) {
                                    if (value == null || value.trim().isEmpty) {
                                      return '请输入 API 端点';
                                    }
                                    final uri = Uri.tryParse(value.trim());
                                    if (uri == null ||
                                        !uri.hasScheme ||
                                        uri.host.isEmpty) {
                                      return '请输入有效的 HTTP 或 HTTPS URL';
                                    }
                                    if (uri.scheme != 'https' &&
                                        uri.scheme != 'http') {
                                      return '仅支持 HTTP 或 HTTPS URL';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 14),
                                TextFormField(
                                  controller: _apiKeyController,
                                  obscureText: !_showApiKey,
                                  decoration: InputDecoration(
                                    labelText: 'API 密钥 / 令牌',
                                    prefixIcon: const Icon(Icons.key_rounded),
                                    suffixIcon: IconButton(
                                      tooltip: _showApiKey ? '隐藏密钥' : '显示密钥',
                                      onPressed: () => setState(
                                        () => _showApiKey = !_showApiKey,
                                      ),
                                      icon: Icon(
                                        _showApiKey
                                            ? Icons.visibility_off_outlined
                                            : Icons.visibility_outlined,
                                      ),
                                    ),
                                  ),
                                  validator: (value) =>
                                      value == null || value.isEmpty
                                          ? '请输入 API 密钥或令牌'
                                          : null,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          _buildSection(
                            context,
                            title: '请求参数',
                            description:
                                '以 JSON 对象填写服务商所需字段，例如 domain_id、username、zone_id、record_id。',
                            icon: Icons.data_object_rounded,
                            child: TextFormField(
                              controller: _requestConfigController,
                              minLines: 5,
                              maxLines: 10,
                              keyboardType: TextInputType.multiline,
                              decoration: InputDecoration(
                                alignLabelWithHint: true,
                                labelText: '更新请求配置（JSON）',
                                errorText: _requestConfigError,
                                hintText: '{\n  "username": "your-account"\n}',
                              ),
                              onChanged: (_) {
                                if (_requestConfigError != null) {
                                  setState(() => _requestConfigError = null);
                                }
                              },
                            ),
                          ),
                          const SizedBox(height: 16),
                          Card(
                            child: SwitchListTile.adaptive(
                              value: _startOnSystemBoot,
                              onChanged: (value) => setState(
                                () => _startOnSystemBoot = value,
                              ),
                              title: const Text('系统启动时运行'),
                              subtitle: const Text(
                                '保存此偏好；是否实际自启取决于当前平台集成。',
                              ),
                              secondary: const Icon(Icons.power_settings_new),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton.icon(
                              onPressed: _isSaving ? null : _saveConfig,
                              icon: const Icon(Icons.save_rounded),
                              label: const Text('保存配置'),
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

  Widget _buildSection(
    BuildContext context, {
    required String title,
    required String description,
    required IconData icon,
    required Widget child,
  }) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        description,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            child,
          ],
        ),
      ),
    );
  }
}
