import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:nebula_ddns/config/ddns_config.dart';
import 'package:nebula_ddns/services/id_ddns_service.dart';
import 'package:nebula_ddns/scheduler/scheduler.dart';
import 'package:nebula_ddns/ddns_manager.dart';
import 'package:nebula_ddns/services/public_ip_addresses.dart';

// 模拟依赖
class MockDDNSService extends Mock implements IDDNSService {
  @override
  Future<bool> checkStatus(DDNSConfig config) async => true;

  @override
  String getLastError() => 'No error.';

  @override
  Future<bool> updateDDNS(DDNSConfig config) async => true;

  @override
  Future<String?> getPublicIP({bool forceRefresh = false}) async =>
      '203.0.113.1';

  @override
  Future<PublicIPAddresses> getPublicIPs() async => const PublicIPAddresses(
        ipv4: '203.0.113.1',
        ipv6: '2001:4860:4860::8888',
      );
}

class MockScheduler extends Mock implements Scheduler {}

void main() {
  late MockDDNSService mockService;
  late MockScheduler mockScheduler;
  late DDNSManager manager;
  late DDNSConfig testConfig;

  setUp(() {
    mockService = MockDDNSService();
    mockScheduler = MockScheduler();
    testConfig = DDNSConfig(
      hostname: 'test.ddns.net',
      serviceType: 'custom',
      apiUrl: 'http://test.api',
      apiKey: 'test_key',
      updateRequestConfig: {'ip_type': 'ipv4', 'interval': 300},
      startOnSystemBoot: true,
    );
    manager = DDNSManager(
      ddnsService: mockService,
      scheduler: mockScheduler,
    );
  });

  group('DDNSManager Tests', () {
    test('should load configuration correctly', () async {
      manager.loadConfig(testConfig);
      // 检查内部状态 (虽然是私有字段，但通过行为验证)
      // 验证 loadConfig 成功后，后续操作基于此配置
      expect((await manager.getStatus())['hostname'], 'test.ddns.net');
    });

    test('should start service and initialize scheduler', () {
      manager.loadConfig(testConfig);
      manager.startService(60);

      // 验证调度器被正确初始化
      verify(mockScheduler.initialize(mockService, testConfig, 60)).called(1);
      // 验证调度器被启动
      verify(mockScheduler.start()).called(1);
      // 验证管理器状态
      expect(manager.isRunning(), isTrue);
    });

    test('should stop service and call scheduler stop', () {
      manager.loadConfig(testConfig);
      manager.startService(60);
      manager.stopService();

      // 验证调度器被停止
      verify(mockScheduler.stop()).called(1);
      // 验证管理器状态
      expect(manager.isRunning(), isFalse);
    });

    test('should return correct status including service checks', () async {
      manager.loadConfig(testConfig);
      // 模拟服务检查成功
      manager.startService(60);

      final status = await manager.getStatus();

      expect(status['isRunning'], isTrue);
      expect(status['isUpdateSuccessful'], isFalse);
      expect(status['lastError'], 'No error.');
    });
  });
}
