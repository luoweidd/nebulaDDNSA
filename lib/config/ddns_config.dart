// d:\projectfile\Fluterproject\nebulaDDNSA\lib\config\ddns_config.dart
import 'dart:convert';

/// DDNS 配置模型，企业级、不可变。
/// 
/// 该类封装了 DDNS 服务的核心配置信息，包括：
/// - [hostname]：域名主机名
/// - [serviceType]：服务类型（如 no-ip、duckdns、custom_api 等）
/// - [apiUrl]：API 端点 URL
/// - [apiKey]：API 密钥
/// - [updateRequestConfig]：动态生成的更新请求参数（如 ip、domain_id 等）
/// - [startOnSystemBoot]：是否开机自启
class DDNSConfig {
  final String hostname;
  final String serviceType; // e.g., 'no-ip', 'duckdns'
  final String apiUrl;
  final String apiKey;
  final Map<String, dynamic> updateRequestConfig; // 存储更新请求参数
  final bool startOnSystemBoot;

  DDNSConfig({
    required this.hostname,
    required this.serviceType,
    required this.apiUrl,
    required this.apiKey,
    Map<String, dynamic>? updateRequestConfig,
    this.startOnSystemBoot = false,
  }) : updateRequestConfig = updateRequestConfig ?? <String, dynamic>{};

  /// 校验配置是否完整。
  /// 
  /// 主机名、服务商类型、API 端点、密钥为必填项。
  /// 
  /// 返回校验结果映射：`valid` 为是否通过，`errors` 为错误信息列表。
  Map<String, dynamic> validate() {
    final errors = <String>[];
    if (hostname.trim().isEmpty) errors.add('主机名不能为空');
    if (serviceType.trim().isEmpty) errors.add('服务商类型不能为空');
    if (apiUrl.trim().isEmpty) errors.add('API 端点不能为空');
    if (apiKey.trim().isEmpty) errors.add('API 密钥不能为空');
    
    // 验证服务类型是否支持
    final supportedTypes = ['no-ip', 'duckdns', 'upivy', 'cloudflare', 'custom_api'];
    if (!supportedTypes.contains(serviceType.toLowerCase())) {
      errors.add('不支持的服务商类型：$serviceType');
    }

    return {
      'valid': errors.isEmpty,
      'errors': errors,
    };
  }

  /// 从 JSON 字符串创建配置对象。
  factory DDNSConfig.fromJson(String jsonString) {
    final map = jsonDecode(jsonString) as Map<String, dynamic>;
    final updateRequestConfig = (map['updateRequestConfig'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    return DDNSConfig(
      hostname: map['hostname'] ?? '',
      serviceType: map['serviceType'] ?? '',
      apiUrl: map['apiUrl'] ?? '',
      apiKey: map['apiKey'] ?? '',
      updateRequestConfig: updateRequestConfig,
      startOnSystemBoot: map['startOnSystemBoot'] ?? false,
    );
  }

  /// 将配置序列化为 JSON 字符串（用于调试和导出）。
  String toJson() => jsonEncode(<String, dynamic>{
        'hostname': hostname,
        'serviceType': serviceType,
        'apiUrl': apiUrl,
        'apiKey': apiKey,
        'updateRequestConfig': updateRequestConfig,
        'startOnSystemBoot': startOnSystemBoot,
      });

  /// 将配置序列化为 Provider 使用的 JSON 格式。
  /// 
  /// 此方法用于持久化存储，包含完整的配置信息。
  String toJsonConfig() => jsonEncode(<String, dynamic>{
        'hostname': hostname,
        'serviceType': serviceType,
        'apiUrl': apiUrl,
        'apiKey': apiKey,
        'updateRequestConfig': updateRequestConfig,
        'startOnSystemBoot': startOnSystemBoot,
      });

  /// 创建配置的副本，并更新指定的字段。
  /// 
  /// [fields] 为要更新的字段映射，未包含的字段保持不变。
  /// 
  /// [updateRequestConfig] 为新的更新请求参数映射（若提供则深拷贝）。
  DDNSConfig copyWith(
    Map<String, dynamic> fields, {
    Map<String, dynamic>? updateRequestConfig,
  }) {
    return DDNSConfig(
      hostname: fields['hostname'] ?? hostname,
      serviceType: fields['serviceType'] ?? serviceType,
      apiUrl: fields['apiUrl'] ?? apiUrl,
      apiKey: fields['apiKey'] ?? apiKey,
      updateRequestConfig:
          updateRequestConfig ?? Map<String, dynamic>.from(this.updateRequestConfig),
      startOnSystemBoot: fields['startOnSystemBoot'] ?? startOnSystemBoot,
    );
  }

  /// 将配置克隆为新的实例（深拷贝更新请求配置）。
  DDNSConfig clone() => DDNSConfig(
        hostname: hostname,
        serviceType: serviceType,
        apiUrl: apiUrl,
        apiKey: apiKey,
        updateRequestConfig: Map<String, dynamic>.from(updateRequestConfig),
        startOnSystemBoot: startOnSystemBoot,
      );

  /// 将配置转换为友好的显示名称。
  String get displayName {
    switch (serviceType) {
      case 'no-ip':
        return 'No-IP';
      case 'duckdns':
        return 'DuckDNS';
      case 'upivy':
        return 'UpIvY';
      case 'cloudflare':
        return 'Cloudflare';
      case 'custom_api':
        return '自定义 API';
      default:
        return serviceType;
    }
  }

  /// 获取服务类型显示名称（用于 UI）
  String get serviceTypeDisplayName {
    switch (serviceType.toLowerCase()) {
      case 'no-ip':
        return 'No-IP';
      case 'duckdns':
        return 'DuckDNS';
      case 'upivy':
        return 'UpIvY';
      case 'cloudflare':
        return 'Cloudflare';
      case 'custom_api':
        return '自定义 API';
      default:
        return serviceType;
    }
  }

  /// 获取支持的预设模板列表
  static List<Map<String, dynamic>> get presets => [
        {'name': 'No-IP', 'type': 'no-ip'},
        {'name': 'DuckDNS', 'type': 'duckdns'},
        {'name': 'UpIvY', 'type': 'upivy'},
        {'name': 'Cloudflare', 'type': 'cloudflare'},
        {'name': '自定义 API', 'type': 'custom_api'},
      ];

  @override
  String toString() => 'DDNSConfig(hostname: $hostname, serviceType: $serviceType)';
}
