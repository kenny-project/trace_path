import 'package:geolocator/geolocator.dart';

/// 定位精度枚举（对应 Geolocator 的 LocationAccuracy）
enum ProviderAccuracy {
  low,      // 低精度 = 网络定位级别
  medium,   // 中精度
  best,     // 最高精度 = GPS
}

/// 定位提供者抽象接口
/// 通过策略模式，支持 Geolocator 和 Android 原生两种实现
abstract class LocationProvider {
  /// 获取当前位置
  /// [accuracy] 定位精度
  /// [timeLimit] 超时限制
  /// 返回 Position 对象，失败返回 null
  Future<Position?> getCurrentPosition({
    ProviderAccuracy accuracy = ProviderAccuracy.best,
    Duration? timeLimit,
  });

  /// 检查定位权限
  /// 返回 true 表示有权限
  Future<bool> checkPermission();

  /// 定位服务是否启用
  /// 返回 true 表示服务已启用
  Future<bool> isLocationServiceEnabled();

  /// 销毁/清理资源
  Future<void> dispose();
}
