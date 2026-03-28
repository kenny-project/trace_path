import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'location_settings_service.dart';

/// 后台定位服务（使用原生 Android 前台服务）
/// 通过 MethodChannel 控制 LocationForegroundService
class BackgroundLocationService {
  static final BackgroundLocationService _instance = BackgroundLocationService._();
  factory BackgroundLocationService() => _instance;
  BackgroundLocationService._();

  static const _channel = MethodChannel('com.example.trace_path/location_service');

  final LocationSettingsService _settingsService = LocationSettingsService();

  /// 初始化
  Future<void> init() async {
    await _settingsService.load();
  }

  /// 启动服务
  Future<bool> start() async {
    try {
      // 检查权限
      final hasPermission = await _checkPermission();
      if (!hasPermission) {
        print('[BackgroundLocationService] start: 权限检查失败');
        return false;
      }

      // Android 13+ 需要通知权限
      if (Platform.isAndroid) {
        final notifStatus = await Permission.notification.status;
        print('[BackgroundLocationService] 通知权限状态: $notifStatus');
        if (notifStatus.isDenied) {
          print('[BackgroundLocationService] 请求通知权限...');
          final result = await Permission.notification.request();
          print('[BackgroundLocationService] 通知权限请求结果: $result');
        }
      }

      // 确认最新设置值
      await _settingsService.load();
      final interval = _settingsService.settings.intervalSeconds;
      final powerSaving = _settingsService.settings.powerSaving;

      print('[BackgroundLocationService] start: interval=${interval}s, powerSaving=$powerSaving');

      // 启动原生前台服务（带配置）
      await _channel.invokeMethod('start', {
        'interval': interval,
        'powerSaving': powerSaving,
      });

      print('[BackgroundLocationService] start: invokeMethod(start) 完成');
      return true;
    } catch (e) {
      print('[BackgroundLocationService] start 异常: $e');
      return false;
    }
  }

  /// 停止服务
  Future<void> stop() async {
    try {
      await _settingsService.update(enabled: false);
      await _channel.invokeMethod('stop');
    } catch (e) {
      print('[BackgroundLocationService] stop 异常: $e');
    }
  }

  /// 检查权限
  Future<bool> _checkPermission() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return false;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return false;
      }

      if (permission == LocationPermission.deniedForever) return false;

      return true;
    } catch (e) {
      print('[BackgroundLocationService] 权限检查异常: $e');
      return false;
    }
  }

  /// 更新设置（热更新）
  Future<void> updateSettings({
    int? intervalSeconds,
    bool? powerSaving,
  }) async {
    await _settingsService.update(
      intervalSeconds: intervalSeconds,
      powerSaving: powerSaving,
    );

    // 通知原生服务更新配置
    try {
      await _channel.invokeMethod('updateConfig', {
        'interval': _settingsService.settings.intervalSeconds,
        'powerSaving': _settingsService.settings.powerSaving,
      });
    } catch (e) {
      print('[BackgroundLocationService] updateConfig 异常: $e');
    }
  }

  /// 是否正在运行
  Future<bool> checkRunning() async {
    try {
      final result = await _channel.invokeMethod<bool>('isRunning');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  Future<void> dispose() async {
    await stop();
  }
}
