import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:nebula_ddns/config/ddns_config.dart';
import 'package:nebula_ddns/services/configurable_ddns_service.dart';
import 'package:nebula_ddns/services/ip_resolver.dart';
import 'package:nebula_ddns/services/network_settings.dart';

class _IPv6OnlyAdapter implements HttpClientAdapter {
  RequestOptions? updateRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final host = options.uri.host;
    final isLookup = host == 'api6.ipify.org' || host == '6.ipw.cn';
    if (!isLookup) updateRequest = options;
    return ResponseBody.fromString(
      isLookup
          ? '2606:4700:4700::1111'
          : '{"success":true}',
      200,
      headers: {
        HttpHeaders.contentTypeHeader: [
          isLookup ? 'text/plain' : 'application/json',
        ],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// 自定义 mock 拦截器，根据响应模式返回响应。
class _ResponseMock extends Interceptor {
  final Map<String, dynamic> responseData;
  final int statusCode;
  final bool throwOnError;
  final DioException? error;

  _ResponseMock({
    required this.responseData,
    required this.statusCode,
    required this.throwOnError,
    required this.error,
  });

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    handler.resolve(Response<dynamic>(
      requestOptions: options,
      data: responseData,
      statusCode: statusCode,
    ));
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (throwOnError) {
      handler.reject(err);
    } else {
      handler.reject(err);
    }
  }
}

void main() {
  late ConfigurableDDNSService service;
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
    service = ConfigurableDDNSService(dioInstance: dio);
  });

  group('ConfigurableDDNSService Tests', () {
    test('should successfully update DDNS when API returns 200/201', () async {
      dio.interceptors.add(_ResponseMock(
        responseData: {'status': 'ok'},
        statusCode: 200,
        throwOnError: false,
        error: null,
      ));

      final success = await service.updateDDNS(buildConfig('custom'));

      expect(success, isTrue);
      expect(service.getLastError(), 'No error.');
    });

    test('should fail update when API returns non-success status code', () async {
      dio.interceptors.add(_ResponseMock(
        responseData: {'error': 'invalid credentials'},
        statusCode: 401,
        throwOnError: false,
        error: null,
      ));

      final success = await service.updateDDNS(buildConfig('custom'));

      expect(success, isFalse);
      expect(service.getLastError(), contains('Status 401'));
    });

    test('should fail update on network or parsing error', () async {
      dio.interceptors.add(_ResponseMock(
        responseData: {},
        statusCode: 0,
        throwOnError: true,
        error: DioException(
          type: DioExceptionType.connectionTimeout,
          requestOptions: RequestOptions(path: 'http://test.api/update'),
        ),
      ));

      final success = await service.updateDDNS(buildConfig('custom'));

      expect(success, isFalse);
      expect(service.getLastError(), contains('Network or Parsing Error'));
    });

    test('should block DDNS updates when a proxy is configured', () async {
      final guardedService = ConfigurableDDNSService(
        dioInstance: dio,
        ipResolver: IPResolver(
          dioInstance: dio,
          networkPathGuard: NetworkPathGuard(
            environment: const {'HTTPS_PROXY': 'http://127.0.0.1:8080'},
            interfaceNames: () async => [],
          ),
        ),
      );
      dio.interceptors.add(_ResponseMock(
        responseData: {'status': 'ok'},
        statusCode: 200,
        throwOnError: false,
        error: null,
      ));

      final success = await guardedService.updateDDNS(
        buildConfig('custom', {'ip': '203.0.113.1'}),
      );

      expect(success, isFalse);
      expect(guardedService.getLastError(), contains('检测到代理环境变量'));
    });

    test('IPv6-only mode sends an IPv6 update without changing the A record',
        () async {
      final adapter = _IPv6OnlyAdapter();
      final isolatedDio = Dio();
      isolatedDio.httpClientAdapter = adapter;
      final guardedResolver = IPResolver(
        dioInstance: isolatedDio,
        networkPathGuard: NetworkPathGuard(
          environment: const {},
          interfaceNames: () async => [],
        ),
      );
      final ipv6Service = ConfigurableDDNSService(
        dioInstance: isolatedDio,
        ipResolver: guardedResolver,
        networkSettingsProvider: () async =>
            const NetworkSettings(ipv6OnlyMode: true),
      );

      final success = await ipv6Service.updateDDNS(
        buildConfig('custom_api', {'ip_type': 'ipv6'}),
      );

      expect(success, isTrue);
      expect(adapter.updateRequest?.queryParameters['ip_type'], 'ipv6');
      expect(adapter.updateRequest?.data.toString(),
          contains('2606:4700:4700::1111'));
      expect(adapter.updateRequest?.queryParameters['ip_type'], isNot('ipv4'));
    });

    test('should reset retry count on new update attempt', () async {
      service.setRetryCount(2);
      expect(service.retryCount, 2);
      expect(service.isMaxRetriesReached, isFalse);

      dio.interceptors.add(_ResponseMock(
        responseData: {'status': 'ok'},
        statusCode: 200,
        throwOnError: false,
        error: null,
      ));

      await service.updateDDNS(buildConfig('custom'));

      expect(service.retryCount, 0);
      expect(service.isMaxRetriesReached, isFalse);
    });

    test('should check status successfully when API returns 200', () async {
      dio.interceptors.add(_ResponseMock(
        responseData: {'status': 'ok'},
        statusCode: 200,
        throwOnError: false,
        error: null,
      ));

      final success = await service.checkStatus(buildConfig('custom'));

      expect(success, isTrue);
    });
  });
}