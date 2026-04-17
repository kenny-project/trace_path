import 'dart:io';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import '../utils/coordinate_utils.dart';
import 'user_service.dart';
import 'track_storage_manager.dart';
import 'compressed_track_storage.dart';

/// 轨迹点数据
class TrackPoint {
  final DateTime timestamp;
  final double latitude;
  final double longitude;
  final double altitude;
  final double speed;
  final double accuracy;

  TrackPoint({
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    this.altitude = 0,
    this.speed = 0,
    this.accuracy = 0,
  });

  /// 从 Position 创建
  factory TrackPoint.fromPosition(Position position) {
    return TrackPoint(
      timestamp: position.timestamp,
      latitude: position.latitude,
      longitude: position.longitude,
      altitude: position.altitude,
      speed: position.speed,
      accuracy: position.accuracy,
    );
  }

  /// 转换为 LatLng
  LatLng toLatLng() => LatLng(latitude, longitude);

  /// 创建转换后的轨迹点（WGS84 → GCJ-02）
  TrackPoint toGcj02() {
    final gcj02 = CoordinateUtils.wgs84ToGcj02(latitude, longitude);
    return TrackPoint(
      timestamp: timestamp,
      latitude: gcj02[0],
      longitude: gcj02[1],
      altitude: altitude,
      speed: speed,
      accuracy: accuracy,
    );
  }

  /// WGS84 转 GCJ-02（委托给 CoordinateUtils）
  static List<double> wgs84ToGcj02(double lat, double lng) {
    return CoordinateUtils.wgs84ToGcj02(lat, lng);
  }

  /// 转换为 CSV 行
  String toCsvLine() {
    final ts = '${timestamp.year}-${_padZero(timestamp.month)}-${_padZero(timestamp.day)}'
        'T${_padZero(timestamp.hour)}:${_padZero(timestamp.minute)}:'
        '${_padZero(timestamp.second)}.${timestamp.millisecond.toString().padLeft(3, '0')}';
    return '$ts,${latitude.toStringAsFixed(6)},${longitude.toStringAsFixed(6)},'
        '${altitude.toStringAsFixed(2)},${speed.toStringAsFixed(2)},${accuracy.toStringAsFixed(1)}';
  }

  String _padZero(int n) => n.toString().padLeft(2, '0');
}

/// 轨迹存储接口
/// 为未来服务器同步预留扩展
abstract class TrackStorage {
  /// 写入轨迹点
  Future<void> write(String phoneNumber, TrackPoint point);

  /// 读取某天的轨迹
  Future<List<TrackPoint>> readDay(String phoneNumber, int year, int month, int day);

  /// 删除某天的轨迹
  Future<void> deleteDay(String phoneNumber, int year, int month, int day);

  /// 获取轨迹文件路径
  Future<String> getTrackFilePath(String phoneNumber, int year, int month, int day);

  /// 读取轨迹文件修改时间
  Future<DateTime?> getFileModifyTime(String phoneNumber, int year, int month, int day);

  // ========== 未来扩展（服务器同步）==========
  /// 上报到服务器（待实现）
  Future<void> syncToServer(String phoneNumber);

  /// 从服务器拉取（待实现）
  Future<void> pullFromServer(String phoneNumber);
}

/// 本地 CSV 存储实现
class LocalCsvStorage implements TrackStorage {
  static const String _csvHeader = 'timestamp,latitude,longitude,altitude,speed,accuracy';

  LocalCsvStorage();

  /// 获取存储管理器
  TrackStorageManager get _manager => TrackStorageManager();

  @override
  Future<void> write(String phoneNumber, TrackPoint point) async {
    // 过滤无效坐标写入
    if (point.latitude.isNaN || point.latitude.isInfinite ||
        point.longitude.isNaN || point.longitude.isInfinite ||
        (point.latitude == 0 && point.longitude == 0)) {
      print('[LocalCsvStorage] 跳过无效坐标: lat=${point.latitude}, lng=${point.longitude}');
      return;
    }

    try {
      final dirPath = _manager.userDir(phoneNumber);
      final trackDir = Directory(
        '$dirPath/'
        '${point.timestamp.year}/'
        '${_padZero(point.timestamp.month)}',
      );

      if (!await trackDir.exists()) {
        await trackDir.create(recursive: true);
      }

      final file = File('${trackDir.path}/${_padZero(point.timestamp.day)}.csv');
      final needsHeader = !await file.exists() || await file.length() == 0;

      if (needsHeader) {
        await file.writeAsString('$_csvHeader\n', mode: FileMode.append);
      }

      await file.writeAsString('${point.toCsvLine()}\n', mode: FileMode.append);

      print('[LocalCsvStorage] 写入轨迹点: ${point.toCsvLine()}');
    } catch (e) {
      print('[LocalCsvStorage] 写入失败: $e');
    }
  }

