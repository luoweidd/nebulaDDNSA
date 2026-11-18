// d:\projectfile\Fluterproject\nebulaDDNSA\lib\services\ddns_service_adapters.dart
import 'package:dio/dio.dart';
import 'package:logger/logger.dart';

import '../config/ddns_config.dart';

/// DDNS 服务商适配器基类。
///
/// 企业级特性：
/// - 支持主流服务商：NoIP、DuckDNS、UpIvY、Cloudflare、CustomAPI（自定义 API）
/// - 统一的更新接口，平台无关
/// - 完善的错误处理和日志记录
abstract class DDNSServiceAdapter {
  /// 适配器服务类型（如 `no-ip`、`duckdns`、`custom_api`）。
  final String serviceType;

  final Dio _dio;
  final Logger _logger;

  DDNSServiceAdapter(this.serviceType, {Dio? dioInstance, Logger? logger})
      : _dio = dioInstance ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 30),
            )),
        _logger = logger ?? Logger();

  /// 获取适配器服务类型。
  String get type => serviceType;

  /// 更新 DDNS 记录。
  ///
  /// 返回结果映射，包含 `success`（布尔值）、`message`/`error` 及 `statusCode`。
  Future<Map<String, dynamic>> update(DDNSConfig config);

  /// 检查 DDNS 状态。
  ///
  /// 返回 `true` 表示状态正常，`false` 表示异常。
  Future<bool> checkStatus(DDNSConfig config);

  /// 构建标准结果映射。
  Map<String, dynamic> buildResult(
    bool success, [
    String? message,
    int? statusCode,
    String? error,
  ]) =>
      <String, dynamic>{
        'success': success,
        if (message != null) 'message': message,
        if (error != null) 'error': error,
        if (statusCode != null) 'statusCode': statusCode,
      };

  /// 处理 Dio 响应，判断是否成功。
  ///
  /// 成功条件：HTTP 状态码为 200/201，或响应体包含 `success: true`。
  bool _isSuccess(Response response) {
    final status = response.statusCode;
    if (status == 200 || status == 201) {
      return true;
    }
    final data = response.data;
    if (data is Map && data['success'] == true) {
      return true;
    }
    return false;
  }

  /// 处理 Dio 异常，返回错误信息。
  String _handleError(DioException e) {
    final message = e.message ?? 'Unknown error';
    final type = e.type;
    switch (type) {
      case DioExceptionType.connectionTimeout:
        return '连接超时';
      case DioExceptionType.receiveTimeout:
        return '接收超时';
      case DioExceptionType.sendTimeout:
        return '发送超时';
      case DioExceptionType.badResponse:
        return '服务器返回错误状态码 (${e.response?.statusCode})';
      case DioExceptionType.cancel:
        return '请求已取消';
      case DioExceptionType.badCertificate:
        return '证书错误';
      case DioExceptionType.unknown:
      default:
        return message;
    }
  }
}

/// NoIP 服务商适配器。
///
/// 后端 API：
/// - 更新：`POST https://api.noip.com/noip/1.1/domain/update`
/// - 状态：`GET https://api.noip.com/noip/1.1/domain/get`
class NoIPAdapter extends DDNSServiceAdapter {
  NoIPAdapter({Dio? dioInstance, Logger? logger})
      : super('no-ip', dioInstance: dioInstance, logger: logger);

  @override
  Future<Map<String, dynamic>> update(DDNSConfig config) async {
    final domain = config.hostname;
    final domainId = config.updateRequestConfig['domain_id'] as String?;
    final username = config.updateRequestConfig['username'] as String?;
    final ip = config.updateRequestConfig['ip'] as String?;

    if (domainId == null || username == null || ip == null) {
      return buildResult(
          false, null, null, 'Missing required fields for NoIP update');
    }

    try {
      final response = await _dio.post(
        'https://api.noip.com/noip/1.1/domain/update',
        data: <String, dynamic>{
          'domainName': domain,
          'domainId': domainId,
          'username': username,
          'password': config.apiKey,
          'protocol': 'udp',
          'address': ip,
        },
      );

      if (_isSuccess(response)) {
        _logger.i('NoIP update successful');
        return buildResult(true, 'NoIP update successful', response.statusCode);
      }

      return buildResult(
          false, null, response.statusCode, 'NoIP update failed');
    } on DioException catch (e) {
      _logger.w('NoIP update failed: ${_handleError(e)}');
      return buildResult(
          false, null, null, 'NoIP update failed: ${_handleError(e)}');
    }
  }

