import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'error_logger_service.dart';
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

  final ErrorLoggerService _errorLogger = ErrorLoggerService();

  @override
  String get name => 'NativeLocationProvider';

  /// 统一日志方法：同时输出到logcat和文件
  void log(String msg) {
    final timestamp = DateTime.now().toString().substring(11, 23);
    print('[$timestamp] [NativeLocationProvider] $msg');
    _errorLogger.logDebug(msg);
  }

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
        print('[NativeLocationProvider] 定位服务未开启');
        await _errorLogger.logGpsFail(reason: 'LOCATION_SERVICE_DISABLED');
        return null;
      }

      // 检查权限
      final hasPermission = await checkPermission();
      if (!hasPermission) {
        print('[NativeLocationProvider] 定位权限被拒绝');
        await _errorLogger.logPermission(permission: 'LOCATION', reason: 'PERMISSION_DENIED');
        return null;
      }

      // 调用原生定位
      // 如果没有传入timeLimit，使用默认超时（GPS 30秒 + 网络15秒 = 45秒）
      final timeoutMs = (timeLimit?.inMilliseconds ?? (_defaultGpsTimeoutMs + _defaultNetTimeoutMs)).toInt();
      final useHighAccuracy = accuracy == ProviderAccuracy.best;

      log('调用原生定位: useHighAccuracy=$useHighAccuracy, timeout=${timeoutMs}ms');
      await _errorLogger.logService(
        action: 'NATIVE_LOCATION_REQUEST',
        extra: 'useHighAccuracy=$useHighAccuracy, timeoutMs=$timeoutMs',
      );

      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('getCurrentLocation', {
        'useHighAccuracy': useHighAccuracy,
        'timeoutMs': timeoutMs,
      }).timeout(
        Duration(milliseconds: timeoutMs + 5000), // 多加5秒缓冲
        onTimeout: () => null, // 超时返回null，让调用方处理
      );

      if (result == null) {
        log('原生定位返回 null');
        await _errorLogger.logGpsFail(reason: 'NATIVE_RETURNED_NULL');
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
        log('原生定位返回无效坐标: lat=$latitude, lng=$longitude');
        await _errorLogger.logGpsFail(reason: 'INVALID_COORDINATES');
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

      log('原生定位成功: lat=$latitude, lng=$longitude, acc=${accuracyVal}m');
      await _errorLogger.logGpsSuccess(
        lat: latitude,
        lng: longitude,
        accuracy: accuracyVal,
      );
      return position;
    } on PlatformException catch (e) {
      print('[NativeLocationProvider] PlatformException: code=${e.code}, message=${e.message}');
      String reason = 'NATIVE_PLATFORM_EXCEPTION';
      if (e.code == 'PERMISSION_DENIED') {
        reason = 'NATIVE_PERMISSION_DENIED';
      } else if (e.code == 'SERVICE_DISABLED') {
        reason = 'NATIVE_SERVICE_DISABLED';
      } else if (e.code == 'TIMEOUT') {
        reason = 'NATIVE_TIMEOUT';
      }
      await _errorLogger.logGpsFail(reason: reason, extra: 'code=${e.code}, msg=${e.message}');
      return null;
    } catch (e, st) {
      print('[NativeLocationProvider] getCurrentPosition 异常: type=${e.runtimeType}, message=$e');
      print('[NativeLocationProvider] stackTrace: $st');
      await _errorLogger.logGpsFail(
        reason: 'EXCEPTION',
        extra: 'type=${e.runtimeType}, msg=$e\n$st',
      );
      return null;
    }
  }

  @override
  Future<bool> checkPermission() async {
    try {
      final result = await _channel.invokeMethod<bool>('checkPermission');
      return result ?? false;
    } catch (e) {
      print('[NativeLocationProvider] checkPermission 异常: $e');
      return false;
    }
  }

  @override
  Future<bool> isLocationServiceEnabled() async {
    try {
      final result = await _channel.invokeMethod<bool>('isLocationServiceEnabled');
      return result ?? false;
    } catch (e) {
      print('[NativeLocationProvider] isLocationServiceEnabled 异常: $e');
      return false;
    }
  }

  @override
  void dispose() {
    // 无需清理资源
  }
}
