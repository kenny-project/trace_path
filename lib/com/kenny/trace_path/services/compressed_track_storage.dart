import 'dart:io';
import 'dart:typed_data';
import 'package:geolocator/geolocator.dart';
import 'track_storage_manager.dart';
import 'track_recorder.dart';
import '../proto/track_message.dart';

/// 压缩轨迹点消息
class CompressedTrackPoint {
  final int timestampMs;
  final double latitude;
  final double longitude;
  final double altitude;
  final double speed;
  final double accuracy;

  CompressedTrackPoint({
    required this.timestampMs,
    required this.latitude,
    required this.longitude,
    this.altitude = 0,
    this.speed = 0,
    this.accuracy = 0,
  });

  factory CompressedTrackPoint.fromPosition(Position position) {
    return CompressedTrackPoint(
      timestampMs: position.timestamp.millisecondsSinceEpoch,
      latitude: position.latitude,
      longitude: position.longitude,
      altitude: position.altitude,
      speed: position.speed,
      accuracy: position.accuracy,
    );
  }

  /// 从 TrackPoint 转换
  factory CompressedTrackPoint.fromTrackPoint(TrackPoint point) {
    return CompressedTrackPoint(
      timestampMs: point.timestamp.millisecondsSinceEpoch,
      latitude: point.latitude,
      longitude: point.longitude,
      altitude: point.altitude,
      speed: point.speed,
      accuracy: point.accuracy,
    );
  }

  /// 转换为 TrackPoint
  TrackPoint toTrackPoint() {
    return TrackPoint(
      timestamp: DateTime.fromMillisecondsSinceEpoch(timestampMs),
      latitude: latitude,
      longitude: longitude,
      altitude: altitude,
      speed: speed,
      accuracy: accuracy,
    );
  }

  TrackPointMessage toMessage() {
    return TrackPointMessage(
      timestampMs: timestampMs,
      latitude: latitude,
      longitude: longitude,
      altitude: altitude,
      speed: speed,
      accuracy: accuracy,
    );
  }
}

/// 压缩存储实现
/// 使用二进制 Protobuf 风格编码，大幅减少存储空间
class CompressedTrackStorage implements TrackStorage {
  static const int _fileVersion = 1;
  static const int _headerSize = 32; // 固定头大小
  static const int _pointSize = 44; // 固定点大小（varint + 5*8/4）

  CompressedTrackStorage();

  /// 获取存储管理器
  TrackStorageManager get _manager => TrackStorageManager();

  @override
  Future<void> write(String phoneNumber, TrackPoint point) async {
    try {
      final compressed = CompressedTrackPoint.fromTrackPoint(point);
      final dirPath = _manager.userDir(phoneNumber);
      final dir = Directory(dirPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final filePath = _manager.dayFilePath(phoneNumber, point.timestamp);
      final file = File(filePath.replaceAll('.csv', '.dat'));

      // 确保日期目录存在
      final fileDir = file.parent;
      if (!await fileDir.exists()) {
        await fileDir.create(recursive: true);
      }

      final (encoded, _) = compressed.toMessage().encode();

      // 检查文件是否存在
      bool needsHeader = !await file.exists() || await file.length() == 0;

      if (needsHeader) {
        // 写入文件头
        final header = _createHeader(phoneNumber);
        await file.writeAsBytes(header, mode: FileMode.append);
      }

      // 追加写入轨迹点
      await file.writeAsBytes(encoded, mode: FileMode.append);

      print('[CompressedTrackStorage] 写入轨迹点: ts=${compressed.timestampMs}, lat=${compressed.latitude}');
    } catch (e) {
      print('[CompressedTrackStorage] 写入失败: $e');
    }
  }

  @override
  Future<List<TrackPoint>> readDay(String phoneNumber, int year, int month, int day) async {
    try {
      final filePath = _manager.dayFilePathByYMD(phoneNumber, year, month, day);
      final file = File(filePath.replaceAll('.csv', '.dat'));

      if (!await file.exists()) {
        return [];
      }

      final bytes = await file.readAsBytes();
      if (bytes.length < _headerSize) {
        return [];
      }

      // 跳过文件头，读取轨迹点
      final points = <TrackPoint>[];
      int offset = _headerSize;

      while (offset < bytes.length) {
        final (point, encodedSize) = TrackPointMessage.decode(bytes, offset);
        if (point != null) {
          points.add(CompressedTrackPoint(
            timestampMs: point.timestampMs,
            latitude: point.latitude,
            longitude: point.longitude,
            altitude: point.altitude,
            speed: point.speed,
            accuracy: point.accuracy,
          ).toTrackPoint());
          offset += encodedSize;
        } else {
          // 解码失败，尝试跳过当前点（按最小可能大小跳过）
          offset += 29; // 最小点大小: 1(varint) + 28
        }
      }

      return points;
    } catch (e) {
      print('[CompressedTrackStorage] 读取失败: $e');
      return [];
    }
  }

  @override
  Future<void> deleteDay(String phoneNumber, int year, int month, int day) async {
    try {
      final filePath = _manager.dayFilePathByYMD(phoneNumber, year, month, day);
      final file = File(filePath.replaceAll('.csv', '.dat'));

      if (await file.exists()) {
        await file.delete();
        print('[CompressedTrackStorage] 删除轨迹文件: ${file.path}');
      }
    } catch (e) {
      print('[CompressedTrackStorage] 删除失败: $e');
    }
  }

  @override
  Future<String> getTrackFilePath(String phoneNumber, int year, int month, int day) async {
    final path = _manager.dayFilePathByYMD(phoneNumber, year, month, day);
    return path.replaceAll('.csv', '.dat');
  }

  @override
  Future<DateTime?> getFileModifyTime(String phoneNumber, int year, int month, int day) async {
    try {
      final filePath = _manager.dayFilePathByYMD(phoneNumber, year, month, day);
      final file = File(filePath.replaceAll('.csv', '.dat'));

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
    print('[CompressedTrackStorage] syncToServer: 待实现');
  }

  @override
  Future<void> pullFromServer(String phoneNumber) async {
    // TODO: 实现服务器拉取
    print('[CompressedTrackStorage] pullFromServer: 待实现');
  }

  /// 创建文件头
  Uint8List _createHeader(String phoneNumber) {
    final buffer = ByteData(_headerSize);
    int offset = 0;

    // Version: 4 bytes
    buffer.setInt32(offset, _fileVersion, Endian.little);
    offset += 4;

    // Phone number length: 4 bytes
    final phoneBytes = phoneNumber.codeUnits;
    buffer.setInt32(offset, phoneBytes.length, Endian.little);
    offset += 4;

    // Phone number: variable (max 20 bytes)
    for (int i = 0; i < phoneBytes.length && i < 20; i++) {
      buffer.setUint8(offset + i, phoneBytes[i]);
    }
    offset += 20;

    // Reserved: 4 bytes
    offset += 4;

    return buffer.buffer.asUint8List();
  }

  /// 获取压缩率（对比原始 CSV）
  Future<double> getCompressionRatio(String phoneNumber, int year, int month, int day) async {
    try {
      final csvPath = _manager.dayFilePathByYMD(phoneNumber, year, month, day);
      final datPath = csvPath.replaceAll('.csv', '.dat');

      final csvFile = File(csvPath);
      final datFile = File(datPath);

      if (!await csvFile.exists() || !await datFile.exists()) {
        return 0;
      }

      final csvSize = await csvFile.length();
      final datSize = await datFile.length();

      if (csvSize == 0) return 0;

      return 1 - (datSize / csvSize);
    } catch (e) {
      return 0;
    }
  }
}
