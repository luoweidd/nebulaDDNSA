// d:\projectfile\Fluterproject\nebulaDDNSA\lib\providers\ddns_manager_provider.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nebula_ddns/config/ddns_config.dart';
import 'package:nebula_ddns/providers/ddns_logs_provider.dart';
import 'package:nebula_ddns/services/configurable_ddns_service.dart';
import 'package:nebula_ddns/ddns_manager.dart';
import 'package:nebula_ddns/scheduler/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:nebula_ddns/platform/platform_manager.dart';
import 'package:nebula_ddns/platform/system_boot_manager.dart';

final systemBootManagerProvider = Provider<SystemBootManager>(
  (ref) => PlatformManager.createBootManager(),
);

/// DDNSManagerProvider: 暴露 DDNSManager 实例和状态给整个应用。
///
/// 企业级特性：
/// - 依赖注入模式
/// - 配置持久化与恢复
/// - 实时状态更新
/// - 日志集成
final ddnsManagerProvider =
    StateNotifierProvider<DDNSManagerNotifier, Map<String, dynamic>>((ref) {
  // 实例化服务和调度器（具体调度器由 main.dart 决定）
  final ddnsService = ConfigurableDDNSService();
  // 初始调度器占位，实际调度器在 main.dart 注入
  final scheduler = PlatformManager.supportsMobileBackground
      ? ExternalScheduler()
      : DesktopScheduler();

  final manager = DDNSManager(
    ddnsService: ddnsService,
    scheduler: scheduler,
    onLogCallback: (log) => ref.read(ddnsLogsProvider.notifier).add(log),
  );

  // 初始状态
  return DDNSManagerNotifier(manager, ref);
});

/// DDNSManagerNotifier: 封装 DDNSManager 的状态变化和操作。
class DDNSManagerNotifier extends StateNotifier<Map<String, dynamic>> {
  final DDNSManager _manager;
  final Ref _ref;
  static const String configKey = 'ddns_config_json';
  static const String _secretKey = 'ddns_api_key';
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  DDNSManagerNotifier(this._manager, this._ref)
      : super(const {
          'isConfigured': false,
          'isRunning': false,
          'isUpdateSuccessful': false,
          'lastUpdateTime': null,
          'lastError': null,
          'hostname': null,
          'serviceType': null,
          'startOnSystemBoot': false,
          'publicIP': null,
          'updateIntervalSeconds': 300,
        });

  void _syncManagerState() {
    final config = _manager.config;
    state = {
      ...state,
      'isConfigured': config != null,
      'isRunning': _manager.isRunning(),
      'hostname': config?.hostname,
      'serviceType': config?.serviceType,
      'startOnSystemBoot': config?.startOnSystemBoot ?? false,
    };
  }

  /// 加载配置（从 Provider 调用）
  Future<void> loadConfig(DDNSConfig config) async {
    await _writeApiKey(config.apiKey);
    final publicConfig = <String, dynamic>{
      'hostname': config.hostname,
      'serviceType': config.serviceType,
      'apiUrl': config.apiUrl,
      'updateRequestConfig': config.updateRequestConfig,
      'startOnSystemBoot': config.startOnSystemBoot,
    };
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(configKey, jsonEncode(publicConfig));

    _manager.loadConfig(config);
    _syncManagerState();
    _ref.read(ddnsLogsProvider.notifier).add('已加载配置：${config.hostname}');

    if (config.startOnSystemBoot) {
      final bootManager = _ref.read(systemBootManagerProvider);
      unawaited(
        bootManager.register().then((registered) {
          _ref.read(ddnsLogsProvider.notifier).add(
                registered ? '已注册系统启动项。' : '系统启动项注册失败。',
              );
        }),
      );
    } else {
      unawaited(_ref.read(systemBootManagerProvider).unregister());
    }
  }

  static Future<DDNSConfig?> restoreConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(configKey);
    if (json == null || json.isEmpty) return null;

