import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_ddns/services/ip_resolver.dart';

class _IPv4Adapter implements HttpClientAdapter {
  int requestCount = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestCount++;
    final path = options.path;
    final body = path.contains('api64') ? '' : '203.0.113.10';
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        HttpHeaders.contentTypeHeader: ['text/plain'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _ChinaFallbackAdapter implements HttpClientAdapter {
  final List<String> requestedHosts = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestedHosts.add(options.uri.host);
    final body = options.uri.host == '4.ipw.cn' ? '203.0.113.20' : '';
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        HttpHeaders.contentTypeHeader: ['text/plain'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _IPv6ConsensusAdapter implements HttpClientAdapter {
  final Map<String, String> responses;
  final List<String> requestedHosts = [];

  _IPv6ConsensusAdapter(this.responses);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestedHosts.add(options.uri.host);
    return ResponseBody.fromString(
      responses[options.uri.host] ?? '',
      200,
      headers: {
        HttpHeaders.contentTypeHeader: ['text/plain'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('resolves and caches a public IPv4 address', () async {
    final dio = Dio();
    final adapter = _IPv4Adapter();
    dio.httpClientAdapter = adapter;
    final resolver = IPResolver(
      dioInstance: dio,
      networkPathGuard: NetworkPathGuard(
        environment: const {},
        interfaceNames: () async => [],
      ),
    );

    expect(await resolver.resolvePublicIP(), '203.0.113.10');
    expect(await resolver.resolvePublicIP(), '203.0.113.10');
    final requestCountAfterCacheHit = adapter.requestCount;
    expect(await resolver.resolvePublicIP(forceRefresh: true), '203.0.113.10');
    expect(adapter.requestCount, greaterThan(requestCountAfterCacheHit));
  });

  test('falls back to the regional IPv4 endpoint', () async {
    final dio = Dio();
    final adapter = _ChinaFallbackAdapter();
    dio.httpClientAdapter = adapter;
    final resolver = IPResolver(
      dioInstance: dio,
      networkPathGuard: NetworkPathGuard(
        environment: const {},
        interfaceNames: () async => [],
      ),
    );

    expect(await resolver.resolvePublicIP(), '203.0.113.20');
    expect(adapter.requestedHosts, contains('4.ipw.cn'));
  });

  test('compares all configured IPv4 query endpoints', () async {
    final dio = Dio();
    dio.httpClientAdapter = _IPv6ConsensusAdapter({
      'v4-a.example': '198.51.100.20',
      'v4-b.example': '198.51.100.20',
    });
    final resolver = IPResolver(
      dioInstance: dio,
      networkPathGuard: NetworkPathGuard(
        environment: const {},
        interfaceNames: () async => [],
      ),
      customIPv4QueryEndpointsProvider: () async => [
        'https://v4-a.example/ip',
        'https://v4-b.example/ip',
      ],
    );

    expect(await resolver.resolveIPv4(), '198.51.100.20');
  });

  test('uses a single configured IPv4 query endpoint', () async {
    final dio = Dio();
    dio.httpClientAdapter = _IPv6ConsensusAdapter({
      'my-ip.example': '198.51.100.20',
    });
    final resolver = IPResolver(
      dioInstance: dio,
      networkPathGuard: NetworkPathGuard(
        environment: const {},
        interfaceNames: () async => [],
      ),
      customIPv4QueryEndpointsProvider: () async => [
        'https://my-ip.example/ip',
      ],
    );

    expect(await resolver.resolveIPv4(), '198.51.100.20');
  });

  test('rejects conflicting custom IPv4 query results', () async {
    final dio = Dio();
    dio.httpClientAdapter = _IPv6ConsensusAdapter({
      'v4-a.example': '198.51.100.20',
      'v4-b.example': '198.51.100.21',
    });
    final resolver = IPResolver(
      dioInstance: dio,
      networkPathGuard: NetworkPathGuard(
        environment: const {},
        interfaceNames: () async => [],
      ),
      customIPv4QueryEndpointsProvider: () async => [
        'https://v4-a.example/ip',
        'https://v4-b.example/ip',
      ],
    );

    expect(await resolver.resolveIPv4(), isNull);
  });

  test(
    'blocks lookups when a proxy environment variable is configured',
    () async {
      final dio = Dio();
      final adapter = _IPv4Adapter();
      dio.httpClientAdapter = adapter;
      final resolver = IPResolver(
        dioInstance: dio,
        networkPathGuard: NetworkPathGuard(
          environment: const {'https_proxy': 'http://127.0.0.1:8080'},
          interfaceNames: () async => [],
        ),
      );

      await expectLater(
        resolver.resolvePublicIP(),
        throwsA(isA<NetworkPathBlockedException>()),
      );
      expect(adapter.requestCount, 0);
    },
  );

  test('blocks lookups when a VPN interface is active', () async {
    final dio = Dio();
    final adapter = _IPv4Adapter();
    dio.httpClientAdapter = adapter;
    final resolver = IPResolver(
      dioInstance: dio,
      networkPathGuard: NetworkPathGuard(
        environment: const {},
        interfaceNames: () async => ['Ethernet', 'WireGuard Tunnel'],
      ),
    );

    await expectLater(
      resolver.resolvePublicIP(),
      throwsA(isA<NetworkPathBlockedException>()),
    );
    expect(adapter.requestCount, 0);
  });

  test('does not reuse a cached IP after a VPN becomes active', () async {
    var vpnActive = false;
    final dio = Dio();
    final adapter = _IPv4Adapter();
    dio.httpClientAdapter = adapter;
    final resolver = IPResolver(
      dioInstance: dio,
      networkPathGuard: NetworkPathGuard(
        environment: const {},
        interfaceNames: () async =>
            vpnActive ? ['WireGuard Tunnel'] : ['Ethernet'],
      ),
    );

    expect(await resolver.resolvePublicIP(), '203.0.113.10');
    final requestCountBeforeVpn = adapter.requestCount;
    vpnActive = true;

    await expectLater(
      resolver.resolvePublicIP(),
      throwsA(isA<NetworkPathBlockedException>()),
    );
    expect(adapter.requestCount, requestCountBeforeVpn);
  });

  test(
    'accepts a global IPv6 address only when lookup sources agree',
    () async {
      final dio = Dio();
      final adapter = _IPv6ConsensusAdapter({
        'api6.ipify.org': '2606:4700:4700::1111',
        'ipv6.icanhazip.com': '2606:4700:4700::1111',
        '6.ipw.cn': '2606:4700:4700::1111',
      });
      dio.httpClientAdapter = adapter;
      final resolver = IPResolver(
        dioInstance: dio,
        networkPathGuard: NetworkPathGuard(
          environment: const {},
          interfaceNames: () async => [],
        ),
      );

      expect(
        await resolver.resolveVerifiedPublicIPv6(),
        '2606:4700:4700::1111',
      );
      expect(adapter.requestedHosts.toSet(), {
        'api6.ipify.org',
        'ipv6.icanhazip.com',
        '6.ipw.cn',
      });
    },
  );

  test(
    'accepts matching IPv6 results if one lookup source is unavailable',
    () async {
      final dio = Dio();
      dio.httpClientAdapter = _IPv6ConsensusAdapter({
        'api6.ipify.org': '240e:398:5787:5060:d1e:d190:b897:2089',
        'ipv6.icanhazip.com': '240e:398:5787:5060:d1e:d190:b897:2089',
        '6.ipw.cn': '',
      });
      final resolver = IPResolver(
        dioInstance: dio,
        networkPathGuard: NetworkPathGuard(
          environment: const {},
          interfaceNames: () async => [],
        ),
      );

      expect(
        await resolver.resolveVerifiedPublicIPv6(),
        '240e:398:5787:5060:d1e:d190:b897:2089',
      );
    },
  );

  test('uses a single configured IPv6 query endpoint', () async {
    final dio = Dio();
    dio.httpClientAdapter = _IPv6ConsensusAdapter({
      'my-ip.example': '240e:398:5787:5060:d1e:d190:b897:2089',
    });
    final resolver = IPResolver(
      dioInstance: dio,
      networkPathGuard: NetworkPathGuard(
        environment: const {},
        interfaceNames: () async => [],
      ),
      customIPv6QueryEndpointsProvider: () async => [
        'https://my-ip.example/ip',
      ],
    );

    expect(
      await resolver.resolveVerifiedPublicIPv6(),
      '240e:398:5787:5060:d1e:d190:b897:2089',
    );
  });

  test(
    'rejects IPv6 results when any valid configured source disagrees',
    () async {
      final dio = Dio();
      dio.httpClientAdapter = _IPv6ConsensusAdapter({
        'v6-a.example': '2606:4700:4700::1111',
        'v6-b.example': '2606:4700:4700::1111',
        'v6-c.example': '2606:4700:4700::1001',
      });
      final resolver = IPResolver(
        dioInstance: dio,
        networkPathGuard: NetworkPathGuard(
          environment: const {},
          interfaceNames: () async => [],
        ),
        customIPv6QueryEndpointsProvider: () async => [
          'https://v6-a.example/ip',
          'https://v6-b.example/ip',
          'https://v6-c.example/ip',
        ],
      );

      expect(await resolver.resolveVerifiedPublicIPv6(), isNull);
    },
  );

  test('returns IPv4 and IPv6 together for dashboard display', () async {
    final dio = Dio();
    dio.httpClientAdapter = _IPv6ConsensusAdapter({
      'api.ipify.org': '198.51.100.20',
      'api6.ipify.org': '2606:4700:4700::1111',
      '6.ipw.cn': '2606:4700:4700::1111',
    });
    final resolver = IPResolver(
      dioInstance: dio,
      networkPathGuard: NetworkPathGuard(
        environment: const {},
        interfaceNames: () async => [],
      ),
    );

    final addresses = await resolver.resolvePublicIPs();

    expect(addresses.ipv4, '198.51.100.20');
    expect(addresses.ipv6, '2606:4700:4700::1111');
  });

  test('rejects private and user-excluded IPv6 ranges', () async {
    for (final address in ['fd12:3456::1', '2606:4700:4700::1111']) {
      final dio = Dio();
      final adapter = _IPv6ConsensusAdapter({
        'api6.ipify.org': address,
        '6.ipw.cn': address,
      });
      dio.httpClientAdapter = adapter;
      final resolver = IPResolver(
        dioInstance: dio,
        networkPathGuard: NetworkPathGuard(
          environment: const {},
          interfaceNames: () async => [],
        ),
        customInternalRangesProvider: () async =>
            address.startsWith('2606:') ? ['2606:4700:4700::/48'] : const [],
      );

      expect(await resolver.resolveVerifiedPublicIPv6(), isNull);
    }
  });

  test('rejects IPv6 results that disagree between endpoints', () async {
    final dio = Dio();
    dio.httpClientAdapter = _IPv6ConsensusAdapter({
      'api6.ipify.org': '2606:4700:4700::1111',
      '6.ipw.cn': '2606:4700:4700::1001',
    });
    final resolver = IPResolver(
      dioInstance: dio,
      networkPathGuard: NetworkPathGuard(
        environment: const {},
        interfaceNames: () async => [],
      ),
    );

    expect(await resolver.resolveVerifiedPublicIPv6(), isNull);
  });
}
