import 'dart:io';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import '../utils/logger.dart';
import 'error_logger_service.dart';
import 'track_recorder.dart';
import 'user_service.dart';

/// Kotlin 轨迹数据恢复服务
///
/// 负责从 Kotlin 原生层恢复 Flutter 被杀期间积累的轨迹数据
class KotlinTrackRecovery {
  static final KotlinTrackRecovery _instance = KotlinTrackRecovery._();
  factory KotlinTrackRecovery() => _instance;
  KotlinTrackRecovery._();

  static const _methodChannel = MethodChannel('com.kenny.trace_path/location_service');

  /// 获取 Android filesDir 路径
  Future<String?> _getFilesDir() async {
    try {
      final result = await _methodChannel.invokeMethod<String>('getFilesDir');
      return result;
    } catch (e) {
      Log.e(LogTag.FBLS, 'getFilesDir 失败', e);
      return null;
    }
  }

  /// 从 Kotlin 的 CSV 文件恢复轨迹数据
  ///
  /// Kotlin 在 Flutter 被杀期间会持续写入 filesDir/location_tracks/track_YYYY-MM-DD.csv
  Future<void> recover() async {
    try {
      final filesDir = await _getFilesDir();
      if (filesDir == null) return;

      final trackDir = Directory('$filesDir/location_tracks');
      if (!await trackDir.exists()) {
        Log.d(LogTag.TRACK, 'Kotlin 轨迹目录不存在，跳过恢复');
        return;
      }

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      // 只读取今天的 Kotlin 文件（避免读取历史垃圾数据）
      final dateStr =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      final kotlinFile = File('${trackDir.path}/track_$dateStr.csv');

      if (!await kotlinFile.exists()) {
        Log.d(LogTag.TRACK, 'Kotlin 今日轨迹文件不存在: track_$dateStr.csv');
        return;
      }

      final lines = await kotlinFile.readAsLines();
      if (lines.length <= 1) return; // 只有表头

      // 获取当前存储中今日轨迹的最后一个时间戳，用于排重
      final phone = UserService().currentPhoneNumber ?? '1000000';
      int? lastRecordedTimestamp;
      try {
        final existingPoints =
            await TrackRecorder().readDay(phone, today.year, today.month, today.day);
        if (existingPoints.isNotEmpty) {
          lastRecordedTimestamp = existingPoints.last.timestamp.millisecondsSinceEpoch;
          Log.d(LogTag.TRACK,
              '当前存储最后点时间: ${DateTime.fromMillisecondsSinceEpoch(lastRecordedTimestamp)}');
        }
      } catch (e) {
        Log.w(LogTag.TRACK, '读取已有轨迹失败: $e');
      }

      int recoveredCount = 0;
      for (int i = 1; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.isEmpty) continue;

        final parts = line.split(',');
        if (parts.length < 6) continue;

        try {
          final timestamp = int.parse(parts[0]);

          // 跳过比当前存储最新点更早或相等的点（防重复）
          if (lastRecordedTimestamp != null && timestamp <= lastRecordedTimestamp) {
            continue;
          }

          final latitude = double.parse(parts[1]);
          final longitude = double.parse(parts[2]);
          final accuracy = double.parse(parts[3]);
          final altitude = double.parse(parts[4]);
          final speed = double.parse(parts[5]);

          final position = Position(
            latitude: latitude,
            longitude: longitude,
            timestamp: DateTime.fromMillisecondsSinceEpoch(timestamp),
            accuracy: accuracy,
            altitude: altitude,
            speed: speed,
            heading: 0,
            altitudeAccuracy: 0,
            headingAccuracy: 0,
            speedAccuracy: 0,
          );

          await TrackRecorder().record(position);
          recoveredCount++;
        } catch (e) {
          // 解析失败跳过
          Log.e(LogTag.TRACK, '★ 解析 Kotlin 轨迹点失败[$i]', e);
          break;
        }
      }

      if (recoveredCount > 0) {
        Log.i(LogTag.TRACK, '从 Kotlin 侧恢复了 $recoveredCount 个轨迹点');
        await ErrorLoggerService().logService(
            action: 'KOTLIN_TRACK_RECOVERED', extra: 'count=$recoveredCount');
      }

      // 恢复成功后删除 CSV，避免重复恢复
      await _deleteKotlinCsv(kotlinFile, dateStr);
    } catch (e) {
      Log.e(LogTag.TRACK, '恢复 Kotlin 轨迹数据失败', e);
    }
  }

  /// 删除 Kotlin CSV 文件
  Future<void> _deleteKotlinCsv(File kotlinFile, String dateStr) async {
    try {
      await kotlinFile.delete();
      Log.d(LogTag.TRACK, 'Kotlin CSV 已删除: track_$dateStr.csv');
    } catch (e) {
      Log.w(LogTag.TRACK, 'Kotlin CSV 删除失败: $e');
    }
  }
}