    final map = jsonDecode(json) as Map<String, dynamic>;
    var apiKey = await _secureStorage.read(key: _secretKey);
    final legacyApiKey = map.remove('apiKey');
    if ((apiKey == null || apiKey.isEmpty) &&
        legacyApiKey is String &&
        legacyApiKey.isNotEmpty) {
      await _writeApiKey(legacyApiKey);
      apiKey = legacyApiKey;
    }
    if ((apiKey == null || apiKey.isEmpty) &&
        await _secureStorage.containsKey(key: _secretKey)) {
      throw StateError('安全存储中的 API 密钥无法读取，请重新输入并保存。');
    }
    if (legacyApiKey != null) {
      await prefs.setString(configKey, jsonEncode(map));
    }
    return DDNSConfig(
      hostname: map['hostname']?.toString() ?? '',
      serviceType: map['serviceType']?.toString() ?? '',
      apiUrl: map['apiUrl']?.toString() ?? '',
      apiKey: apiKey ?? '',
      updateRequestConfig:
          (map['updateRequestConfig'] as Map?)?.cast<String, dynamic>(),
      startOnSystemBoot: map['startOnSystemBoot'] == true,
    );
  }

  static Future<void> _writeApiKey(String apiKey) async {
    await _secureStorage.write(key: _secretKey, value: apiKey);
    final savedApiKey = await _secureStorage.read(key: _secretKey);
    if (savedApiKey != apiKey) {
      throw StateError('安全存储中的 API 密钥写入校验失败，请检查设备密钥存储。');
    }
  }

  /// 启动服务
  Future<void> startService(int intervalSeconds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('ddns_update_interval_seconds', intervalSeconds);
    _manager.startService(intervalSeconds);
    _syncManagerState();
    state = {...state, 'updateIntervalSeconds': intervalSeconds};
    _ref.read(ddnsLogsProvider.notifier).add('服务已启动（间隔 $intervalSeconds 秒）');
    if (PlatformManager.supportsMobileBackground) {
      final started = await PlatformManager.startMobileBackgroundService();
      if (!started) {
        _manager.stopService();
        _syncManagerState();
        throw StateError('无法启动移动端后台服务。');
      }
    }
  }

  /// 停止服务
  Future<void> stopService() async {
    _manager.stopService();
    _syncManagerState();
    _ref.read(ddnsLogsProvider.notifier).add('服务已停止');
    if (PlatformManager.supportsMobileBackground) {
      await PlatformManager.stopMobileBackgroundService();
    }
  }

  /// 手动更新
  Future<bool> updateNow() async {
    final success = await _manager.updateNow();
    state = {
      ...state,
      'isRunning': _manager.isRunning(),
      'isUpdateSuccessful': success,
      'lastUpdateTime':
          success ? DateTime.now().toIso8601String() : state['lastUpdateTime'],
      'lastError': success ? null : _manager.getLastLog(),
    };
    if (success) {
      _ref.read(ddnsLogsProvider.notifier).add('手动 DDNS 更新成功');
    } else {
      _ref
          .read(ddnsLogsProvider.notifier)
          .add('手动 DDNS 更新失败：${_manager.getLastLog()}');
    }
    return success;
  }

  /// 获取公网 IP
  Future<String?> getPublicIP() async {
    final ip = await _manager.getPublicIP();
    if (ip != null) {
      state = {...state, 'publicIP': ip};
      _ref.read(ddnsLogsProvider.notifier).add('公网 IP: $ip');
    }
    return ip;
  }

  /// 清空日志
  void clearLogs() {
    _manager.clearLogs();
    _ref.read(ddnsLogsProvider.notifier).clear();
    _ref.read(ddnsLogsProvider.notifier).add('日志已清空');
  }

  /// 获取最后一条日志
  String? getLastLog() {
    return _manager.getLastLog();
  }
}
