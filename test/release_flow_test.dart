import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nebula_ddns/config/ddns_config.dart';
import 'package:nebula_ddns/providers/ddns_manager_provider.dart';
import 'package:nebula_ddns/screens/ddns_dashboard.dart';
import 'package:nebula_ddns/platform/system_boot_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('release flow restores config, starts, updates and stops',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final config = DDNSConfig(
      hostname: 'release.example.com',
      serviceType: 'custom_api',
      apiUrl: 'https://api.example.com/update',
      apiKey: 'release-test-key',
      updateRequestConfig: const {'method': 'POST'},
    );
    final container = ProviderContainer(
      overrides: [
        systemBootManagerProvider
            .overrideWithValue(const UnsupportedBootManager()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: DDNSDashboardScreen()),
      ),
    );
    await container.read(ddnsManagerProvider.notifier).loadConfig(config);
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('release.example.com'), findsOneWidget);
    expect(find.text('启动服务'), findsOneWidget);

    await tester.ensureVisible(find.text('启动服务'));
    await tester.tap(find.text('启动服务'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(container.read(ddnsManagerProvider)['isRunning'], isTrue);

    await tester.ensureVisible(find.text('停止服务'));
    await tester.tap(find.text('停止服务'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(container.read(ddnsManagerProvider)['isRunning'], isFalse);
  });
}
