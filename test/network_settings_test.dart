import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nebula_ddns/services/ip_resolver.dart';
import 'package:nebula_ddns/services/network_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('loads defaults and persists global network settings', () async {
    final defaults = await NetworkSettingsStore.load();
    expect(defaults.ipv6OnlyMode, isFalse);
    expect(defaults.customInternalRanges, isEmpty);

    await NetworkSettingsStore.save(
      const NetworkSettings(
        ipv6OnlyMode: true,
        customInternalRanges: ['10.20.0.0/16', '2001:db8:1234::/48'],
        customIPv4QueryUrls: [
          'https://v4.example/ip',
          'https://v4-backup.example/ip',
        ],
        customIPv6QueryUrls: ['https://v6.example/ip'],
      ),
    );

    final restored = await NetworkSettingsStore.load();
    expect(restored.ipv6OnlyMode, isTrue);
    expect(restored.customInternalRanges, [
      '10.20.0.0/16',
      '2001:db8:1234::/48',
    ]);
    expect(restored.customIPv4QueryUrls, [
      'https://v4.example/ip',
      'https://v4-backup.example/ip',
    ]);
    expect(restored.customIPv6QueryUrls, ['https://v6.example/ip']);
  });

  test('matches custom IPv4 and IPv6 CIDR ranges', () {
    final ipv4Range = IpNetworkRange.parse('10.20.0.0/16');
    final ipv6Range = IpNetworkRange.parse('2001:db8:1234::/48');

    expect(ipv4Range.contains(InternetAddress('10.20.4.5')), isTrue);
    expect(ipv4Range.contains(InternetAddress('10.21.4.5')), isFalse);
    expect(ipv6Range.contains(InternetAddress('2001:db8:1234::1')), isTrue);
    expect(ipv6Range.contains(InternetAddress('2001:db8:1235::1')), isFalse);
  });

  test('rejects invalid CIDR prefixes', () {
    expect(() => IpNetworkRange.parse('10.20.0.0/33'), throwsFormatException);
    expect(() => IpNetworkRange.parse('2001:db8::/129'), throwsFormatException);
  });
}
