import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_ddns/services/ip_resolver.dart';

class _IPv4Adapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('resolves and caches a public IPv4 address', () async {
    final dio = Dio();
    dio.httpClientAdapter = _IPv4Adapter();
    final resolver = IPResolver(dioInstance: dio);

    expect(await resolver.resolvePublicIP(), '203.0.113.10');
    expect(await resolver.resolvePublicIP(), '203.0.113.10');
  });
}
