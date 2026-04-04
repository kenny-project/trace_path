import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'error_logger_service.dart';
import 'location_provider.dart';

/// Geolocator 定位提供者实现
/// 通过 Geolocator 包实现定位，策略：GPS → 网络 fallback
/// 
/// 超时时间设置参考（来自高德/百度建议）：
/// - GPS首次定位：通常30-60秒，信号差环境（地铁/室内）可能更长
/// - 网络定位：10-15秒
class GeolocatorLocationProvider implements LocationProvider {
  final ErrorLoggerService _errorLogger = ErrorLoggerService();

  @override
  Future<Position?> getCurrentPosition({
    ProviderAccuracy accuracy = ProviderAccuracy.best,
    Duration? timeLimit,
  }) async {
    try {
      // === 检查定位服务 ===
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('[GeolocatorLocationProvider] 定位服务未开启');
        await _errorLogger.logGpsFail(reason: 'LOCATION_SERVICE_DISABLED');
        return null;
      }

      // === 检查权限 ===
      final hasPermission = await _checkPermission();
      if (!hasPermission) {
        print('[GeolocatorLocationProvider] 定位权限被拒绝');
        await _errorLogger.logPermission(permission: 'LOCATION', reason: 'PERMISSION_DENIED');
        return null;
      }

      // === 策略1: 优先 GPS（精度阈值 50m）===
      Position? position = await _getGpsPosition();
      if (position != null && position.accuracy < 50) {
        print('[GeolocatorLocationProvider] GPS 定位成功: acc=${position.accuracy}m');
        return position;
      }

      // === 策略2: GPS 失败或精度差 → 网络定位（接受 <200m 的结果）===
      print('[GeolocatorLocationProvider] GPS 定位失败或精度差（acc=${position?.accuracy ?? 'null'}m），尝试网络定位...');
      position = await _getNetworkPosition();
      if (position != null && position.accuracy < 200) {
        print('[GeolocatorLocationProvider] 网络定位成功: acc=${position.accuracy}m');
        return position;
      }

      print('[GeolocatorLocationProvider] 所有定位方式均失败');
      await _errorLogger.logGpsFail(reason: 'ALL_METHODS_FAILED');
      return null;
    } catch (e, st) {
      print('[GeolocatorLocationProvider] getCurrentPosition 异常: type=${e.runtimeType}, message=$e');
      print('[GeolocatorLocationProvider] stackTrace: $st');
      await _errorLogger.logGpsFail(
        reason: 'EXCEPTION',
        extra: 'type=${e.runtimeType}, msg=$e\n$st',
      );
      return null;
    }
  }

  Future<Position?> _getGpsPosition() async {
    try {
      print('[GeolocatorLocationProvider] 尝试 GPS 定位: accuracy=best, timeLimit=45s');
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: const Duration(seconds: 45),
      );
      return position;
    } catch (e, st) {
      String reason;
      if (e is TimeoutException) {
        reason = 'GPS_TIMEOUT';
      } else if (e is PlatformException && e.code == 'PERMISSION_DENIED') {
        reason = 'GPS_PERMISSION_DENIED';
      } else if (e is PlatformException && e.code == 'LOCATION_SERVICE_DISABLED') {
        reason = 'GPS_SERVICE_DISABLED';
      } else {
        reason = 'GPS_UNKNOWN';
      }
      print('[GeolocatorLocationProvider] GPS 定位失败: reason=$reason');
      print('[GeolocatorLocationProvider] GPS FAIL: type=${e.runtimeType}, message=$e');
      print('[GeolocatorLocationProvider] GPS FAIL stackTrace:\n$st');
      await _errorLogger.logGpsFail(
        reason: reason,
        accuracy: null,
        timeout: 45,
        extra: 'type=${e.runtimeType}\n$e\n$st',
      );
      return null;
    }
  }

  Future<Position?> _getNetworkPosition() async {
    try {
      print('[GeolocatorLocationProvider] 尝试网络定位: accuracy=medium, timeLimit=45s');
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 45),
      );
      return position;
    } catch (e, st) {
      String reason;
      if (e is TimeoutException) {
        reason = 'NETWORK_TIMEOUT';
      } else if (e is PlatformException && e.code == 'PERMISSION_DENIED') {
        reason = 'NETWORK_PERMISSION_DENIED';
      } else if (e is PlatformException && e.code == 'NETWORK') {
        reason = 'NETWORK_UNAVAILABLE';
      } else {
        reason = 'NETWORK_UNKNOWN';
      }
      print('[GeolocatorLocationProvider] 网络定位失败: reason=$reason');
      print('[GeolocatorLocationProvider] Network FAIL: type=${e.runtimeType}, message=$e');
      print('[GeolocatorLocationProvider] Network FAIL stackTrace:\n$st');
      await _errorLogger.logNetworkFail(
        reason: reason,
        timeout: 45,
        extra: 'type=${e.runtimeType}\n$e\n$st',
      );
      return null;
    }
  }

  Future<bool> _checkPermission() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return false;
      }
      if (permission == LocationPermission.deniedForever) return false;
      return true;
    } catch (e) {
      print('[GeolocatorLocationProvider] 权限检查异常: $e');
      return false;
    }
  }

  @override
  Future<bool> checkPermission() async {
    return _checkPermission();
  }

  @override
  Future<bool> isLocationServiceEnabled() async {
    try {
      return await Geolocator.isLocationServiceEnabled();
    } catch (e) {
      print('[GeolocatorLocationProvider] isLocationServiceEnabled 异常: $e');
      return false;
    }
  }

  @override
  Future<void> dispose() async {
    // 无需清理资源
  }
}
