import 'package:shared_preferences/shared_preferences.dart';

class NetworkSettings {
  final bool ipv6OnlyMode;
  final List<String> customInternalRanges;
  final List<String> customIPv4QueryUrls;
  final List<String> customIPv6QueryUrls;

  const NetworkSettings({
    this.ipv6OnlyMode = false,
    this.customInternalRanges = const [],
    this.customIPv4QueryUrls = const [],
    this.customIPv6QueryUrls = const [],
  });
}

class NetworkSettingsStore {
  static const _ipv6OnlyModeKey = 'network_ipv6_only_mode';
  static const _customInternalRangesKey = 'network_custom_internal_ranges';
  static const _customIPv4QueryUrlsKey = 'network_custom_ipv4_query_urls';
  static const _customIPv6QueryUrlsKey = 'network_custom_ipv6_query_urls';

  static Future<NetworkSettings> load() async {
    final preferences = await SharedPreferences.getInstance();
    return NetworkSettings(
      ipv6OnlyMode: preferences.getBool(_ipv6OnlyModeKey) ?? false,
      customInternalRanges:
          preferences.getStringList(_customInternalRangesKey) ?? const [],
      customIPv4QueryUrls:
          preferences.getStringList(_customIPv4QueryUrlsKey) ?? const [],
      customIPv6QueryUrls:
          preferences.getStringList(_customIPv6QueryUrlsKey) ?? const [],
    );
  }

  static Future<List<String>> loadCustomInternalRanges() async =>
      (await load()).customInternalRanges;

  static Future<void> save(NetworkSettings settings) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_ipv6OnlyModeKey, settings.ipv6OnlyMode);
    await preferences.setStringList(
      _customInternalRangesKey,
      settings.customInternalRanges,
    );
    await preferences.setStringList(
      _customIPv4QueryUrlsKey,
      settings.customIPv4QueryUrls,
    );
    await preferences.setStringList(
      _customIPv6QueryUrlsKey,
      settings.customIPv6QueryUrls,
    );
  }
}