  @override
  Future<bool> checkStatus(DDNSConfig config) async {
    try {
      final response = await _dio.get(
        'https://api.noip.com/noip/1.1/domain/get',
        queryParameters: <String, dynamic>{
          'domainName': config.hostname,
          'domainId': config.updateRequestConfig['domain_id'],
          'username': config.updateRequestConfig['username'],
          'password': config.apiKey,
          'protocol': 'udp',
        },
      );
      final data = response.data;
      if (data is Map) {
        final success = data['success'];
        return success == true || success.toString().toLowerCase() == 'true';
      }
      return false;
    } on DioException catch (e) {
      _logger.w('NoIP status check failed: ${_handleError(e)}');
      return false;
    }
  }
}

/// DuckDNS 服务商适配器。
///
/// 后端 API：
/// - 更新：`POST https://www.duckdns.org/update`
/// - 状态：`GET https://www.duckdns.org/query`
class DuckDNSAdapter extends DDNSServiceAdapter {
  DuckDNSAdapter({Dio? dioInstance, Logger? logger})
      : super('duckdns', dioInstance: dioInstance, logger: logger);

  @override
  Future<Map<String, dynamic>> update(DDNSConfig config) async {
    final token = config.apiKey;
    final subdomain = config.hostname;
    final ip = config.updateRequestConfig['ip'] as String?;

    if (ip == null) {
      return buildResult(
          false, null, null, 'Missing required fields for DuckDNS update');
    }

    try {
      final isIPv6 =
          config.updateRequestConfig['ip_type']?.toString().toLowerCase() ==
              'ipv6';
      final response = await _dio.post(
        'https://www.duckdns.org/update',
        data: <String, dynamic>{
          'domains': subdomain,
          'token': token,
          if (isIPv6) 'ipv6': ip else 'ip': ip,
        },
      );

      if (response.statusCode == 200) {
        _logger.i('DuckDNS update successful');
        return buildResult(
            true, 'DuckDNS update successful', response.statusCode);
      }

      return buildResult(
          false, null, response.statusCode, 'DuckDNS update failed');
    } on DioException catch (e) {
      _logger.w('DuckDNS update failed: ${_handleError(e)}');
      return buildResult(
          false, null, null, 'DuckDNS update failed: ${_handleError(e)}');
    }
  }

  @override
  Future<bool> checkStatus(DDNSConfig config) async {
    try {
      final response = await _dio.get(
        'https://www.duckdns.org/query',
        queryParameters: <String, dynamic>{
          'tokens': config.apiKey,
          'domains': config.hostname,
        },
      );
      return response.statusCode == 200;
    } on DioException catch (e) {
      _logger.w('DuckDNS status check failed: ${_handleError(e)}');
      return false;
    }
  }
}

/// UpIvY 服务商适配器。
///
/// 后端 API：
/// - 更新：`POST https://ipv4.upvy.net/json`
/// - 状态：`GET https://ipv4.upvy.net/status`
class UpIvYAdapter extends DDNSServiceAdapter {
  UpIvYAdapter({Dio? dioInstance, Logger? logger})
      : super('upivy', dioInstance: dioInstance, logger: logger);