  @override
  Future<List<TrackPoint>> readDay(String phoneNumber, int year, int month, int day) async {
    try {
      final filePath = await getTrackFilePath(phoneNumber, year, month, day);
      final file = File(filePath);

      if (!await file.exists()) {
        return [];
      }

      final lines = await file.readAsLines();
      if (lines.length <= 1) return [];

      final points = <TrackPoint>[];
      // 跳过表头
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
      print('[LocalCsvStorage] 读取失败: $e');
      return [];
    }
  }

  @override
  Future<void> deleteDay(String phoneNumber, int year, int month, int day) async {
    try {
      final filePath = await getTrackFilePath(phoneNumber, year, month, day);
      final file = File(filePath);

      if (await file.exists()) {
        await file.delete();
        print('[LocalCsvStorage] 删除轨迹文件: $filePath');
      }
    } catch (e) {
      print('[LocalCsvStorage] 删除失败: $e');
    }
  }

  @override
  Future<String> getTrackFilePath(String phoneNumber, int year, int month, int day) async {
    return _manager.dayFilePathByYMD(phoneNumber, year, month, day);
  }

  @override
  Future<DateTime?> getFileModifyTime(String phoneNumber, int year, int month, int day) async {
    try {
      final filePath = await getTrackFilePath(phoneNumber, year, month, day);
      final file = File(filePath);

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
    // TODO: 实现服务器上报
    print('[LocalCsvStorage] syncToServer: 待实现');
  }

  @override
  Future<void> pullFromServer(String phoneNumber) async {
    // TODO: 实现服务器拉取
    print('[LocalCsvStorage] pullFromServer: 待实现');
  }

  /// 解析 CSV 行
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
      print('[LocalCsvStorage] 解析 CSV 行失败: $line, error: $e');
      return null;
    }
  }

  String _padZero(int n) => n.toString().padLeft(2, '0');
}

/// 轨迹录制器（单例）
/// 统一管理轨迹数据的录制和存储
class TrackRecorder {
  static final TrackRecorder _instance = TrackRecorder._();
  factory TrackRecorder() => _instance;
  TrackRecorder._();

  // 默认使用压缩存储
  TrackStorage _storage = CompressedTrackStorage();

  /// 设置存储实现（支持切换存储方式）
  void setStorage(TrackStorage storage) {
    _storage = storage;
  }

  /// 录制一个轨迹点
  Future<void> record(Position position) async {
    final phone = UserService().currentPhoneNumber ?? '1000000';
    final point = TrackPoint.fromPosition(position);
    await _storage.write(phone, point);
  }

  /// 录制指定手机号的轨迹点
  Future<void> recordFor(String phoneNumber, Position position) async {
    final point = TrackPoint.fromPosition(position);
    await _storage.write(phoneNumber, point);
  }

  /// 读取某天的轨迹
  Future<List<TrackPoint>> readDay(String phoneNumber, int year, int month, int day) {
    return _storage.readDay(phoneNumber, year, month, day);
  }

  /// 删除某天的轨迹
  Future<void> deleteDay(String phoneNumber, int year, int month, int day) {
    return _storage.deleteDay(phoneNumber, year, month, day);
  }

  /// 获取轨迹文件修改时间
  Future<DateTime?> getFileModifyTime(String phoneNumber, int year, int month, int day) {
    return _storage.getFileModifyTime(phoneNumber, year, month, day);
  }

  /// 同步到服务器
  Future<void> syncToServer(String phoneNumber) {
    return _storage.syncToServer(phoneNumber);
  }

  /// 从服务器拉取
  Future<void> pullFromServer(String phoneNumber) {
    return _storage.pullFromServer(phoneNumber);
  }
}
