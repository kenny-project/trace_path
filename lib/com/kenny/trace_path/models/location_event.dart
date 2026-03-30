import 'package:geolocator/geolocator.dart';

/// 定位事件类型
enum LocationEventType {
  locationUpdate,  // 位置更新
  error,           // 定位错误
  serviceStart,    // 服务启动
  serviceStop,     // 服务停止
}

/// 定位事件
class LocationEvent {
  final LocationEventType type;
  final Position? position;
  final String? errorMessage;
  final DateTime timestamp;

  LocationEvent({
    required this.type,
    this.position,
    this.errorMessage,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// 位置更新事件
  factory LocationEvent.position(Position position) {
    return LocationEvent(
      type: LocationEventType.locationUpdate,
      position: position,
    );
  }

  /// 错误事件
  factory LocationEvent.error(String message) {
    return LocationEvent(
      type: LocationEventType.error,
      errorMessage: message,
    );
  }

  /// 服务启动事件
  factory LocationEvent.serviceStart() {
    return LocationEvent(type: LocationEventType.serviceStart);
  }

  /// 服务停止事件
  factory LocationEvent.serviceStop() {
    return LocationEvent(type: LocationEventType.serviceStop);
  }

  /// 是否是位置更新事件
  bool get isPositionUpdate => type == LocationEventType.locationUpdate;

  /// 纬度
  double? get latitude => position?.latitude;

  /// 经度
  double? get longitude => position?.longitude;

  /// 精度
  double? get accuracy => position?.accuracy;

  /// 速度
  double? get speed => position?.speed;
}
