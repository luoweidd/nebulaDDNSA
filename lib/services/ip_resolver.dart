// d:\projectfile\Fluterproject\nebulaDDNSA\lib\services\ip_resolver.dart
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:logger/logger.dart';

/// IPResolver：跨平台公共 IP 地址解析服务。
///
/// 企业级特性：
/// - 自动检测 IPv4 / IPv6 地址类型
/// - 支持多个公共 IP 查询端点（冗余与故障转移）
/// - 使用 Dio 进行 HTTP 请求（与企业级 HTTP 栈一致）
/// - 完善的错误处理和超时控制
/// - 结果缓存以提高性能
class IPResolver {
  final Dio _dio;
  final Logger _logger;
  final List<String> _queryEndpoints;
  bool _hasResolvedIPv6 = false;
  bool _hasResolvedIPv4 = false;

  /// IP 解析结果缓存
  String? _cachedIP;
  DateTime? _cachedIPTime;
  static const int _cacheDuration = 30 * 60 * 1000; // 30 分钟

  IPResolver({
    Dio? dioInstance,
    Logger? logger,
    List<String>? queryEndpoints,
    Duration? timeout,
  })  : _dio = dioInstance ??
            Dio(BaseOptions(
              connectTimeout: timeout ?? const Duration(seconds: 10),
              receiveTimeout: timeout ?? const Duration(seconds: 10),
            )),
        _logger = logger ?? Logger(),
        _queryEndpoints = queryEndpoints ??
            const [
              'https://api.ipify.org',
              'https://ipv4.icanhazip.com',
              'https://api64.ipify.org',
            ];

  /// 解析公共 IPv4 地址。
  ///
  /// 返回地址字符串，若解析失败则返回 null。
  Future<String?> resolveIPv4() async {
    for (final endpoint in _queryEndpoints) {
      try {
        final response = await _dio.get(endpoint);
        final value = response.data.toString().trim();
        final address = InternetAddress.tryParse(value);
        if (address?.type == InternetAddressType.IPv4) {
          _hasResolvedIPv4 = true;
          return value;
        }
      } catch (error) {
        _logger.w('IPv4 lookup failed at $endpoint: $error');
      }
    }
    return null;
  }

  /// 解析公共 IPv6 地址。
  ///
  /// 返回地址字符串，若解析失败则返回 null。
  Future<String?> resolveIPv6() async {
    try {
      final response = await _dio.get('https://api64.ipify.org');
      final value = response.data.toString().trim();
      final address = InternetAddress.tryParse(value);
      if (address?.type != InternetAddressType.IPv6) return null;
      _hasResolvedIPv6 = true;
      return value;
    } catch (e) {
      _logger.w('IPv6 remote resolution failed: $e');
      return null;
    }
  }

  /// 检测当前网络接口是否支持 IPv6。
  bool get supportsIPv6 => _hasResolvedIPv6;

  /// 检测当前网络接口是否支持 IPv4。
  bool get supportsIPv4 => _hasResolvedIPv4;

  /// 解析本地接口 IP 地址（用于局域网 DDNS 场景）。
  ///
  /// 返回第一个非回环、非链路本地（169.254.x.x）的接口 IP。
  Future<String?> resolveLocalIP() async {
    final interfaces = await NetworkInterface.list();
    for (final interface in interfaces) {
      for (final ip in interface.addresses) {
        final address = ip.address;
        // 跳过回环地址 (127.0.0.0/8) 和链路本地地址 (169.254.0.0/16)
        if (address.startsWith('127.') || address.startsWith('169.254.')) {
          continue;
        }
        if (ip.type == InternetAddressType.IPv4) {
          return address;
        }
      }
    }
    return null;
  }

  /// 解析公共 IP 地址（自动检测 IPv4/IPv6）。
  ///
  /// 优先返回 IPv6 地址（若支持），否则返回 IPv4 地址。
  ///
  /// 返回纯 IP 字符串（如 `203.0.113.5` 或 `2001:db8::1`），不含类型后缀。
  ///
  /// 若无法解析，抛出 [Exception]。
  Future<String> resolvePublicIP() async {
    // 检查缓存
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_cachedIP != null &&
        _cachedIPTime != null &&
        (now - _cachedIPTime!.millisecondsSinceEpoch) < _cacheDuration) {
      _logger.i('Using cached IP: $_cachedIP');
      return _cachedIP!;
    }

    try {
      final ipv6 = await resolveIPv6();
      if (ipv6 != null) {
        _cacheResult(ipv6);
        _logger.i('Resolved public IPv6: $ipv6');
        return ipv6;
      }

      final ipv4 = await resolveIPv4();
      if (ipv4 != null) {
        _cacheResult(ipv4);
        _logger.i('Resolved public IPv4: $ipv4');
        return ipv4;
      }

      throw Exception('Unable to resolve public IP address');
    } catch (error) {
      _logger.e('Failed to resolve public IP: $error');
      rethrow;
    }
  }

  /// 缓存解析结果。
  void _cacheResult(String ip) {
    _cachedIP = ip;
    _cachedIPTime = DateTime.now();
  }

  /// 清除 IP 缓存。
  void clearCache() {
    _cachedIP = null;
    _cachedIPTime = null;
    _logger.i('IP cache cleared');
  }

  /// 获取所有网络接口的详细信息（用于调试和日志记录）。
  Future<List<Map<String, dynamic>>> getNetworkInterfaces() async {
    final interfaces = await NetworkInterface.list();
    return interfaces.map((interface) {
      return {
        'name': interface.name,
        'ipv4': interface.addresses
            .where((a) => a.type == InternetAddressType.IPv4)
            .map((a) => a.address),
        'ipv6': interface.addresses
            .where((a) => a.type == InternetAddressType.IPv6)
            .map((a) => a.address),
      };
    }).toList();
  }
}
