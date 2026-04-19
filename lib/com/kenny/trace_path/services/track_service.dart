import 'dart:io';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import '../utils/logger.dart';
import 'track_recorder.dart';
import 'track_storage_manager.dart';

// 导出 TrackPoint，保持向后兼容
export 'track_recorder.dart' show TrackPoint;

/// 轨迹服务
class TrackService {
  static final TrackService _instance = TrackService._();
  factory TrackService() => _instance;
  TrackService._();

  /// 获取存储管理器
  TrackStorageManager get _manager => TrackStorageManager();

  /// 获取指定手机号的轨迹目录
  String _phoneDir(String phoneNumber) {
    return _manager.userDir(phoneNumber);
  }

  /// 删除指定日期的轨迹文件
  Future<bool> deleteDayTrack(String phoneNumber, int year, int month, int day) async {
    try {
      await TrackRecorder().deleteDay(phoneNumber, year, month, day);
      return true;
    } catch (e) {
      Log.e(LogTag.TRACK, 'TrackService 删除失败: $e');
      return false;
    }
  }

  /// 保存一条定位记录
  Future<bool> saveLocation({
    required String phoneNumber,
    required double lat,
    required double lng,
    required double altitude,
    required double speed,
    required double accuracy,
  }) async {
    try {
      final now = DateTime.now();
      // 通过 TrackRecorder 保存（现在是 CompressedTrackStorage）
      await TrackRecorder().record(Position(
        latitude: lat,
        longitude: lng,
        altitude: altitude,
        speed: speed,
        accuracy: accuracy,
        timestamp: now,
        heading: 0,
        headingAccuracy: 0,
        altitudeAccuracy: 0,
        speedAccuracy: 0,
      ));
      Log.d(LogTag.TRACK, 'TrackService 保存成功: lat=$lat, lng=$lng');
      return true;
    } catch (e) {
      Log.e(LogTag.TRACK, 'TrackService 保存失败: $e');
      return false;
    }
  }

  /// 读取指定日期的轨迹数据
  Future<List<TrackPoint>> readDayTrack(String phoneNumber, int year, int month, int day) async {
    try {
      // 通过 TrackRecorder 读取（现在是 CompressedTrackStorage）
      final points = await TrackRecorder().readDay(phoneNumber, year, month, day);
      Log.d(LogTag.TRACK, 'TrackService 读取轨迹: ${points.length} 个点');

      if (points.isEmpty) {
        return [];
      }

      points.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      // WGS84 → GCJ-02 坐标转换（用于高德/腾讯地图显示）
      final convertedPoints = points.map((p) => p.toGcj02()).toList();

      // 过滤无效坐标（NaN、Infinity、越界坐标、跳变过大等）
      final validPoints = <TrackPoint>[];
      const double maxJumpMeters = 5000; // 单次跳变超过5km视为异常

      for (int i = 0; i < convertedPoints.length; i++) {
        final p = convertedPoints[i];

        // 1. NaN / Infinity 检查
        if (p.latitude.isNaN || p.latitude.isInfinite) continue;
        if (p.longitude.isNaN || p.longitude.isInfinite) continue;

        // 2. 坐标越界检查（中国区域大致范围，防止漂移到海洋）
        if (p.latitude < -90 || p.latitude > 90) continue;
        if (p.longitude < -180 || p.longitude > 180) continue;

        // 3. (0,0) 海洋坐标过滤（GPS未锁定常见值）
        if (p.latitude == 0 && p.longitude == 0) continue;

        // 4. 相邻点跳变过大检查（仅对时间间隔<60秒的点进行）
        if (validPoints.isNotEmpty) {
          final lastPoint = validPoints.last;
          final timeDiffSeconds = p.timestamp.difference(lastPoint.timestamp).inSeconds;

          // 时间间隔小于60秒才检查跳变，时间间隔长说明可能是GPS中断或移动了，不应过滤
          if (timeDiffSeconds < 60) {
            const distance = Distance();
            final jump = distance.as(
              LengthUnit.Meter,
              lastPoint.toLatLng(),
              p.toLatLng(),
            );
            if (jump > maxJumpMeters) {
              Log.w(LogTag.TRACK, 'TrackService 跳过跳变过大的点: ${jump.toStringAsFixed(0)}m (时间间隔: ${timeDiffSeconds}s)');
              continue;
            }
          }
          // 时间间隔 >= 60秒，直接保留，不检查跳变
        }

        validPoints.add(p);
      }

      final removed = convertedPoints.length - validPoints.length;
      if (removed > 0) {
        Log.d(LogTag.TRACK, 'TrackService 过滤掉 $removed 个无效坐标点');
      }

      Log.d(LogTag.TRACK, 'TrackService 转换成功: ${validPoints.length} 个点');
      return validPoints;
    } catch (e) {
      Log.e(LogTag.TRACK, 'TrackService 读取失败: $e');
      return [];
    }
  }

