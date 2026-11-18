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

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('shows an actionable empty state when no config is saved',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: DDNSDashboardScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('尚未配置'), findsOneWidget);
    expect(find.text('还没有 DDNS 配置'), findsOneWidget);
    expect(find.text('添加配置'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('restores saved config and renders dashboard on narrow screens',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final config = DDNSConfig(
      hostname: 'home.example.com',
      serviceType: 'duckdns',
      apiUrl: 'https://www.duckdns.org/update',
      apiKey: 'test-token',
      updateRequestConfig: const {'ip': '203.0.113.1'},
    );
    SharedPreferences.setMockInitialValues({
      DDNSManagerNotifier.configKey: config.toJsonConfig(),
    });
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

    expect(find.text('服务运行中'), findsNothing);
    expect(find.text('DuckDNS'), findsNWidgets(2));
    expect(find.text('home.example.com'), findsOneWidget);
    expect(find.text('启动服务'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saves configuration through the dashboard flow', (tester) async {
    final config = DDNSConfig(
      hostname: 'home.example.com',
      serviceType: 'custom_api',
      apiUrl: 'https://api.example.com/update',
      apiKey: 'test-token',
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

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(DDNSManagerNotifier.configKey), isNotNull);
    expect(find.text('home.example.com'), findsOneWidget);
    expect(find.text('启动服务'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
