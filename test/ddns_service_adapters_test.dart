import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:nebula_ddns/config/ddns_config.dart';
import 'package:nebula_ddns/services/ddns_service_adapters.dart';

/// 自定义 mock adapter，返回可配置的响应。
class _MockAdapter implements HttpClientAdapter {
  final Map<String, dynamic> responseData;
  final int statusCode;
  final DioException? error;
  RequestOptions? lastRequestOptions;

  _MockAdapter({
    required this.responseData,
    required this.statusCode,
    required this.error,
  }) : super();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequestOptions = options;
    if (error != null) {
      throw error!;
    }
    return ResponseBody.fromString(
      jsonEncode(responseData),
      statusCode,
      headers: {
        HttpHeaders.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late Dio dio;

  DDNSConfig buildConfig(String serviceType, [Map<String, dynamic>? extra]) {
    return DDNSConfig(
      hostname: 'test.ddns.net',
      serviceType: serviceType,
      apiUrl: 'http://test.api/update',
      apiKey: 'test_key',
      updateRequestConfig: {
        'ip_type': 'ipv4',
        'interval': 300,
        ...?extra,
      },
      startOnSystemBoot: true,
    );
  }

  setUp(() {
    dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 10),
    ));
  });

  group('DDNSServiceAdapter Tests', () {
    test('createAdapter returns correct adapter type', () {
      expect(createAdapter('no-ip').type, 'no-ip');
      expect(createAdapter('duckdns').type, 'duckdns');
      expect(createAdapter('upivy').type, 'upivy');
      expect(createAdapter('cloudflare').type, 'cloudflare');
      expect(createAdapter('custom_api').type, 'custom_api');
      expect(createAdapter('unknown').type, 'custom_api');
    });

    test('NoIP adapter should return success on 200 with success=true', () async {
      dio.httpClientAdapter = _MockAdapter(
        responseData: {'success': 'true'},
        statusCode: 200,
        error: null,
      );

      final adapter = createAdapter('no-ip', dioInstance: dio);
      final result = await adapter.update(buildConfig('no-ip', {
        'domain_id': 'domain1',
        'username': 'test-user',
        'ip': '203.0.113.1',
      }));

      expect(result['success'], isTrue);
    });

    test('NoIP adapter should return failure on missing fields', () async {
      final adapter = createAdapter('no-ip', dioInstance: dio);
      final result = await adapter.update(buildConfig('no-ip', {'domain_id': null}));

      expect(result['success'], isFalse);
      expect(result['error'], contains('Missing required fields'));
    });

    test('DuckDNS adapter should return success on 200', () async {
      dio.httpClientAdapter = _MockAdapter(
        responseData: {},
        statusCode: 200,
        error: null,
      );

      final adapter = createAdapter('duckdns', dioInstance: dio);
      final result = await adapter.update(buildConfig(
        'duckdns',
        {'ip': '203.0.113.1'},
      ));

      expect(result['success'], isTrue);
    });

    test('DuckDNS adapter should return failure on non-200', () async {
      dio.httpClientAdapter = _MockAdapter(
        responseData: {},
        statusCode: 500,
        error: null,
      );

      final adapter = createAdapter('duckdns', dioInstance: dio);
      final result = await adapter.update(buildConfig(
        'duckdns',
        {'ip': '203.0.113.1'},
      ));

      expect(result['success'], isFalse);
      expect(result['error'], contains('DuckDNS update failed'));
    });

    test('DuckDNS IPv6 updates use only the ipv6 parameter', () async {
      final adapter = _MockAdapter(
        responseData: {},
        statusCode: 200,
        error: null,
      );
      dio.httpClientAdapter = adapter;

      final result = await createAdapter('duckdns', dioInstance: dio).update(
        buildConfig('duckdns', {
          'ip': '2606:4700:4700::1111',
          'ip_type': 'ipv6',
        }),
      );

      expect(result['success'], isTrue);
      final requestData = adapter.lastRequestOptions?.data as Map;
      expect(requestData['ipv6'], '2606:4700:4700::1111');
      expect(requestData.containsKey('ip'), isFalse);
    });

    test('UpIvY adapter should return success on 200', () async {
      dio.httpClientAdapter = _MockAdapter(
        responseData: {},
        statusCode: 200,
        error: null,
      );

      final adapter = createAdapter('upivy', dioInstance: dio);
      final result = await adapter.update(buildConfig('upivy', {
        'username': 'test-user',
        'ip': '203.0.113.1',
      }));

      expect(result['success'], isTrue);
    });

    test('Cloudflare adapter should return success on 200 with success=true', () async {
      dio.httpClientAdapter = _MockAdapter(
        responseData: {'success': true},
        statusCode: 200,
        error: null,
      );

      final adapter = createAdapter('cloudflare', dioInstance: dio);
      final result = await adapter.update(buildConfig('cloudflare', {
        'zone_id': 'zone1',
        'record_id': 'rec1',
        'ip': '203.0.113.1',
      }));

      expect(result['success'], isTrue);
    });

    test('Cloudflare adapter should return failure on missing fields', () async {
      final adapter = createAdapter('cloudflare', dioInstance: dio);
      final result = await adapter.update(buildConfig('cloudflare'));

      expect(result['success'], isFalse);
      expect(result['error'], contains('Missing required fields'));
    });

    test('Generic adapter should return success on 200/201', () async {
      dio.httpClientAdapter = _MockAdapter(
        responseData: {},
        statusCode: 201,
        error: null,
      );

      final adapter = createAdapter('custom_api', dioInstance: dio);
      final result = await adapter.update(buildConfig('custom_api'));

      expect(result['success'], isTrue);
    });

    test('Generic adapter should return failure on non-success status', () async {
      dio.httpClientAdapter = _MockAdapter(
        responseData: {},
        statusCode: 500,
        error: null,
      );

      final adapter = createAdapter('custom_api', dioInstance: dio);
      final result = await adapter.update(buildConfig('custom_api'));

      expect(result['success'], isFalse);
      expect(result['error'], contains('Custom API update failed'));
    });

    test('Generic adapter should handle network errors gracefully', () async {
      dio.httpClientAdapter = _MockAdapter(
        responseData: {},
        statusCode: 0,
        error: DioException(
          type: DioExceptionType.connectionTimeout,
          requestOptions: RequestOptions(path: 'http://test.api/update'),
        ),
      );

      final adapter = createAdapter('custom_api', dioInstance: dio);
      final result = await adapter.update(buildConfig('custom_api'));

      expect(result['success'], isFalse);
      expect(result['error'], contains('Custom API update failed'));
    });
  });
}