import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:trace_path/com/kenny/trace_path/services/track_recorder.dart';

/// LocalCsvStorage 的测试版本，使用注入的路径
class TestableLocalCsvStorage implements TrackStorage {
  final String testBasePath;
  
  TestableLocalCsvStorage(this.testBasePath);

  @override
  Future<void> write(String phoneNumber, TrackPoint point) async {
    try {
      final trackDir = Directory(
        '$testBasePath/location_tracks/$phoneNumber/'
        '${point.timestamp.year}/'
        '${_padZero(point.timestamp.month)}',
      );

      if (!await trackDir.exists()) {
        await trackDir.create(recursive: true);
      }

      final file = File('${trackDir.path}/${_padZero(point.timestamp.day)}.csv');
      final needsHeader = !await file.exists() || await file.length() == 0;

      if (needsHeader) {
        await file.writeAsString('timestamp,latitude,longitude,altitude,speed,accuracy\n', mode: FileMode.append);
      }

      await file.writeAsString('${point.toCsvLine()}\n', mode: FileMode.append);
    } catch (e) {
      print('[TestableLocalCsvStorage] 写入失败: $e');
    }
  }

  @override
  Future<List<TrackPoint>> readDay(String phoneNumber, int year, int month, int day) async {
    try {
      final file = File('$testBasePath/location_tracks/$phoneNumber/$year/${_padZero(month)}/${_padZero(day)}.csv');

      if (!await file.exists()) {
        return [];
      }

      final lines = await file.readAsLines();
      if (lines.length <= 1) return [];

      final points = <TrackPoint>[];
      for (int i = 1; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.isEmpty) continue;

        final point = _parseCsvLine(line);
        if (point != null) {
          points.add(point);
        }
      }

      return points;
    } catch (e) {
      print('[TestableLocalCsvStorage] 读取失败: $e');
      return [];
    }
  }

  @override
  Future<void> deleteDay(String phoneNumber, int year, int month, int day) async {
    try {
      final file = File('$testBasePath/location_tracks/$phoneNumber/$year/${_padZero(month)}/${_padZero(day)}.csv');

      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      print('[TestableLocalCsvStorage] 删除失败: $e');
    }
  }

  @override
  Future<String> getTrackFilePath(String phoneNumber, int year, int month, int day) async {
    return '$testBasePath/location_tracks/$phoneNumber/$year/${_padZero(month)}/${_padZero(day)}.csv';
  }

  @override
  Future<DateTime?> getFileModifyTime(String phoneNumber, int year, int month, int day) async {
    try {
      final file = File('$testBasePath/location_tracks/$phoneNumber/$year/${_padZero(month)}/${_padZero(day)}.csv');

      if (await file.exists()) {
        final stat = await file.stat();
        return stat.modified;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  @override
  Future<void> syncToServer(String phoneNumber) async {
    print('[TestableLocalCsvStorage] syncToServer: 待实现');
  }

  @override
  Future<void> pullFromServer(String phoneNumber) async {
    print('[TestableLocalCsvStorage] pullFromServer: 待实现');
  }

  TrackPoint? _parseCsvLine(String line) {
    try {
      final parts = line.split(',');
      if (parts.length < 6) return null;

      return TrackPoint(
        timestamp: DateTime.parse(parts[0]),
        latitude: double.parse(parts[1]),
        longitude: double.parse(parts[2]),
        altitude: double.parse(parts[3]),
        speed: double.parse(parts[4]),
        accuracy: double.parse(parts[5]),
      );
    } catch (e) {
      return null;
    }
  }

  String _padZero(int n) => n.toString().padLeft(2, '0');
}
