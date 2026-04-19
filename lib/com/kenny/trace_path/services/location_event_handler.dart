import 'dart:async';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import '../models/location_event.dart';
import '../utils/logger.dart';
import 'track_recorder.dart';

/// 定位事件处理器
///
/// 负责处理来自原生 EventChannel 的定位事件
class LocationEventHandler {
  static const _eventChannel = EventChannel('com.kenny.trace_path/location_events');

  StreamSubscription<dynamic>? _eventSubscription;
  int _successCount = 0;
  bool _hasFirstLocation = false;

  /// 定位事件回调
  void Function(LocationEvent event)? onLocationEvent;

  /// 启动监听
  void startListening() {
    Log.d(LogTag.FLEH, '★★★ LocationEventHandler.startListening ★★★');
    _eventSubscription?.cancel();
    _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        Log.d(LogTag.FLEH, 'EventChannel received event: ${event.runtimeType}');
        _handleLocationEvent(event);
      },
      onError: (dynamic error) {
        Log.e(LogTag.FLEH, 'EventChannel error: $error');
      },
    );
    Log.d(LogTag.FLEH, 'EventChannel listener registered');
  }

  /// 停止监听
  Future<void> stopListening() async {
    await _eventSubscription?.cancel();
    _eventSubscription = null;
  }

  /// 处理原生服务推送的位置
  void _handleLocationEvent(dynamic event) {
    Log.d(LogTag.FLEH, '_handleLocationEvent called event=${event.runtimeType}: $event');

    if (event is! Map) {
      Log.w(LogTag.FLEH, 'Invalid event type: ${event.runtimeType}');
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
        Log.w(LogTag.FLEH, 'Invalid location data: $event');
        return;
      }

      Log.d(LogTag.FLEH, 'Received location event: lat=$latitude, lng=$longitude, acc=$accuracy, time=${timestamp != null ? DateTime.fromMillisecondsSinceEpoch(timestamp).toIso8601String() : "null"}');

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
        Log.i(LogTag.FLEH, 'handleLocationEvent debug, first location success: lat=$latitude, lng=$longitude, acc=${accuracy ?? 0.0}m');
      }

      // 每10次成功记录一次
      if (_successCount % 1 == 0) {
        Log.d(LogTag.FLEH, 'handleLocationEvent debug, location success: $_successCount: pos=$latitude, $longitude, acc=${accuracy ?? 0.0}m');
      }

      // 触发回调
      if (onLocationEvent != null) {
        onLocationEvent!(LocationEvent.position(position));
      }
      else {
        Log.w(LogTag.FLEH, 'handleLocationEvent debug, no callback registered for location event');
      }

      // 保存到本地
      _saveToLocal(position);
    } catch (e, s) {
      Log.e(LogTag.FLEH, 'handleLocationEvent debug, error processing location event', e, s);
    }
  }

  /// 保存位置到本地
  Future<void> _saveToLocal(Position position) async {
    try {
      await TrackRecorder().record(position);
    } catch (e, s) {
      Log.e(LogTag.FLEH, 'saveToLocal debug, error saving location to local storage', e, s);
    }
  }

  /// 重置计数器
  void reset() {
    _successCount = 0;
    _hasFirstLocation = false;
    Log.d(LogTag.FLEH, 'handleLocationEvent debug, reset location event handler');
  }
}
