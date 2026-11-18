import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nebula_ddns/providers/ddns_manager_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('migrates a legacy plaintext API key into secure storage', () async {
    SharedPreferences.setMockInitialValues({
      DDNSManagerNotifier.configKey: jsonEncode({
        'hostname': 'home.example.com',
        'serviceType': 'custom_api',
        'apiUrl': 'https://api.example.com/update',
        'apiKey': 'legacy-secret',
        'updateRequestConfig': <String, dynamic>{},
      }),
    });
    FlutterSecureStorage.setMockInitialValues({});

    final config = await DDNSManagerNotifier.restoreConfig();
    final prefs = await SharedPreferences.getInstance();
    const secureStorage = FlutterSecureStorage();
    final savedConfig = jsonDecode(
      prefs.getString(DDNSManagerNotifier.configKey)!,
    ) as Map<String, dynamic>;

    expect(config?.apiKey, 'legacy-secret');
    expect(await secureStorage.read(key: 'ddns_api_key'), 'legacy-secret');
    expect(savedConfig.containsKey('apiKey'), isFalse);
  });

  test('reports an unreadable stored API key instead of restoring it empty',
      () async {
    SharedPreferences.setMockInitialValues({
      DDNSManagerNotifier.configKey: jsonEncode({
        'hostname': 'home.example.com',
        'serviceType': 'custom_api',
        'apiUrl': 'https://api.example.com/update',
      }),
    });
    FlutterSecureStorage.setMockInitialValues({'ddns_api_key': ''});

    await expectLater(
      DDNSManagerNotifier.restoreConfig(),
      throwsA(isA<StateError>()),
    );
  });
}
