// d:\projectfile\Fluterproject\nebulaDDNSA\lib\platform\system_boot_manager.dart
import 'dart:io';
import 'dart:developer' as developer;

/// SystemBootManager：跨平台开机自启注册与注销管理器。
///
/// 企业级特性：
/// - Windows：使用 Task Scheduler 注册计划任务
/// - Linux：使用 systemd 注册服务
/// - macOS：使用 LaunchDaemon 注册守护进程
/// - 统一的注册/注销接口，平台差异封装在内部
abstract class SystemBootManager {
  /// 注册开机自启。
  Future<bool> register();

  /// 注销开机自启。
  Future<bool> unregister();

  /// 检查是否已注册开机自启。
  Future<bool> isRegistered();
}

class UnsupportedBootManager implements SystemBootManager {
  const UnsupportedBootManager();

  @override
  Future<bool> register() async => false;

  @override
  Future<bool> unregister() async => true;

  @override
  Future<bool> isRegistered() async => false;
}

/// Windows 平台开机自启管理器（Task Scheduler）。
class WindowsBootManager implements SystemBootManager {
  static const String taskName = 'NebulaDDNSClient';

  @override
  Future<bool> register() async {
    try {
      final executable = Platform.resolvedExecutable;
      final result = await Process.run('schtasks', [
        '/Create',
        '/TN',
        taskName,
        '/TR',
        '"$executable"',
        '/SC',
        'ONLOGON',
        '/RL',
        'LIMITED',
        '/F',
      ]);
      if (result.exitCode == 0) {
        developer.log('Registered startup task: $taskName', name: 'WindowsBoot');
        return true;
      }
      developer.log('Failed to register startup task: ${result.stderr}',
          name: 'WindowsBoot', level: 900);
      return false;
    } catch (e) {
      developer.log('Error registering startup task: $e',
          name: 'WindowsBoot', level: 1000);
      return false;
    }
  }

  @override
  Future<bool> unregister() async {
    try {
      final result =
          await Process.run('schtasks', ['/Delete', '/TN', taskName, '/F']);
      if (result.exitCode == 0) {
        developer.log('Unregistered startup task: $taskName', name: 'WindowsBoot');
        return true;
      }
      developer.log('Failed to unregister startup task: ${result.stderr}',
          name: 'WindowsBoot', level: 900);
      return false;
    } catch (e) {
      developer.log('Error unregistering startup task: $e',
          name: 'WindowsBoot', level: 1000);
      return false;
    }
  }

  @override
  Future<bool> isRegistered() async {
    try {
      final result =
          await Process.run('schtasks', ['/Query', '/TN', taskName]);
      return result.exitCode == 0;
    } catch (e) {
      developer.log('Error checking startup task status: $e',
          name: 'WindowsBoot', level: 900);
      return false;
    }
  }
}

/// Linux 平台开机自启管理器（systemd）。
class LinuxBootManager implements SystemBootManager {
  static const String serviceName = 'nebula-ddns.service';

  @override
  Future<bool> register() async {
    try {
      final executable = Platform.resolvedExecutable;
      final home = Platform.environment['HOME'];
      if (home == null || home.isEmpty) return false;
      final unitDir = Directory('$home/.config/systemd/user');
      await unitDir.create(recursive: true);
      final unit = File('${unitDir.path}/$serviceName');
      await unit.writeAsString(
        '[Unit]\n'
        'Description=Nebula DDNS Client\n'
        'After=network-online.target\n'
        'Wants=network-online.target\n\n'
        '[Service]\n'
        'ExecStart=$executable\n'
        'Restart=on-failure\n\n'
        '[Install]\n'
        'WantedBy=default.target\n',
      );
      final reloadResult =
          await Process.run('systemctl', ['--user', 'daemon-reload']);
      if (reloadResult.exitCode != 0) return false;
      final enableResult =
          await Process.run('systemctl', ['--user', 'enable', serviceName]);
      if (enableResult.exitCode == 0) {
        developer.log('Enabled service: $serviceName', name: 'LinuxBoot');
        return true;
      }
      developer.log('Failed to enable service: ${enableResult.stderr}',
          name: 'LinuxBoot', level: 900);
      return false;
    } catch (e) {
      developer.log('Error enabling service: $e',
          name: 'LinuxBoot', level: 1000);
      return false;
    }
  }