  /// 获取所有轨迹文件列表（按人员、年、月、日分级）
  Future<Map<String, Map<String, Map<String, List<String>>>>> getTrackHierarchy() async {
    final hierarchy = <String, Map<String, Map<String, List<String>>>>{};

    try {
      final root = TrackStorageManager().rootPath;
      final rootDir = Directory(root);
      if (!await rootDir.exists()) return hierarchy;

      // 遍历手机号目录
      for (final phoneEntity in await rootDir.list().toList()) {
        if (phoneEntity is! Directory) continue;
        final phoneNumber = phoneEntity.path.split('/').last;

        hierarchy[phoneNumber] = <String, Map<String, List<String>>>{};
        final yearDirs = await phoneEntity.list().toList();

        for (final yearEntity in yearDirs) {
          if (yearEntity is! Directory) continue;
          final year = yearEntity.path.split('/').last;
          if (int.tryParse(year) == null) continue;

          hierarchy[phoneNumber]![year] = <String, List<String>>{};
          final monthDirs = await yearEntity.list().toList();

          for (final monthEntity in monthDirs) {
            if (monthEntity is! Directory) continue;
            final month = monthEntity.path.split('/').last;
            if (int.tryParse(month) == null) continue;

            hierarchy[phoneNumber]![year]![month] = <String>[];
            final datFiles = await monthEntity.list().toList();

            for (final file in datFiles) {
              if (file is File && file.path.endsWith('.dat')) {
                final day = file.path.split('/').last.replaceAll('.dat', '');
                hierarchy[phoneNumber]![year]![month]!.add(day);
              }
            }
            // 按日期降序排列
            hierarchy[phoneNumber]![year]![month]!.sort((a, b) => b.compareTo(a));
          }
        }
      }
    } catch (e) {
      Log.e(LogTag.TRACK, 'TrackService 获取层级失败: $e');
    }

    return hierarchy;
  }

  /// 获取有轨迹数据的手机号列表
  Future<List<String>> getPhonesWithTracks() async {
    final hierarchy = await getTrackHierarchy();
    return hierarchy.keys.toList();
  }

  /// 获取指定日期轨迹文件的修改时间
  Future<DateTime?> getFileModifyTime(String phoneNumber, int year, int month, int day) async {
    try {
      return await TrackRecorder().getFileModifyTime(phoneNumber, year, month, day);
    } catch (e) {
      Log.e(LogTag.TRACK, 'TrackService 获取文件修改时间失败: $e');
    }
    return null;
  }

  /// 获取指定手机号的年列表（按最新年份排序）
  Future<List<String>> getYearsWithTracks(String phoneNumber) async {
    final hierarchy = await getTrackHierarchy();
    if (!hierarchy.containsKey(phoneNumber)) return [];
    final years = hierarchy[phoneNumber]!.keys.toList();
    years.sort((a, b) => b.compareTo(a)); // 降序
    return years;
  }

  /// 获取指定手机号和年份的月列表
  Future<List<String>> getMonthsWithTracks(String phoneNumber, String year) async {
    final hierarchy = await getTrackHierarchy();
    if (!hierarchy.containsKey(phoneNumber) || !hierarchy[phoneNumber]!.containsKey(year)) return [];
    final months = hierarchy[phoneNumber]![year]!.keys.toList();
    months.sort((a, b) => b.compareTo(a)); // 降序
    return months;
  }

  /// 获取指定手机号、年、月的日列表
  Future<List<String>> getDaysWithTracks(String phoneNumber, String year, String month) async {
    final hierarchy = await getTrackHierarchy();
    if (!hierarchy.containsKey(phoneNumber) || !hierarchy[phoneNumber]!.containsKey(year)) return [];
    final days = hierarchy[phoneNumber]![year]![month] ?? [];
    return days;
  }
}
