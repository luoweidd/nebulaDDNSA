import 'dart:async';
import 'dart:developer' as developer;

import '../config/ddns_config.dart';
import '../services/id_ddns_service.dart';

abstract class Scheduler {
  void initialize(IDDNSService service, DDNSConfig config, int intervalSeconds);
  void start();
  void stop();
  bool get isRunning;
}

abstract class _PeriodicScheduler implements Scheduler {
  _PeriodicScheduler({IDDNSService? ddnsService, DDNSConfig? config})
      : _ddnsService = ddnsService,
        _config = config;

  IDDNSService? _ddnsService;
  DDNSConfig? _config;
  Timer? _timer;
  int _intervalSeconds = 60;
  bool _isRunning = false;
  bool _isExecuting = false;

  String get _schedulerName;

  @override
  void initialize(
    IDDNSService service,
    DDNSConfig config,
    int intervalSeconds,
  ) {
    if (intervalSeconds <= 0) {
      throw ArgumentError.value(
        intervalSeconds,
        'intervalSeconds',
        'Must be greater than zero.',
      );
    }
    _ddnsService = service;
    _config = config;
    _intervalSeconds = intervalSeconds;
  }

  @override
  void start() {
    if (_isRunning) return;
    if (_ddnsService == null || _config == null) {
      throw StateError('Initialize the scheduler before starting it.');
    }
    _isRunning = true;
    unawaited(_executeTask());
    _timer = Timer.periodic(
      Duration(seconds: _intervalSeconds),
      (_) => unawaited(_executeTask()),
    );
  }

  @override
  void stop() {
    _timer?.cancel();
    _timer = null;
    _isRunning = false;
  }

  @override
  bool get isRunning => _isRunning;

  Future<void> _executeTask() async {
    if (!_isRunning || _isExecuting) return;
    final service = _ddnsService;
    final config = _config;
    if (service == null || config == null) {
      throw StateError('Scheduler dependencies are not initialized.');
    }

    _isExecuting = true;
    try {
      final success = await service.updateDDNS(config);
      if (!success) {
        developer.log(
          service.getLastError(),
          name: _schedulerName,
          level: 900,
        );
      }
    } catch (error, stackTrace) {
      developer.log(
        'Scheduled DDNS update failed.',
        name: _schedulerName,
        error: error,
        stackTrace: stackTrace,
        level: 1000,
      );
    } finally {
      _isExecuting = false;
    }
  }
}

class MobileScheduler extends _PeriodicScheduler {
  MobileScheduler({super.ddnsService, super.config});

  @override
  String get _schedulerName => 'MobileScheduler';
}

class DesktopScheduler extends _PeriodicScheduler {
  DesktopScheduler({super.ddnsService, super.config});

  @override
  String get _schedulerName => 'DesktopScheduler';
}

class BackgroundScheduler extends _PeriodicScheduler {
  BackgroundScheduler({super.ddnsService, super.config});

  @override
  String get _schedulerName => 'BackgroundScheduler';
}

class ExternalScheduler implements Scheduler {
  bool _isRunning = false;

  @override
  void initialize(
    IDDNSService service,
    DDNSConfig config,
    int intervalSeconds,
  ) {
    if (intervalSeconds <= 0) {
      throw ArgumentError.value(
        intervalSeconds,
        'intervalSeconds',
        'Must be greater than zero.',
      );
    }
  }

  @override
  void start() {
    _isRunning = true;
  }

  @override
  void stop() {
    _isRunning = false;
  }

  @override
  bool get isRunning => _isRunning;
}
