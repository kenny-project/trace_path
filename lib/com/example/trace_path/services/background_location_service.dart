import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'location_settings_service.dart';
import 'csv_storage_service.dart';

/// 后台定位服务
/// 使用 flutter_background_service 实现前台服务 + 通知栏常驻
class BackgroundLocationService {
  static final BackgroundLocationService _instance = BackgroundLocationService._();
  factory BackgroundLocationService() => _instance;
  BackgroundLocationService._();

  final CsvStorageService _csvService = CsvStorageService();
  final LocationSettingsService _settingsService = LocationSettingsService();
  final FlutterBackgroundService _bgService = FlutterBackgroundService();

  bool _isStationary = false;
  int _stationaryCount = 0;
  static const int _stationaryThreshold = 3;
  static const int _maxIntervalWhenStationary = 3600;

  /// 初始化（在 main() 里调用）
  Future<void> init() async {
    await _settingsService.load();
    await _bgService.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: 'location_service_channel',
        initialNotificationTitle: 'TracePath',
        initialNotificationContent: '实时定位服务运行中',
        foregroundServiceNotificationId: 888,
        foregroundServiceTypes: [AndroidForegroundType.location],
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );
  }

  /// 后台服务入口（运行在后台 isolate）
  @pragma('vm:entry-point')
  static Future<void> onStart(ServiceInstance service) async {
    final csvService = CsvStorageService();
    final settingsService = LocationSettingsService();
    await settingsService.load();

    StreamSubscription<Position>? positionSub;

    // 设置前台通知参数
    if (service is AndroidServiceInstance) {
      await service.setForegroundNotificationInfo(
        title: 'TracePath 正在后台定位',
        content: '实时追踪服务运行中',
      );
      await service.setAsForegroundService();
    }

    // 监听来自主isolate的命令
    service.on('update_notification').listen((data) async {
      if (data != null && service is AndroidServiceInstance) {
        final speed = (data['speed'] as double?) ?? 0;
        final accuracy = (data['accuracy'] as double?) ?? 0;
        final speedText = speed < 0.5 ? '静止' : '${speed.toStringAsFixed(1)}m/s';
        await service.setForegroundNotificationInfo(
          title: 'TracePath 正在定位',
          content: '速度: $speedText | 精度: ${accuracy.toStringAsFixed(0)}m',
        );
      }
    });

    service.on('stop').listen((_) {
      positionSub?.cancel();
      service.stopSelf();
    });

    service.on('start_tracking').listen((_) async {
      positionSub?.cancel();

      await _startTracking(csvService, settingsService, service);
    });

    service.on('restart_tracking').listen((_) async {
      positionSub?.cancel();
      await _startTracking(csvService, settingsService, service);
    });
  }

  static Future<void> _startTracking(
    CsvStorageService csvService,
    LocationSettingsService settingsService,
    ServiceInstance service,
  ) async {
    final interval = settingsService.settings.intervalSeconds;
    final distanceFilter = settingsService.settings.powerSaving ? 20.0 : 10.0;

    final locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: distanceFilter.toInt(),
      timeLimit: Duration(seconds: interval),
    );

    Geolocator.getPositionStream(locationSettings: locationSettings)
        .listen((position) {
      // 省电模式
      if (settingsService.settings.powerSaving) {
        // 静止检测并动态调整
      }

      // 保存CSV
      csvService.saveLocation(
        lat: position.latitude,
        lng: position.longitude,
        altitude: position.altitude,
        speed: position.speed,
        accuracy: position.accuracy,
      );

      // 更新通知
      service.invoke('update_notification', {
        'speed': position.speed,
        'accuracy': position.accuracy,
      });
    });
  }

  /// iOS 后台回调
  @pragma('vm:entry-point')
  static Future<bool> onIosBackground(ServiceInstance service) async {
    return true;
  }

  /// 启动服务
  Future<bool> start() async {
    try {
      final hasPermission = await _checkPermission();
      if (!hasPermission) return false;
    } catch (e) {
      print('[BackgroundLocationService] 权限检查异常: $e');
      return false;
    }

    await _settingsService.update(enabled: true);

    final ok = await _bgService.startService();
    if (ok) {
      _bgService.invoke('start_tracking');
    }
    return ok;
  }

  /// 停止服务
  Future<void> stop() async {
    _bgService.invoke('stop');
    await _settingsService.update(enabled: false);
  }

  /// 检查权限
  Future<bool> _checkPermission() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return false;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        try {
          permission = await Geolocator.requestPermission();
        } catch (e) {
          print('[BackgroundLocationService] requestPermission 异常: $e');
          return false;
        }
        if (permission == LocationPermission.denied) return false;
      }

      if (permission == LocationPermission.deniedForever) return false;

      return true;
    } catch (e) {
      print('[BackgroundLocationService] 权限检查异常: $e');
      return false;
    }
  }

  /// 更新设置并热更新追踪参数
  Future<void> updateSettings({
    int? intervalSeconds,
    bool? powerSaving,
  }) async {
    await _settingsService.update(
      intervalSeconds: intervalSeconds,
      powerSaving: powerSaving,
    );
    // 通知后台重新开始追踪（使用新参数）
    final running = await _bgService.isRunning();
    if (running) {
      _bgService.invoke('restart_tracking');
    }
  }

  /// 是否正在运行
  Future<bool> checkRunning() async {
    return await _bgService.isRunning();
  }

  Future<void> dispose() async {
    await stop();
  }
}
