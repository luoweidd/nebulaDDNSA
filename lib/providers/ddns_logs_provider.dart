// d:\projectfile\Fluterproject\nebulaDDNSA\lib\providers\ddns_logs_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// DDNSLogsProvider: 集中管理 DDNS 日志记录。
/// 
/// 企业级特性：
/// - 实时日志流
/// - 日志数量限制（防止内存溢出）
/// - 简单字符串格式（便于 UI 展示）
final ddnsLogsProvider = StateNotifierProvider<DDNSLogsNotifier, List<String>>((ref) {
  return DDNSLogsNotifier();
});

/// DDNSLogsNotifier: 封装日志管理逻辑。
class DDNSLogsNotifier extends StateNotifier<List<String>> {
  static const int maxLogCount = 100; // 限制日志数量，防止内存溢出

  DDNSLogsNotifier() : super([]);

  /// 添加日志（默认 INFO 级别）
  void add(String message) {
    state.insert(0, message);
    if (state.length > maxLogCount) {
      state.removeRange(maxLogCount, state.length);
    }
    state = List<String>.from(state); // 触发 UI 更新
  }

  /// 清空所有日志
  void clear() {
    state = [];
  }

  /// 获取最后一条日志
  String? getLast() {
    return state.isNotEmpty ? state.first : null;
  }

  /// 获取日志数量
  int get count => state.length;
}