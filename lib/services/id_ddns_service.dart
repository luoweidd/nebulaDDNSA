// d:\projectfile\Fluterproject\nebulaDDNSA\lib\services\id_ddns_service.dart
import 'package:nebula_ddns/config/ddns_config.dart';

/// DDNS 服务接口：定义所有 DDNS 服务的标准操作契约。
///
/// 该接口确保服务层解耦，支持任意自定义 API（README.md line 14）。
///
/// 所有实现类必须遵循统一的异步操作语义，返回值为 `Future<bool>`，
/// 其中 `true` 表示操作成功，`false` 表示失败。
abstract class IDDNSService {
  /// 检查当前 DDNS 状态（如是否在线、是否成功更新）。
  ///
  /// 返回 `true` 表示状态正常，`false` 表示异常。
  Future<bool> checkStatus(DDNSConfig config);

  /// 执行 DDNS 更新操作。
  ///
  /// 返回 `true` 表示更新成功，`false` 表示失败。
  Future<bool> updateDDNS(DDNSConfig config);

  /// 获取服务商特定的错误信息。
  String getLastError();

  /// 获取公网 IP 地址。
  ///
  /// 返回纯 IP 字符串（如 `203.0.113.5`），若解析失败返回 `null`。
  Future<String?> getPublicIP();
}