  @override
  Future<bool> unregister() async {
    try {
      final result =
          await Process.run('systemctl', ['--user', 'disable', serviceName]);
      if (result.exitCode == 0) {
        final home = Platform.environment['HOME'];
        if (home != null) {
          final unit = File('$home/.config/systemd/user/$serviceName');
          if (await unit.exists()) await unit.delete();
        }
        await Process.run(
          'systemctl',
          ['--user', 'daemon-reload'],
        );
        developer.log('Disabled service: $serviceName', name: 'LinuxBoot');
        return true;
      }
      developer.log('Failed to disable service: ${result.stderr}',
          name: 'LinuxBoot', level: 900);
      return false;
    } catch (e) {
      developer.log('Error disabling service: $e',
          name: 'LinuxBoot', level: 1000);
      return false;
    }
  }

  @override
  Future<bool> isRegistered() async {
    try {
      final result =
          await Process.run('systemctl', ['--user', 'is-enabled', serviceName]);
      return result.exitCode == 0;
    } catch (e) {
      developer.log('Error checking service status: $e',
          name: 'LinuxBoot', level: 900);
      return false;
    }
  }
}

/// macOS 平台开机自启管理器（LaunchDaemon）。
class MacOSBootManager implements SystemBootManager {
  static const String daemonName = 'nebula.ddns.client';

  @override
  Future<bool> register() async {
    try {
      final home = Platform.environment['HOME'];
      if (home == null || home.isEmpty) return false;
      final agentsDir = Directory('$home/Library/LaunchAgents');
      await agentsDir.create(recursive: true);
      final plist = File('${agentsDir.path}/$daemonName.plist');
      await plist.writeAsString(
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
        '"http://www.apple.com/DTDs/PropertyList-1.0.plist">\n'
        '<plist version="1.0"><dict>\n'
        '  <key>Label</key><string>$daemonName</string>\n'
        '  <key>ProgramArguments</key><array>\n'
        '    <string>${Platform.resolvedExecutable}</string>\n'
        '  </array>\n'
        '  <key>RunAtLoad</key><true/> \n'
        '  <key>KeepAlive</key><false/>\n'
        '</dict></plist>\n',
      );
      final result = await Process.run(
        'launchctl',
        ['load', '-w', plist.path],
      );
      if (result.exitCode == 0) {
        developer.log('Loaded daemon: $daemonName', name: 'MacOSBoot');
        return true;
      }
      developer.log('Failed to load daemon: ${result.stderr}',
          name: 'MacOSBoot', level: 900);
      return false;
    } catch (e) {
      developer.log('Error loading daemon: $e',
          name: 'MacOSBoot', level: 1000);
      return false;
    }
  }

  @override
  Future<bool> unregister() async {
    try {
      final home = Platform.environment['HOME'];
      if (home == null || home.isEmpty) return false;
      final plist = File('$home/Library/LaunchAgents/$daemonName.plist');
      final result = await Process.run(
        'launchctl',
        ['unload', '-w', plist.path],
      );
      if (result.exitCode == 0) {
        if (await plist.exists()) await plist.delete();
        developer.log('Unloaded daemon: $daemonName', name: 'MacOSBoot');
        return true;
      }
      developer.log('Failed to unload daemon: ${result.stderr}',
          name: 'MacOSBoot', level: 900);
      return false;
    } catch (e) {
      developer.log('Error unloading daemon: $e',
          name: 'MacOSBoot', level: 1000);
      return false;
    }
  }

  @override
  Future<bool> isRegistered() async {
    try {
      final result = await Process.run('launchctl', ['list', daemonName]);
      return result.exitCode == 0;
    } catch (e) {
      developer.log('Error checking daemon status: $e',
          name: 'MacOSBoot', level: 900);
      return false;
    }
  }
}