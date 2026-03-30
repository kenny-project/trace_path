import 'dart:io';
import 'package:trace_path/com/kenny/trace_path/services/track_recorder.dart';

/// TrackService 的测试版本，使用注入的路径而非 path_provider
/// 这样可以避免 path_provider 在测试环境中的问题
class TestableTrackService {
  final String testBasePath;
  static const String _folderName = 'location_tracks';

  TestableTrackService(this.testBasePath);

  /// 获取轨迹根目录
  String get _tracksRootDir => '$testBasePath/$_folderName';

  /// 获取指定手机号的轨迹目录
  String _phoneDir(String phoneNumber) => '$_tracksRootDir/$phoneNumber';

  /// 保存一条定位记录
  /// [timestamp] 可选，默认为当前时间
  Future<bool> saveLocation({
    required String phoneNumber,
    required double lat,
    required double lng,
    required double altitude,
    required double speed,
    required double accuracy,
    DateTime? timestamp,
  }) async {
    try {
      final now = timestamp ?? DateTime.now();
      final path = _phoneDir(phoneNumber);
      final dir = Directory(path);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      // 路径格式: {phoneNumber}/{year}/{month}/{day}.csv
      final datePath =
          '${now.year}/${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')}.csv';
      final file = File('$path/$datePath');

      // 确保月份目录存在
      final monthDir = file.parent;
      if (!await monthDir.exists()) {
        await monthDir.create(recursive: true);
      }

      bool needsHeader = !await file.exists() || await file.length() == 0;

      final tsString = now.toIso8601String();
      final dataRow =
          '$tsString,${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)},${altitude.toStringAsFixed(2)},${speed.toStringAsFixed(2)},${accuracy.toStringAsFixed(1)}';

      String content = '';
      if (needsHeader) {
        content =
            'timestamp,latitude,longitude,altitude,speed,accuracy\n$dataRow\n';
      } else {
        content = '$dataRow\n';
      }

      await file.writeAsString(content, mode: FileMode.append);
      return true;
    } catch (e) {
      print('[TestableTrackService] 保存失败: $e');
      return false;
    }
  }

  /// 读取指定日期的轨迹数据（返回原始 WGS84 坐标，不做 GCJ-02 转换）
  /// 与 LocalCsvStorage.readDay 保持一致
  Future<List<TrackPoint>> readDayTrack(
      String phoneNumber, int year, int month, int day) async {
    try {
      final path = _phoneDir(phoneNumber);
      final datePath =
          '$year/${month.toString().padLeft(2, '0')}/${day.toString().padLeft(2, '0')}.csv';
      final fullPath = '$path/$datePath';

      final file = File(fullPath);
      if (!await file.exists()) {
        return [];
      }

      final content = await file.readAsString();
      final lines = content
          .split(RegExp(r'\r?\n'))
          .where((l) => l.trim().isNotEmpty)
          .toList();

      if (lines.isEmpty) return [];

      final firstLine = lines.first;
      final isHeader =
          firstLine.contains('timestamp') || firstLine.contains('latitude');
      final dataLines = isHeader ? lines.skip(1) : lines;

      final points = <TrackPoint>[];
      for (final line in dataLines) {
        if (line.trim().isEmpty) continue;
        final parts = line.split(',');
        if (parts.length < 6) continue;
        try {
          points.add(TrackPoint(
            timestamp: DateTime.parse(parts[0].trim()),
            latitude: double.parse(parts[1].trim()),
            longitude: double.parse(parts[2].trim()),
            altitude: double.parse(parts[3].trim()),
            speed: double.parse(parts[4].trim()),
            accuracy: double.parse(parts[5].trim()),
          ));
        } catch (e) {
          print('[TestableTrackService] 解析行失败: $line, $e');
        }
      }

      points.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      return points;
    } catch (e) {
      print('[TestableTrackService] 读取失败: $e');
      return [];
    }
  }

  /// 删除指定日期的轨迹文件
  Future<bool> deleteDayTrack(
      String phoneNumber, int year, int month, int day) async {
    try {
      final path = _phoneDir(phoneNumber);
      final datePath =
          '$year/${month.toString().padLeft(2, '0')}/${day.toString().padLeft(2, '0')}.csv';
      final file = File('$path/$datePath');
      if (await file.exists()) {
        await file.delete();
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// 获取文件修改时间
  Future<DateTime?> getFileModifyTime(
      String phoneNumber, int year, int month, int day) async {
    try {
      final path = _phoneDir(phoneNumber);
      final datePath =
          '$year/${month.toString().padLeft(2, '0')}/${day.toString().padLeft(2, '0')}.csv';
      final file = File('$path/$datePath');
      if (await file.exists()) {
        final stat = await file.stat();
        return stat.modified;
      }
    } catch (e) {
      // ignore
    }
    return null;
  }
}
