import 'dart:async';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import '../utils/logger.dart';
import 'location_provider.dart';

/// Geolocator 定位提供者实现
/// 通过 Geolocator 包实现定位，策略：GPS → 网络 fallback
///
/// 超时时间设置参考（来自高德/百度建议）：
/// - GPS首次定位：通常30-60秒，信号差环境（地铁/室内）可能更长
/// - 网络定位：10-15秒
class GeolocatorLocationProvider implements LocationProvider {
  @override
  String get name => 'GeolocatorLocationProvider';

  @override
  Future<Position?> getCurrentPosition({
    ProviderAccuracy accuracy = ProviderAccuracy.best,
    Duration? timeLimit,
  }) async {
    try {
      // === 检查定位服务 ===
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        Log.w(LogTag.FBLS, '定位服务未开启');
        return null;
      }

      // === 检查权限 ===
      final hasPermission = await _checkPermission();
      if (!hasPermission) {
        Log.w(LogTag.FBLS, '定位权限被拒绝');
        return null;
      }

      // === 策略1: 优先 GPS（精度阈值 50m）===
      Position? position = await _getGpsPosition();
      if (position != null && position.accuracy < 50) {
        Log.i(LogTag.FBLS, 'GPS 定位成功: acc=${position.accuracy}m');
        return position;
      }

      // === 策略2: GPS 失败或精度差 → 网络定位（接受 <200m 的结果）===
      Log.d(LogTag.FBLS, 'GPS 定位失败或精度差（acc=${position?.accuracy ?? 'null'}m），尝试网络定位...');
      position = await _getNetworkPosition();
      if (position != null && position.accuracy < 200) {
        Log.i(LogTag.FBLS, '网络定位成功: acc=${position.accuracy}m');
        return position;
      }

      Log.w(LogTag.FBLS, '所有定位方式均失败');
      return null;
    } catch (e, st) {
      Log.e(LogTag.FBLS, 'getCurrentPosition 异常: type=${e.runtimeType}, message=$e, stackTrace: $st');
      return null;
    }
  }

  Future<Position?> _getGpsPosition() async {
    try {
      Log.d(LogTag.FBLS, '尝试 GPS 定位: accuracy=best, timeLimit=45s');
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
      Log.e(LogTag.FBLS, 'GPS 定位失败: reason=$reason, type=${e.runtimeType}, message=$e');
      return null;
    }
  }

  Future<Position?> _getNetworkPosition() async {
    try {
      Log.d(LogTag.FBLS, '尝试网络定位: accuracy=medium, timeLimit=45s');
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
      Log.e(LogTag.FBLS, '网络定位失败: reason=$reason, type=${e.runtimeType}, message=$e');
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
      Log.e(LogTag.FBLS, '权限检查异常: $e');
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
      Log.e(LogTag.FBLS, 'isLocationServiceEnabled 异常: $e');
      return false;
    }
  }

  @override
  void dispose() {
    // 无需清理资源
  }
}