  @override
  Future<Map<String, dynamic>> update(DDNSConfig config) async {
    final domain = config.hostname;
    final username = config.updateRequestConfig['username'] as String?;
    final password = config.apiKey;
    final ip = config.updateRequestConfig['ip'] as String?;

    if (username == null || ip == null) {
      return buildResult(
          false, null, null, 'Missing required fields for UpIvY update');
    }

    try {
      final response = await _dio.post(
        'https://ipv4.upvy.net/json',
        data: <String, dynamic>{
          'domain': domain,
          'username': username,
          'password': password,
          'ip': ip,
        },
      );

      if (_isSuccess(response)) {
        _logger.i('UpIvY update successful');
        return buildResult(
            true, 'UpIvY update successful', response.statusCode);
      }

      return buildResult(
          false, null, response.statusCode, 'UpIvY update failed');
    } on DioException catch (e) {
      _logger.w('UpIvY update failed: ${_handleError(e)}');
      return buildResult(
          false, null, null, 'UpIvY update failed: ${_handleError(e)}');
    }
  }

  @override
  Future<bool> checkStatus(DDNSConfig config) async {
    try {
      final response = await _dio.get('https://ipv4.upvy.net/status');
      final data = response.data;
      return data is Map && data['ip'] != null;
    } on DioException catch (e) {
      _logger.w('UpIvY status check failed: ${_handleError(e)}');
      return false;
    }
  }
}

/// Cloudflare 服务商适配器。
///
/// 后端 API：
/// - 更新：`PUT https://api.cloudflare.com/client/v4/zones/{zone_id}/dns_records/{record_id}`
/// - 状态：`GET https://api.cloudflare.com/client/v4/user/zones`
class CloudflareAdapter extends DDNSServiceAdapter {
  CloudflareAdapter({Dio? dioInstance, Logger? logger})
      : super('cloudflare', dioInstance: dioInstance, logger: logger);

  @override
  Future<Map<String, dynamic>> update(DDNSConfig config) async {
    final zoneId = config.updateRequestConfig['zone_id'] as String?;
    final recordId = config.updateRequestConfig['record_id'] as String?;
    final ip = config.updateRequestConfig['ip'] as String?;

    if (zoneId == null || recordId == null || ip == null) {
      return buildResult(
          false, null, null, 'Missing required fields for Cloudflare update');
    }

    try {
      final response = await _dio.put(
        'https://api.cloudflare.com/client/v4/zones/$zoneId/dns_records/$recordId',
        data: <String, dynamic>{
          'type': config.updateRequestConfig['type'] ?? 'A',
          'name': config.updateRequestConfig['name'] ?? config.hostname,
          'content': ip,
          if (config.updateRequestConfig['ttl'] != null)
            'ttl': config.updateRequestConfig['ttl'],
          if (config.updateRequestConfig['proxied'] != null)
            'proxied': config.updateRequestConfig['proxied'],
        },
        options: Options(
          headers: <String, dynamic>{
            'X-Auth-Email': config.apiKey,
            'X-Auth-Key':
                config.updateRequestConfig['api_key'] ?? config.apiKey,
            'Content-Type': 'application/json',
          },
        ),
      );

      if (_isSuccess(response)) {
        _logger.i('Cloudflare update successful');
        return buildResult(
            true, 'Cloudflare update successful', response.statusCode);
      }

      return buildResult(
          false, null, response.statusCode, 'Cloudflare update failed');
    } on DioException catch (e) {
      _logger.w('Cloudflare update failed: ${_handleError(e)}');
      return buildResult(
          false, null, null, 'Cloudflare update failed: ${_handleError(e)}');
    }
  }

  @override
  Future<bool> checkStatus(DDNSConfig config) async {
    try {
      final zoneId = config.updateRequestConfig['zone_id'] as String?;
      final recordId = config.updateRequestConfig['record_id'] as String?;
      if (zoneId == null || recordId == null) return false;
      final response = await _dio.get(
        'https://api.cloudflare.com/client/v4/zones/$zoneId/dns_records/$recordId',
        options: Options(
          headers: <String, dynamic>{
            'X-Auth-Email': config.apiKey,
            'X-Auth-Key':
                config.updateRequestConfig['api_key'] ?? config.apiKey,
          },
        ),
      );
      final data = response.data;
      return data is Map && data['result'] is List;
    } on DioException catch (e) {
      _logger.w('Cloudflare status check failed: ${_handleError(e)}');
      return false;
    }
  }
}

