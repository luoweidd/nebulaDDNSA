import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

import 'system_boot_manager.dart';

/// Centralizes platform-specific lifecycle decisions.
class PlatformManager {
  const PlatformManager._();

  static SystemBootManager createBootManager() {
    if (kIsWeb) {
      return const UnsupportedBootManager();
    }
    if (Platform.isWindows) return WindowsBootManager();
    if (Platform.isLinux) return LinuxBootManager();
    if (Platform.isMacOS) return MacOSBootManager();
    if (Platform.isAndroid || Platform.isIOS) {
      return const UnsupportedBootManager();
    }
    return const UnsupportedBootManager();
  }

  static bool get supportsDesktopTray =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  static bool get supportsMobileBackground =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static Future<bool> configureMobileBackgroundService({
    required Future<void> Function(ServiceInstance service) onStart,
    required Future<bool> Function(ServiceInstance service) onBackground,
  }) async {
    if (!supportsMobileBackground) return false;
    final service = FlutterBackgroundService();
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false,
        autoStartOnBoot: false,
        isForegroundMode: true,
        initialNotificationTitle: 'Nebula DDNS',
        initialNotificationContent: '动态 DNS 服务正在运行',
      ),
      iosConfiguration: IosConfiguration(
        onForeground: onStart,
        onBackground: onBackground,
        autoStart: false,
      ),
    );
    return true;
  }

  static Future<bool> startMobileBackgroundService() async {
    if (!supportsMobileBackground) return false;
    final service = FlutterBackgroundService();
    if (await service.isRunning()) return true;
    return service.startService();
  }

  static Future<bool> stopMobileBackgroundService() async {
    if (!supportsMobileBackground) return false;
    final service = FlutterBackgroundService();
    if (!await service.isRunning()) return true;
    service.invoke('stop');
    return true;
  }
}
