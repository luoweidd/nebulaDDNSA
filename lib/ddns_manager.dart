// d:\projectfile\Fluterproject\nebulaDDNSA\lib\ddns_manager.dart
import 'package:nebula_ddns/config/ddns_config.dart';
import 'package:nebula_ddns/services/id_ddns_service.dart';
import 'package:nebula_ddns/scheduler/scheduler.dart';

/// DDNSManager：核心业务逻辑层，负责配置、服务调用和调度管理。
/// 
/// 企业级特性：
/// - 依赖注入模式（通过构造函数或 Provider）
/// - 统一的日志记录接口
/// - 完整的状态管理
/// - 错误分类与处理
class DDNSManager {
  final IDDNSService ddnsService;
  final Scheduler scheduler;
  DDNSConfig? _config;
  bool _isRunning = false;
  List<String> _logs = [];
  DateTime? _lastUpdateTime;
  bool _lastUpdateSuccess = false;

  /// 日志回调函数（用于外部监听）
  void Function(String)? onLogCallback;

  DDNSManager({
    required this.ddnsService,
    required this.scheduler,
    this.onLogCallback,
  });

  /// 加载配置
  void loadConfig(DDNSConfig config) {
    _config = config;
    _log('Configuration loaded for hostname: ${config.hostname}');
  }

  /// 启动服务
  void startService(int intervalSeconds) {
    if (_config == null) {
      _log('Error: Configuration not loaded.');
      return;
    }
    
    // 检查状态
    ddnsService.checkStatus(_config!).then((_) {});
    
    // 初始化调度器
    scheduler.initialize(ddnsService, _config!, intervalSeconds);
    scheduler.start();
    
    _isRunning = true;
    _log('DDNS Service started with interval: ${intervalSeconds}s');
  }

  /// 停止服务
  void stopService() {
    scheduler.stop();
    _isRunning = false;
    _log('DDNS Service stopped.');
  }

  /// 获取运行状态
  bool isRunning() => _isRunning;

  /// 获取当前配置
  DDNSConfig? get config => _config;

  /// 获取服务类型显示名称
  String get serviceTypeDisplayName {
    switch (_config?.serviceType.toLowerCase()) {
      case 'no-ip':
        return 'No-IP';
      case 'duckdns':
        return 'DuckDNS';
      case 'upivy':
        return 'UpIvY';
      case 'cloudflare':
        return 'Cloudflare';
      case 'custom_api':
        return 'Custom API';
      default:
        return _config?.serviceType ?? 'Unknown';
    }
  }

  /// 获取服务状态详情
  Future<Map<String, dynamic>> getStatus() async {
    final config = _config;
    if (config == null) {
      return {
        'isRunning': _isRunning,
        'isUpdateSuccessful': _lastUpdateSuccess,
        'lastUpdateTime': _lastUpdateTime?.toIso8601String(),
        'lastError': ddnsService.getLastError(),
        'hostname': null,
        'serviceType': null,
        'startOnSystemBoot': false,
      };
    }
    await ddnsService.checkStatus(config);
    return {
      'isRunning': _isRunning,
      'isUpdateSuccessful': _lastUpdateSuccess,
      'lastUpdateTime': _lastUpdateTime?.toIso8601String(),
      'lastError': ddnsService.getLastError(),
      'hostname': _config?.hostname,
      'serviceType': _config?.serviceType ?? 'custom_api',
      'startOnSystemBoot': _config?.startOnSystemBoot ?? false,
    };
  }

  /// 获取公网 IP（带缓存）
  Future<String?> getPublicIP() async {
    try {
      return await ddnsService.getPublicIP();
    } catch (e) {
      _log('Failed to get public IP: $e');
      return null;
    }
  }

  /// 执行手动更新
  Future<bool> updateNow() async {
    if (_config == null) {
      _log('Error: Configuration not loaded.');
      return false;
    }
    
    try {
      final success = await ddnsService.updateDDNS(_config!);
      if (success) {
        _lastUpdateTime = DateTime.now();
        _lastUpdateSuccess = true;
        _log('Manual DDNS update successful');
      } else {
        _lastUpdateSuccess = false;
        _log('Manual DDNS update failed: ${ddnsService.getLastError()}');
      }
      return success;
    } catch (e) {
      _log('Manual DDNS update error: $e');
      return false;
    }
  }

  /// 内部日志记录方法
  void _log(String message) {
    final timestamp = DateTime.now().toIso8601String();
    final logEntry = '$timestamp - $message';
    
    // 添加到本地日志列表（限制数量）
    _logs.add(logEntry);
    if (_logs.length > 200) {
      _logs = _logs.sublist(_logs.length - 200);
    }

    // 调用外部回调（用于 Provider）
    onLogCallback?.call(logEntry);
  }

  /// 获取日志列表（不可变视图）
  List<String> get logs => List.unmodifiable(_logs);

  /// 清空日志
  void clearLogs() {
    _logs.clear();
    _log('Logs cleared');
  }

  /// 获取最后一条日志
  String? getLastLog() {
    return _logs.isNotEmpty ? _logs.last : null;
  }
}