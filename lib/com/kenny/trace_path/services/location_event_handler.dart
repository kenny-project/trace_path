import 'dart:async';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import '../models/location_event.dart';
import '../utils/logger.dart';
import 'error_logger_service.dart';
import 'track_recorder.dart';

/// 定位事件处理器
///
/// 负责处理来自原生 EventChannel 的定位事件
class LocationEventHandler {
  static const _eventChannel = EventChannel('com.kenny.trace_path/location_events');

  final ErrorLoggerService _errorLogger = ErrorLoggerService();

  StreamSubscription<dynamic>? _eventSubscription;
  int _successCount = 0;
  bool _hasFirstLocation = false;

  /// 定位事件回调
  void Function(LocationEvent event)? onLocationEvent;

  /// 启动监听
  void startListening() {
    Log.d(LogTag.location, '★★★ LocationEventHandler.startListening ★★★');
    _eventSubscription?.cancel();
    _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        Log.d(LogTag.location, 'EventChannel received event: ${event.runtimeType}');
        _handleLocationEvent(event);
      },
      onError: (dynamic error) {
        Log.e(LogTag.location, 'EventChannel error', error);
        _errorLogger.logService(action: 'EVENT_CHANNEL_ERROR', extra: 'error=$error');
      },
    );
    Log.d(LogTag.location, 'EventChannel listener registered');
  }

  /// 停止监听
  Future<void> stopListening() async {
    await _eventSubscription?.cancel();
    _eventSubscription = null;
  }

  /// 处理原生服务推送的位置
  void _handleLocationEvent(dynamic event) {
    Log.d(LogTag.location, '★★★ _handleLocationEvent called ★★★ event=${event.runtimeType}: $event');

    if (event is! Map) {
      Log.w(LogTag.location, 'Invalid event type: ${event.runtimeType}');
      return;
    }

    try {
      final latitude = (event['latitude'] as num?)?.toDouble();
      final longitude = (event['longitude'] as num?)?.toDouble();
      final accuracy = (event['accuracy'] as num?)?.toDouble();
      final altitude = (event['altitude'] as num?)?.toDouble() ?? 0.0;
      final speed = (event['speed'] as num?)?.toDouble() ?? 0.0;
      final timestamp = (event['timestamp'] as num?)?.toInt();

      if (latitude == null || longitude == null) {
        Log.w(LogTag.location, 'Invalid location data: $event');
        return;
      }

      Log.d(LogTag.location, '★ 收到EventChannel位置: lat=$latitude, lng=$longitude, acc=$accuracy, time=${timestamp != null ? DateTime.fromMillisecondsSinceEpoch(timestamp).toIso8601String() : "null"}');

      // 构造 Position 对象
      final position = Position(
        latitude: latitude,
        longitude: longitude,
        accuracy: accuracy ?? 0.0,
        altitude: altitude,
        speed: speed,
        heading: 0.0,
        timestamp: timestamp != null
            ? DateTime.fromMillisecondsSinceEpoch(timestamp)
            : DateTime.now(),
        altitudeAccuracy: 0.0,
        headingAccuracy: 0.0,
        speedAccuracy: 0.0,
      );

      _successCount++;

      // 首次定位记录
      if (!_hasFirstLocation) {
        _hasFirstLocation = true;
        _errorLogger.logFirstLocation(
          lat: latitude,
          lng: longitude,
          accuracy: accuracy ?? 0.0,
        );
      }

      // 每10次成功记录一次
      if (_successCount % 10 == 0) {
        _errorLogger.logGpsSuccess(
          lat: latitude,
          lng: longitude,
          accuracy: accuracy ?? 0.0,
          successCount: _successCount,
        );
      }

      // 触发回调
      if (onLocationEvent != null) {
        onLocationEvent!(LocationEvent.position(position));
      }

      // 保存到本地
      _saveToLocal(position);
    } catch (e, s) {
      Log.e(LogTag.location, '处理位置事件异常', e, s);
      _errorLogger.logService(action: 'EVENT_HANDLE_ERROR', extra: 'error=$e');
    }
  }

  /// 保存位置到本地
  Future<void> _saveToLocal(Position position) async {
    try {
      await TrackRecorder().record(position);
    } catch (e, s) {
      Log.e(LogTag.track, '保存位置失败', e, s);
    }
  }

  /// 重置计数器
  void reset() {
    _successCount = 0;
    _hasFirstLocation = false;
  }
}
