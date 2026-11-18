import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nebula_ddns/config/ddns_config.dart';
import 'package:nebula_ddns/ddns_manager.dart';
import 'package:nebula_ddns/providers/ddns_manager_provider.dart';
import 'package:nebula_ddns/scheduler/scheduler.dart';
import 'package:nebula_ddns/screens/ddns_dashboard.dart';
import 'package:nebula_ddns/services/id_ddns_service.dart';
import 'package:nebula_ddns/services/public_ip_addresses.dart';
import 'package:nebula_ddns/platform/system_boot_manager.dart';
import 'package:nebula_ddns/themes/theme.dart';

class _FakeDDNSService implements IDDNSService {
  int publicIPLookups = 0;

  @override
  Future<bool> checkStatus(DDNSConfig config) async => true;

  @override
  Future<bool> updateDDNS(DDNSConfig config) async => true;

  @override
  String getLastError() => '';

  @override
  Future<String?> getPublicIP({bool forceRefresh = false}) async => null;

  @override
  Future<PublicIPAddresses> getPublicIPs() async {
    publicIPLookups++;
    return const PublicIPAddresses(
      ipv4: '198.51.100.40',
      ipv6: '2001:4860:4860::8888',
    );
  }
}

class _FakeScheduler implements Scheduler {
  bool _isRunning = false;

  @override
  void initialize(
    IDDNSService service,
    DDNSConfig config,
    int intervalSeconds,
  ) {}

  @override
  void start() => _isRunning = true;

  @override
  void stop() => _isRunning = false;

  @override
  bool get isRunning => _isRunning;
}

ProviderContainer _createContainer(_FakeDDNSService service) {
  return ProviderContainer(
    overrides: [
      ddnsManagerProvider.overrideWith(
        (ref) => DDNSManagerNotifier(
          DDNSManager(ddnsService: service, scheduler: _FakeScheduler()),
          ref,
        ),
      ),
      systemBootManagerProvider.overrideWithValue(
        const UnsupportedBootManager(),
      ),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('shows an actionable empty state when no config is saved', (
    tester,
  ) async {
    final container = _createContainer(_FakeDDNSService());
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: DDNSDashboardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('尚未配置'), findsOneWidget);
    expect(find.text('还没有 DDNS 配置'), findsOneWidget);
    expect(find.text('添加配置'), findsOneWidget);
    expect(find.text('IPv4'), findsOneWidget);
    expect(find.text('IPv6'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('automatically fetches public IP on startup', (tester) async {
    final service = _FakeDDNSService();
    final container = _createContainer(service);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: DDNSDashboardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(service.publicIPLookups, 1);
    expect(find.text('198.51.100.40'), findsOneWidget);
    expect(find.text('2001:4860:4860::8888'), findsOneWidget);
  });

  testWidgets('interval menu uses readable dark-theme colors', (tester) async {
    final service = _FakeDDNSService();
    final container = _createContainer(service);
    addTearDown(container.dispose);
    final theme = AppTheme.darkTheme;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: theme, home: const DDNSDashboardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final dropdown = tester.widget<DropdownButton<int>>(
      find.byType(DropdownButton<int>),
    );
    expect(dropdown.dropdownColor, theme.colorScheme.surface);
    for (final item in dropdown.items!) {
      expect((item.child as Text).style?.color, theme.colorScheme.onSurface);
    }
  });

  test('dark theme provides readable on-surface text', () {
    final theme = AppTheme.darkTheme;
    expect(theme.textTheme.titleLarge?.color, theme.colorScheme.onSurface);
    expect(theme.textTheme.bodyMedium?.color, theme.colorScheme.onSurface);
  });

  testWidgets('restores saved config and renders dashboard on narrow screens', (
    tester,
  ) async {
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
    final container = _createContainer(_FakeDDNSService());
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
    final container = _createContainer(_FakeDDNSService());
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
