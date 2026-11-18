// d:\projectfile\Fluterproject\nebulaDDNSA\lib\services\ip_resolver.dart
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:logger/logger.dart';

import 'public_ip_addresses.dart';

class IpNetworkRange {
  final InternetAddress network;
  final int prefixLength;

  const IpNetworkRange(this.network, this.prefixLength);

  factory IpNetworkRange.parse(String value) {
    final parts = value.trim().split('/');
    if (parts.length > 2 || parts.first.isEmpty) {
      throw FormatException('Invalid IP network range: $value');
    }

    final network = InternetAddress.tryParse(parts.first);
    if (network == null) {
      throw FormatException('Invalid IP address in network range: $value');
    }
    final addressBits = network.type == InternetAddressType.IPv4 ? 32 : 128;
    final prefixLength = parts.length == 1
        ? addressBits
        : int.tryParse(parts[1]);
    if (prefixLength == null ||
        prefixLength < 0 ||
        prefixLength > addressBits) {
      throw FormatException('Invalid prefix length in network range: $value');
    }
    return IpNetworkRange(network, prefixLength);
  }

  bool contains(InternetAddress address) {
    if (address.type != network.type) return false;
    final networkBytes = network.rawAddress;
    final addressBytes = address.rawAddress;
    final fullBytes = prefixLength ~/ 8;
    for (var index = 0; index < fullBytes; index++) {
      if (networkBytes[index] != addressBytes[index]) return false;
    }

    final remainingBits = prefixLength % 8;
    if (remainingBits == 0) return true;
    final mask = (0xff << (8 - remainingBits)) & 0xff;
    return (networkBytes[fullBytes] & mask) == (addressBytes[fullBytes] & mask);
  }

  String get normalized => '${network.address}/$prefixLength';
}

class NetworkPathBlockedException implements Exception {
  final String reason;

  const NetworkPathBlockedException(this.reason);

  @override
  String toString() => reason;
}

class NetworkPathGuard {
  static const _proxyEnvironmentKeys = {
    'HTTP_PROXY',
    'HTTPS_PROXY',
    'ALL_PROXY',
    'FTP_PROXY',
  };
  static final _vpnInterfacePattern = RegExp(
    r'\b(?:tun|tap|ppp|wg|utun|wintun|wireguard|openvpn|tailscale|zerotier|vpn|nordlynx|anyconnect|proton|mullvad|expressvpn|surfshark|clash|sing-box|v2ray|shadowsocks)\w*\b',
    caseSensitive: false,
  );

  final Map<String, String> _environment;
  final Future<List<String>> Function() _interfaceNames;

  NetworkPathGuard({
    Map<String, String>? environment,
    Future<List<String>> Function()? interfaceNames,
  }) : _environment = environment ?? Platform.environment,
       _interfaceNames = interfaceNames ?? _loadInterfaceNames;

  Future<String?> findProxyOrVpn() async {
    for (final entry in _environment.entries) {
      if (_proxyEnvironmentKeys.contains(entry.key.toUpperCase()) &&
          entry.value.trim().isNotEmpty) {
        return '检测到代理环境变量 ${entry.key}';
      }
    }

    final interfaces = await _interfaceNames();
    for (final name in interfaces) {
      if (_vpnInterfacePattern.hasMatch(name)) {
        return '检测到疑似 VPN/代理网络接口：$name';
      }
    }
    return null;
  }

