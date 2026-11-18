import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';

import 'providers/ddns_logs_provider.dart';
import 'providers/ddns_manager_provider.dart';
import 'screens/ddns_dashboard.dart';
import 'themes/theme.dart';
import 'config/ddns_config.dart';
import 'platform/platform_manager.dart';
import 'services/configurable_ddns_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (PlatformManager.supportsMobileBackground) {
    await PlatformManager.configureMobileBackgroundService(
      onStart: _runMobileBackgroundService,
      onBackground: _runMobileBackgroundFetch,
    );
  }
  runApp(const ProviderScope(child: MyApp()));
}

@pragma('vm:entry-point')
Future<void> _runMobileBackgroundService(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  Timer? updateTimer;
  service.on('stop').listen((_) async {
    updateTimer?.cancel();
    await service.stopSelf();
  });
  final prefs = await SharedPreferences.getInstance();
  final interval = prefs.getInt('ddns_update_interval_seconds') ?? 300;
  await _performMobileBackgroundUpdate();
  updateTimer = Timer.periodic(Duration(seconds: interval), (_) {
    unawaited(_performMobileBackgroundUpdate());
  });
}

@pragma('vm:entry-point')
Future<bool> _runMobileBackgroundFetch(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  await _performMobileBackgroundUpdate();
  return true;
}

@pragma('vm:entry-point')
Future<void> _performMobileBackgroundUpdate() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(DDNSManagerNotifier.configKey);
    if (json == null) return;
    final map = jsonDecode(json) as Map<String, dynamic>;
    final apiKey =
        await const FlutterSecureStorage().read(key: 'ddns_api_key') ?? '';
    final config = DDNSConfig(
      hostname: map['hostname']?.toString() ?? '',
      serviceType: map['serviceType']?.toString() ?? '',
      apiUrl: map['apiUrl']?.toString() ?? '',
      apiKey: apiKey,
      updateRequestConfig:
          (map['updateRequestConfig'] as Map?)?.cast<String, dynamic>(),
      startOnSystemBoot: map['startOnSystemBoot'] == true,
    );
    await ConfigurableDDNSService(dioInstance: Dio()).updateDDNS(config);
  } catch (error, stackTrace) {
    developer.log(
      'Mobile background DDNS update failed.',
      name: 'NebulaDDNS',
      error: error,
      stackTrace: stackTrace,
    );
  }
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> with TrayListener {
  static const _trayIconPath = 'assets/icons/tray_icon_512.png';
  static const _menuOpenDashboard = 'open_dashboard';
  static const _menuManualUpdate = 'manual_update';
  static const _menuExit = 'exit';

  bool get _supportsSystemTray =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS);

  @override
  void initState() {
    super.initState();
    if (_supportsSystemTray) {
      trayManager.addListener(this);
      unawaited(_initializeTray());
    }
  }

  Future<void> _initializeTray() async {
    try {
      await trayManager.setIcon(_trayIconPath);
      await trayManager.setToolTip('Nebula DDNS');
      await trayManager.setContextMenu(
        Menu(
          items: [
            MenuItem(key: _menuOpenDashboard, label: '打开 Nebula DDNS'),
            MenuItem.separator(),
            MenuItem(key: _menuManualUpdate, label: '立即更新'),
            MenuItem.separator(),
            MenuItem(key: _menuExit, label: '退出'),
          ],
        ),
      );
    } catch (error, stackTrace) {
      developer.log(
        'System tray initialization failed.',
        name: 'NebulaDDNS',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        ref.read(ddnsLogsProvider.notifier).add('系统托盘初始化失败：$error');
      }
    }
  }

  @override
  void onTrayIconMouseUp() {
    _showDashboard();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case _menuOpenDashboard:
        _showDashboard();
      case _menuManualUpdate:
        unawaited(_handleManualUpdate());
      case _menuExit:
        unawaited(_exitApp());
    }
  }

  void _showDashboard() {
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _handleManualUpdate() async {
    final success = await ref.read(ddnsManagerProvider.notifier).updateNow();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            success
                ? 'DDNS 更新成功。'
                : 'DDNS 更新失败：${ref.read(ddnsManagerProvider.notifier).getLastLog() ?? '请查看最近活动日志。'}',
          ),
          backgroundColor: success ? null : Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _exitApp() async {
    if (ref.read(ddnsManagerProvider)['isRunning'] == true) {
      await ref.read(ddnsManagerProvider.notifier).stopService();
    }
    await trayManager.destroy();
    await SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nebula DDNS Client',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: const DDNSDashboardScreen(),
    );
  }

  @override
  void dispose() {
    if (_supportsSystemTray) {
      trayManager.removeListener(this);
    }
    super.dispose();
  }
}
