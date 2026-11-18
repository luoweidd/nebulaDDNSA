import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nebula_ddns/screens/network_settings_screen.dart';
import 'package:nebula_ddns/services/network_settings.dart';

Finder _settingsScrollable() => find
    .descendant(of: find.byType(ListView), matching: find.byType(Scrollable))
    .first;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('saves network mode, ranges, and custom query URL lists', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: const NetworkSettingsScreen(),
      ),
    );
    await tester.pumpAndSettle();

    tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged!(true);
    await tester.pump();
    final rangesInput = find.byKey(const Key('internalRangesInput'));
    await tester.scrollUntilVisible(
      rangesInput,
      200,
      scrollable: _settingsScrollable(),
    );
    await tester.enterText(rangesInput, '10.20.0.0/16\n2001:db8:1234::/48');
    final ipv4UrlsInput = find.byKey(const Key('ipv4QueryUrlsInput'));
    await tester.scrollUntilVisible(
      ipv4UrlsInput,
      200,
      scrollable: _settingsScrollable(),
    );
    await tester.enterText(
      ipv4UrlsInput,
      'https://v4.example/ip\nhttps://v4-backup.example/ip',
    );
    final ipv6UrlsInput = find.byKey(const Key('ipv6QueryUrlsInput'));
    await tester.scrollUntilVisible(
      ipv6UrlsInput,
      200,
      scrollable: _settingsScrollable(),
    );
    await tester.enterText(ipv6UrlsInput, 'https://v6.example/ip');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final settings = await NetworkSettingsStore.load();
    expect(settings.ipv6OnlyMode, isTrue);
    expect(settings.customInternalRanges, [
      '10.20.0.0/16',
      '2001:db8:1234::/48',
    ]);
    expect(settings.customIPv4QueryUrls, [
      'https://v4.example/ip',
      'https://v4-backup.example/ip',
    ]);
    expect(settings.customIPv6QueryUrls, ['https://v6.example/ip']);
  });

  testWidgets('rejects invalid custom ranges before saving', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: const NetworkSettingsScreen(),
      ),
    );
    await tester.pumpAndSettle();

    final rangesInput = find.byKey(const Key('internalRangesInput'));
    await tester.scrollUntilVisible(
      rangesInput,
      200,
      scrollable: _settingsScrollable(),
    );
    await tester.enterText(rangesInput, '10.20.0.0/33');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Invalid prefix length'), findsOneWidget);
    expect((await NetworkSettingsStore.load()).customInternalRanges, isEmpty);
  });

  testWidgets('rejects invalid custom query URLs before saving', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: const NetworkSettingsScreen(),
      ),
    );
    await tester.pumpAndSettle();

    final ipv6UrlsInput = find.byKey(const Key('ipv6QueryUrlsInput'));
    await tester.scrollUntilVisible(
      ipv6UrlsInput,
      200,
      scrollable: _settingsScrollable(),
    );
    await tester.enterText(ipv6UrlsInput, 'file:///etc/passwd');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.textContaining('IPv6 查询地址无效'), findsOneWidget);
    expect((await NetworkSettingsStore.load()).customIPv6QueryUrls, isEmpty);
  });
}