/// 自定义 API 服务商适配器（Generic）。
///
/// 后端 API：
/// - 更新/状态：可配置的端点，支持 GET/POST
/// - 成功条件：HTTP 状态码 200/201，或响应体包含 `success: true`
class CustomAPIAdapter extends DDNSServiceAdapter {
  CustomAPIAdapter({Dio? dioInstance, Logger? logger})
      : super('custom_api', dioInstance: dioInstance, logger: logger);

  @override
  Future<Map<String, dynamic>> update(DDNSConfig config) async {
    try {
      final method = config.updateRequestConfig['method'] as String? ?? 'POST';
      final payload = <String, dynamic>{
        ...config.updateRequestConfig,
        'hostname': config.hostname,
        'ip': config.updateRequestConfig['ip'],
      }..remove('method');
      final response = await _dio.request(
        config.apiUrl,
        data: method.toUpperCase() == 'GET' ? null : payload,
        queryParameters: <String, dynamic>{
          'ip_type': config.updateRequestConfig['ip_type'],
          'interval': config.updateRequestConfig['interval'],
          if (method.toUpperCase() == 'GET') ...payload,
        },
        options: Options(
          method: method,
          headers: <String, dynamic>{
            'Authorization': 'Bearer ${config.apiKey}',
            'Content-Type': 'application/json',
          },
        ),
      );

      if (_isSuccess(response)) {
        _logger.i('Custom API update successful');
        return buildResult(
            true, 'Custom API update successful', response.statusCode);
      }

      return buildResult(
          false, null, response.statusCode, 'Custom API update failed');
    } on DioException catch (e) {
      _logger.w('Custom API update failed: ${_handleError(e)}');
      return buildResult(
          false, null, null, 'Custom API update failed: ${_handleError(e)}');
    }
  }

  @override
  Future<bool> checkStatus(DDNSConfig config) async {
    try {
      final method = config.updateRequestConfig['method'] as String? ?? 'GET';
      final response = await _dio.request(
        config.apiUrl,
        queryParameters: <String, dynamic>{
          'hostname': config.hostname,
          'ip_type': config.updateRequestConfig['ip_type'],
          'interval': config.updateRequestConfig['interval'],
        },
        options: Options(
          method: method,
          headers: <String, dynamic>{
            'Authorization': 'Bearer ${config.apiKey}',
          },
        ),
      );
      return _isSuccess(response);
    } on DioException catch (e) {
      _logger.w('Custom API status check failed: ${_handleError(e)}');
      return false;
    }
  }
}

/// 根据服务商类型创建对应的适配器实例。
///
/// [type] 为服务商类型，若为未知类型则返回 [CustomAPIAdapter]。
///
/// [dioInstance] 为可选的 Dio 实例，用于测试注入或自定义配置。
DDNSServiceAdapter createAdapter(String type, {Dio? dioInstance}) {
  final normalizedType = type.trim().toLowerCase();
  switch (normalizedType) {
    case 'no-ip':
    case 'noip':
      return NoIPAdapter(dioInstance: dioInstance);
    case 'duckdns':
      return DuckDNSAdapter(dioInstance: dioInstance);
    case 'upivy':
    case 'upivyservice':
      return UpIvYAdapter(dioInstance: dioInstance);
    case 'cloudflare':
      return CloudflareAdapter(dioInstance: dioInstance);
    case 'custom_api':
    case 'custom':
    case 'generic':
    case '':
      return CustomAPIAdapter(dioInstance: dioInstance);
    default:
      Logger()
          .w('Unknown DDNS service type "$type", falling back to CustomAPI');
      return CustomAPIAdapter(dioInstance: dioInstance);
  }
}
