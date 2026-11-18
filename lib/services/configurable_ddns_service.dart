// d:\projectfile\Fluterproject\nebulaDDNSA\lib\services\configurable_ddns_service.dart

import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import 'package:nebula_ddns/config/ddns_config.dart';

import 'ddns_service_adapters.dart';
import 'id_ddns_service.dart';
import 'ip_resolver.dart';
import 'network_settings.dart';
import 'public_ip_addresses.dart';

/// ConfigurableDDNSService：基于配置动态选择服务商适配器的实现。
///
/// 实现了 IDDNSService 接口，不依赖特定服务商的硬编码 API。
///
/// 企业级特性：
/// - 根据配置的服务类型（serviceType）自动选择对应服务商适配器
/// - 实现指数退避重试机制
/// - 支持超时控制（连接/读取）
/// - 完善的错误分类和日志记录
/// - 集成公网 IP 解析（IPResolver），更新前自动解析公网 IP
class ConfigurableDDNSService implements IDDNSService {
  final Dio _dio;
  final IPResolver? _providedIpResolver;
  final Future<NetworkSettings> Function() _networkSettingsProvider;
  late final IPResolver _ipResolver =
      _providedIpResolver ??
      IPResolver(
        dioInstance: _dio,
        customInternalRangesProvider: () async =>
            (await _networkSettingsProvider()).customInternalRanges,
        customIPv4QueryEndpointsProvider: () async =>
            (await _networkSettingsProvider()).customIPv4QueryUrls,
        customIPv6QueryEndpointsProvider: () async =>
            (await _networkSettingsProvider()).customIPv6QueryUrls,
      );
  final Logger _logger;
  String _lastError = "No error.";
  int _retryCount = 0;
  final int _maxRetries = 3;

  /// 当前配置
  DDNSConfig? _config;

