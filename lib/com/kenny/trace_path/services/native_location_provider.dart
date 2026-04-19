import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import '../utils/logger.dart';
import 'location_provider.dart';

/// Android 原生定位提供者实现
/// 通过 MethodChannel 调用 Android 原生 FusedLocationProviderClient
///
/// 超时时间设置参考（来自高德/百度建议）：
/// - GPS首次定位：通常30-60秒，信号差环境（地铁/室内）可能更长
/// - 网络定位：10-15秒
/// - 整体超时：建议30-45秒
class NativeLocationProvider implements LocationProvider {
  static const _channel = MethodChannel('com.kenny.trace_path/native_location');

  @override
  String get name => 'NativeLocationProvider';

  // 默认超时时间：GPS 30秒 + 网络15秒 = 总共45秒
  static const int _defaultGpsTimeoutMs = 30000;
  static const int _defaultNetTimeoutMs = 15000;

  @override
  Future<Position?> getCurrentPosition({
    ProviderAccuracy accuracy = ProviderAccuracy.best,
    Duration? timeLimit,
  }) async {
    try {
      // 检查服务是否启用
      final serviceEnabled = await isLocationServiceEnabled();
      if (!serviceEnabled) {
        Log.w(LogTag.FBLS, '定位服务未开启');
        return null;
      }

      // 检查权限
      final hasPermission = await checkPermission();
      if (!hasPermission) {
        Log.w(LogTag.FBLS, '定位权限被拒绝');
        return null;
      }

      // 调用原生定位
      // 如果没有传入timeLimit，使用默认超时（GPS 30秒 + 网络15秒 = 45秒）
      final timeoutMs = (timeLimit?.inMilliseconds ?? (_defaultGpsTimeoutMs + _defaultNetTimeoutMs)).toInt();
      final useHighAccuracy = accuracy == ProviderAccuracy.best;

      Log.d(LogTag.FBLS, 'getCurrentPosition: useHighAccuracy=$useHighAccuracy, timeout=${timeoutMs}ms');

      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('getCurrentLocation', {
        'useHighAccuracy': useHighAccuracy,
        'timeoutMs': timeoutMs,
      }).timeout(
        Duration(milliseconds: timeoutMs + 5000), // 多加5秒缓冲
        onTimeout: () => null, // 超时返回null，让调用方处理
      );

      if (result == null) {
        Log.w(LogTag.FBLS, 'getCurrentPosition fail, result is null');
        return null;
      }

      // 解析原生返回的位置数据
      final latitude = (result['latitude'] as num?)?.toDouble();
      final longitude = (result['longitude'] as num?)?.toDouble();
      final accuracyVal = (result['accuracy'] as num?)?.toDouble() ?? 0.0;
      final altitude = (result['altitude'] as num?)?.toDouble() ?? 0.0;
      final speed = (result['speed'] as num?)?.toDouble() ?? 0.0;
      final heading = (result['heading'] as num?)?.toDouble() ?? 0.0;
      final timestamp = (result['timestamp'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;

      if (latitude == null || longitude == null) {
        Log.e(LogTag.FBLS, 'getCurrentPosition fail,  pos=$latitude, $longitude');
        return null;
      }

      // 构造 Position 对象（与 Geolocator 兼容）
      final position = Position(
        latitude: latitude,
        longitude: longitude,
        timestamp: DateTime.fromMillisecondsSinceEpoch(timestamp),
        accuracy: accuracyVal,
        altitude: altitude,
        heading: heading,
        speed: speed,
        speedAccuracy: 0.0, // Android 原生不提供
        altitudeAccuracy: 0.0,
        headingAccuracy: 0.0, // Android 原生不提供
      );

      Log.i(LogTag.FBLS, '原生定位成功: lat=$latitude, lng=$longitude, acc=${accuracyVal}m');
      return position;
    } on PlatformException catch (e) {
      Log.e(LogTag.FBLS, 'PlatformException: code=${e.code}, message=${e.message}');
      return null;
    } catch (e, st) {
      Log.e(LogTag.FBLS, 'Exception type=${e.runtimeType}, message=$e, stackTrace: $st');
      return null;
    }
  }

  @override
  Future<bool> checkPermission() async {
    try {
      var permission = await Permission.location.status;
      if (permission.isDenied) {
        permission = await Permission.location.request();
        if (permission.isDenied) return false;
      }
      if (permission.isPermanentlyDenied) return false;
      return true;
    } catch (e) {
      Log.e(LogTag.FBLS, 'checkPermission 异常: $e');
      return false;
    }
  }

  @override
  Future<bool> isLocationServiceEnabled() async {
    try {
      final result = await _channel.invokeMethod<bool>('isLocationServiceEnabled');
      return result ?? false;
    } catch (e) {
      Log.e(LogTag.FBLS, 'isLocationServiceEnabled 异常: $e');
      return false;
    }
  }

  @override
  void dispose() {
    // 无需清理资源
  }
}
