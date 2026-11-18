import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:nebula_ddns/config/ddns_config.dart';
import 'package:nebula_ddns/services/configurable_ddns_service.dart';

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