  /// 初始化 Dio 客户端，配置超时和拦截器
  ConfigurableDDNSService({
    Dio? dioInstance,
    IPResolver? ipResolver,
    Logger? logger,
    Duration? connectTimeout,
    Duration? receiveTimeout,
    Future<NetworkSettings> Function()? networkSettingsProvider,
  }) : _dio =
           dioInstance ??
           Dio(
             BaseOptions(
               connectTimeout: connectTimeout ?? const Duration(seconds: 10),
               receiveTimeout: receiveTimeout ?? const Duration(seconds: 30),
               contentType: 'application/json',
             ),
           ),
       _providedIpResolver = ipResolver,
       _networkSettingsProvider =
           networkSettingsProvider ?? _defaultNetworkSettings,
       _logger = logger ?? Logger() {
    // 添加请求拦截器：记录请求信息
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          _logger.i('[DDNS] Request: ${options.method} ${options.uri}');
          return handler.next(options);
        },
        onResponse: (response, handler) {
          _logger.i('[DDNS] Response: ${response.statusCode}');
          return handler.next(response);
        },
        onError: (error, handler) {
          _logger.w('[DDNS] Error: ${error.message}');
          return handler.next(error);
        },
      ),
    );
  }

  /// 获取 Dio 客户端实例（用于测试）
  Dio get dio => _dio;

  /// 获取 IP 解析器实例
  IPResolver get ipResolver => _ipResolver;

  /// 获取当前配置的服务类型。
  String get serviceType => _config?.serviceType ?? 'custom_api';

  /// 设置当前配置
  void setConfig(DDNSConfig config) {
    _config = config;
  }

  /// 获取当前配置
  DDNSConfig? get config => _config;

  @override
  String getLastError() => _lastError;

  @override
  Future<String?> getPublicIP({bool forceRefresh = false}) async {
    try {
      final settings = await _networkSettingsProvider();
      final ip = settings.ipv6OnlyMode
          ? await _ipResolver.resolveVerifiedPublicIPv6()
          : await _ipResolver.resolvePublicIP(forceRefresh: forceRefresh);
      return ip;
    } catch (e) {
      _logger.w('Failed to resolve public IP: $e');
      return null;
    }
  }

  @override
  Future<PublicIPAddresses> getPublicIPs() => _ipResolver.resolvePublicIPs();

  /// 获取适配器返回的错误详情。
  String _getLastErrorDetail() {
    final serviceType = _config?.serviceType ?? 'custom_api';
    switch (serviceType) {
      case 'no-ip':
        return 'NoIP update failed';
      case 'duckdns':
        return 'DuckDNS update failed';
      case 'upivy':
        return 'UpIvY update failed';
      case 'cloudflare':
        return 'Cloudflare update failed';
      case 'custom_api':
      default:
        return 'Custom API update failed';
    }
  }

  /// 设置重试次数
  void setRetryCount(int count) {
    _retryCount = count;
  }

  /// 获取当前重试次数
  int get retryCount => _retryCount;

  /// 检查是否已达到最大重试次数
  bool get isMaxRetriesReached => _retryCount >= _maxRetries;

  /// 重置重试计数器
  void resetRetryCount() {
    _retryCount = 0;
  }

  @override
  Future<bool> checkStatus(DDNSConfig config) async {
    try {
      _config = config;
      final adapter = createAdapter(config.serviceType, dioInstance: _dio);
      final success = await adapter.checkStatus(config);
      if (success) {
        _lastError = 'No error.';
        return true;
      }
      _lastError =
          'Status Check Failed for ${config.serviceType}: ${_getLastErrorDetail()}';
      return false;
    } catch (e) {
      _lastError = 'Status Check Error: $e';
      return false;
    }
  }

  @override
  Future<bool> updateDDNS(DDNSConfig config) async {
    // 重置重试计数器
    resetRetryCount();
    _config = config;

    try {
      // 若配置未指定 IP，则自动解析公网 IP 并注入到配置中
      final settings = await _networkSettingsProvider();
      final resolvedConfig = settings.ipv6OnlyMode
          ? await _prepareIPv6OnlyConfig(config)
          : await _resolveIPIfNeeded(config);
      if (resolvedConfig == null) return false;

      final adapter = createAdapter(
        resolvedConfig.serviceType,
        dioInstance: _dio,
      );
      final result = await _retryWithExponentialBackoff(
        () => adapter.update(resolvedConfig),
      );

      if (result['success'] == true) {
        _lastError = 'No error.';
        return true;
      } else {
        // 根据是否有状态码分类错误
        final statusCode = result['statusCode'];
        if (statusCode == null || (statusCode is int && statusCode <= 0)) {
          // 网络错误（无响应）
          _lastError = 'Network or Parsing Error: ${result['error']}';
        } else {
          // HTTP 错误（有响应但状态码非成功）
          _lastError =
              'API Update Failed: Status $statusCode: ${result['error']}';
        }
        return false;
      }
    } catch (e) {
      _lastError = 'Network or Parsing Error: $e';
      return false;
    }
  }

  Future<DDNSConfig?> _prepareIPv6OnlyConfig(DDNSConfig config) async {
    final requestConfig = config.updateRequestConfig;
    final serviceType = config.serviceType.toLowerCase();
    final supportsIPv6Update = switch (serviceType) {
      'duckdns' => true,
      'cloudflare' => requestConfig['type']?.toString().toUpperCase() == 'AAAA',
      'custom_api' =>
        requestConfig['ip_type']?.toString().toLowerCase() == 'ipv6',
      _ => false,
    };

    if (!supportsIPv6Update) {
      _lastError = '当前服务配置未明确支持只更新 IPv6 AAAA；已保留 IPv4 A 记录。';
      return null;
    }

    final ipv6 = await _ipResolver.resolveVerifiedPublicIPv6();
    if (ipv6 == null) {
      _lastError = '公网 IPv6 未通过全球单播及多源一致性验证；已保留 IPv4 A 记录。';
      return null;
    }

    final ipv6RequestConfig = {
      ...requestConfig,
      'ip': ipv6,
      'ip_type': 'ipv6',
      if (serviceType == 'cloudflare') 'type': 'AAAA',
    };
    return config.copyWith({
      'ip': ipv6,
    }, updateRequestConfig: ipv6RequestConfig);
  }

  /// 若配置未指定 IP，则自动解析公网 IP 并注入到配置中
  Future<DDNSConfig> _resolveIPIfNeeded(DDNSConfig config) async {
    final ip = config.updateRequestConfig['ip'];
    if (ip != null && ip.toString().isNotEmpty) {
      await _ipResolver.ensureNoProxyOrVpn();
      return config;
    }

    try {
      await _ipResolver.ensureNoProxyOrVpn();
      final ipType = config.updateRequestConfig['ip_type']
          ?.toString()
          .toLowerCase();
      final resolvedIP = switch (ipType) {
        'ipv4' => await _ipResolver.resolveIPv4(),
        'ipv6' => await _ipResolver.resolveIPv6(),
        _ => await _ipResolver.resolvePublicIP(),
      };
      if (resolvedIP != null && resolvedIP.isNotEmpty) {
        _logger.i('Resolved public IP: $resolvedIP');
        return config.copyWith(
          {'ip': resolvedIP},
          updateRequestConfig: {
            ...config.updateRequestConfig,
            'ip': resolvedIP,
          },
        );
      }
      _logger.w('Unable to resolve public IP, using configured IP or empty');
      return config;
    } catch (e) {
      _logger.w('Failed to resolve public IP: $e');
      if (e is NetworkPathBlockedException) rethrow;
      return config;
    }
  }

  static Future<NetworkSettings> _defaultNetworkSettings() async =>
      const NetworkSettings();

  /// 指数退避重试机制
  Future<Map<String, dynamic>> _retryWithExponentialBackoff(
    Future<Map<String, dynamic>> Function() fn,
  ) async {
    while (true) {
      try {
        final result = await fn();
        final statusCode = result['statusCode'];
        if (statusCode is int &&
            (statusCode == 408 || statusCode == 429 || statusCode >= 500)) {
          throw DioException(
            requestOptions: RequestOptions(path: _config?.apiUrl ?? ''),
            response: Response(
              requestOptions: RequestOptions(path: _config?.apiUrl ?? ''),
              statusCode: statusCode,
            ),
            type: DioExceptionType.badResponse,
            message: result['error']?.toString(),
          );
        }
        return result;
      } catch (e) {
        _lastError = 'Retry Attempt Failed: $e';

        // 检查是否已达到最大重试次数
        if (_retryCount >= _maxRetries) {
          _logger.e('[DDNS] Max retries reached. Final error: $_lastError');
          throw Exception('Max retries reached: $_lastError');
        }

        // 指数退避：等待时间 = baseDelay * 2^retryCount（使用位移运算保证整数精确）
        final delay = Duration(seconds: 2 * (1 << _retryCount));
        _logger.w(
          '[DDNS] Retry ${_retryCount + 1}/$_maxRetries in ${delay.inSeconds} seconds...',
        );

        // 等待一段时间后重试
        await Future.delayed(delay);
        _retryCount++;
      }
    }
  }
}