  static Future<List<String>> _loadInterfaceNames() async {
    final interfaces = await NetworkInterface.list();
    return interfaces.map((interface) => interface.name).toList();
  }
}

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
  final NetworkPathGuard _networkPathGuard;
  final Future<List<String>> Function() _customInternalRangesProvider;
  final Future<List<String>> Function() _customIPv4QueryEndpointsProvider;
  final Future<List<String>> Function() _customIPv6QueryEndpointsProvider;
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
    NetworkPathGuard? networkPathGuard,
    Future<List<String>> Function()? customInternalRangesProvider,
    Future<List<String>> Function()? customIPv4QueryEndpointsProvider,
    Future<List<String>> Function()? customIPv6QueryEndpointsProvider,
  }) : _dio =
           dioInstance ??
           Dio(
             BaseOptions(
               connectTimeout: timeout ?? const Duration(seconds: 10),
               receiveTimeout: timeout ?? const Duration(seconds: 10),
             ),
           ),
       _logger = logger ?? Logger(),
       _networkPathGuard = networkPathGuard ?? NetworkPathGuard(),
       _customInternalRangesProvider =
           customInternalRangesProvider ?? _emptyInternalRanges,
       _customIPv4QueryEndpointsProvider =
           customIPv4QueryEndpointsProvider ?? _emptyInternalRanges,
       _customIPv6QueryEndpointsProvider =
           customIPv6QueryEndpointsProvider ?? _emptyInternalRanges,
       _queryEndpoints =
           queryEndpoints ??
           const [
             'https://api.ipify.org',
             'https://ipv4.icanhazip.com',
             'https://api64.ipify.org',
             'https://4.ipw.cn',
           ];

  /// 解析公共 IPv4 地址。
  ///
  /// 返回地址字符串，若解析失败则返回 null。
  Future<String?> resolveIPv4() async {
    final internalRanges = await _loadCustomInternalRanges();
    final customEndpoints = (await _customIPv4QueryEndpointsProvider())
        .toSet()
        .toList();
    if (customEndpoints.isNotEmpty) {
      final results = await Future.wait(
        customEndpoints.map((endpoint) async {
          try {
            final response = await _dio.get(endpoint);
            final value = response.data.toString().trim();
            final address = InternetAddress.tryParse(value);
            if (address?.type != InternetAddressType.IPv4 ||
                _isInInternalRange(address!, internalRanges)) {
              _logger.w('Rejected non-public IPv4 response from $endpoint');
              return null;
            }
            return address.address;
          } catch (error) {
            _logger.w('IPv4 lookup failed at $endpoint: $error');
            return null;
          }
        }),
      );
      final resolved = _selectConsistentResult(
        results,
        minimumResponses: customEndpoints.length == 1 ? 1 : 2,
        label: 'IPv4',
      );
      if (resolved != null) _hasResolvedIPv4 = true;
      return resolved;
    }

    for (final endpoint in _queryEndpoints) {
      try {
        final response = await _dio.get(endpoint);
        final value = response.data.toString().trim();
        final address = InternetAddress.tryParse(value);
        if (address?.type == InternetAddressType.IPv4 &&
            !_isInInternalRange(address!, internalRanges)) {
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
    return resolveVerifiedPublicIPv6();
  }

  /// Requires configured IPv6 lookup endpoints to agree on a global
  /// unicast address before using it.
  Future<String?> resolveVerifiedPublicIPv6() async {
    await ensureNoProxyOrVpn();
    final internalRanges = await _loadCustomInternalRanges();
    final customEndpoints = (await _customIPv6QueryEndpointsProvider())
        .toSet()
        .toList();
    final endpoints = customEndpoints.isEmpty
        ? const [
            'https://api6.ipify.org',
            'https://ipv6.icanhazip.com',
            'https://6.ipw.cn',
          ]
        : customEndpoints;
    final results = await Future.wait(
      endpoints.map((endpoint) async {
        try {
          final response = await _dio.get(endpoint);
          final value = response.data.toString().trim();
          final address = InternetAddress.tryParse(value);
          if (address?.type != InternetAddressType.IPv6 ||
              !_isGlobalUnicastIPv6(address!) ||
              _isInInternalRange(address, internalRanges)) {
            _logger.w('Rejected non-public IPv6 response from $endpoint');
            return null;
          }
          return address.address;
        } catch (error) {
          _logger.w('IPv6 verification failed at $endpoint: $error');
          return null;
        }
      }),
    );

    final resolved = _selectConsistentResult(
      results,
      minimumResponses: endpoints.length == 1 ? 1 : 2,
      label: 'IPv6',
    );
    if (resolved != null) _hasResolvedIPv6 = true;
    return resolved;
  }

  String? _selectConsistentResult(
    List<String?> results, {
    required int minimumResponses,
    required String label,
  }) {
    final addresses = results.whereType<String>().toSet();
    final successfulResults = results.whereType<String>().length;
    if (successfulResults < minimumResponses || addresses.length != 1) {
      _logger.w('$label lookup results were insufficient or inconsistent');
      return null;
    }
    return addresses.single;
  }

  Future<PublicIPAddresses> resolvePublicIPs() async {
    await ensureNoProxyOrVpn();
    final results = await Future.wait<String?>([
      resolveIPv4(),
      resolveVerifiedPublicIPv6(),
    ]);
    return PublicIPAddresses(ipv4: results[0], ipv6: results[1]);
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

  /// 阻止在已知代理或 VPN 网络路径下使用出口 IP 更新 DDNS。
  Future<void> ensureNoProxyOrVpn() async {
    final reason = await _networkPathGuard.findProxyOrVpn();
    if (reason != null) {
      clearCache();
      throw NetworkPathBlockedException('$reason；为避免解析到代理出口 IP，请关闭代理/VPN 后重试');
    }
  }

  Future<List<IpNetworkRange>> _loadCustomInternalRanges() async =>
      (await _customInternalRangesProvider())
          .map(IpNetworkRange.parse)
          .toList(growable: false);

  bool _isInInternalRange(
    InternetAddress address,
    List<IpNetworkRange> ranges,
  ) => ranges.any((range) => range.contains(address));

  bool _isGlobalUnicastIPv6(InternetAddress address) {
    final bytes = address.rawAddress;
    if (address.type != InternetAddressType.IPv6 || (bytes[0] & 0xe0) != 0x20) {
      return false;
    }
    return !const [
      '2001:db8::/32',
      '2001::/23',
      '2002::/16',
      '3fff::/20',
    ].map(IpNetworkRange.parse).any((range) => range.contains(address));
  }

  static Future<List<String>> _emptyInternalRanges() async => const [];

  /// 解析公共 IP 地址（自动检测 IPv4/IPv6）。
  ///
  /// 优先返回 IPv6 地址（若支持），否则返回 IPv4 地址。
  ///
  /// 返回纯 IP 字符串（如 `203.0.113.5` 或 `2001:db8::1`），不含类型后缀。
  ///
  /// 若无法解析，抛出 [Exception]。
  Future<String> resolvePublicIP({bool forceRefresh = false}) async {
    if (forceRefresh) clearCache();
    await ensureNoProxyOrVpn();
    final internalRanges = await _loadCustomInternalRanges();

    // 检查缓存
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_cachedIP != null &&
        _cachedIPTime != null &&
        (now - _cachedIPTime!.millisecondsSinceEpoch) < _cacheDuration) {
      final cachedAddress = InternetAddress.tryParse(_cachedIP!);
      if (cachedAddress != null &&
          !_isInInternalRange(cachedAddress, internalRanges)) {
        _logger.i('Using cached IP: $_cachedIP');
        return _cachedIP!;
      }
      clearCache();
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
