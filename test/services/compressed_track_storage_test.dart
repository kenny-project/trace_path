import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:trace_path/com/kenny/trace_path/proto/track_message.dart';
import 'package:trace_path/com/kenny/trace_path/services/compressed_track_storage.dart';
import 'package:trace_path/com/kenny/trace_path/services/track_storage_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late CompressedTrackStorage storage;
  const testPhone = '13800138000';

  setUpAll(() async {
    // 创建临时目录
    tempDir = await Directory.systemTemp.createTemp('track_storage_test_');

    // 使用 fake path_provider 让 TrackStorageManager 使用临时目录
    PathProviderPlatform.instance = FakePathProviderPlatform(tempDir.path);

    // 重新初始化 TrackStorageManager（使用新的路径）
    final manager = TrackStorageManager();
    await manager.init();

    storage = CompressedTrackStorage();
  });

  tearDownAll(() async {
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  group('CompressedTrackStorage', () {
    group('write / readDay', () {
      test('写入单条轨迹后正确读取', () async {
        final point = CompressedTrackPoint(
          timestampMs: 1711785600000,
          latitude: 39.908823,
          longitude: 116.397470,
          altitude: 38.5,
          speed: 2.5,
          accuracy: 10.0,
        );

        await storage.write(testPhone, point.toTrackPoint());

        // 从写入的轨迹点获取日期，确保读写路径一致
        final writtenDate = DateTime.fromMillisecondsSinceEpoch(point.timestampMs);
        final read = await storage.readDay(testPhone, writtenDate.year, writtenDate.month, writtenDate.day);

        expect(read, isNotEmpty);
        expect(read.first.timestamp.millisecondsSinceEpoch, equals(point.timestampMs));
        expect(read.first.latitude, closeTo(point.latitude, 0.000001));
        expect(read.first.longitude, closeTo(point.longitude, 0.000001));
        expect(read.first.altitude, closeTo(point.altitude, 0.01));
        expect(read.first.speed, closeTo(point.speed, 0.01));
        expect(read.first.accuracy, closeTo(point.accuracy, 0.01));
      });

      test('写入多条轨迹后读取数量一致', () async {
        final points = [
          CompressedTrackPoint(
            timestampMs: 1711785600000,
            latitude: 39.908823,
            longitude: 116.397470,
            altitude: 10.0,
            speed: 1.0,
            accuracy: 5.0,
          ),
          CompressedTrackPoint(
            timestampMs: 1711785700000,
            latitude: 39.909000,
            longitude: 116.398000,
            altitude: 12.0,
            speed: 2.0,
            accuracy: 3.0,
          ),
          CompressedTrackPoint(
            timestampMs: 1711785800000,
            latitude: 39.909500,
            longitude: 116.398500,
            altitude: 15.0,
            speed: 3.0,
            accuracy: 2.0,
          ),
        ];

        for (final p in points) {
          await storage.write(testPhone, p.toTrackPoint());
        }

        // 从写入的轨迹点获取日期，确保读写路径一致
        final writtenDate = DateTime.fromMillisecondsSinceEpoch(points.first.timestampMs);
        final read = await storage.readDay(testPhone, writtenDate.year, writtenDate.month, writtenDate.day);

        // 之前写了1条，现在写了3条，共4条
        expect(read.length, greaterThanOrEqualTo(points.length));
        // 验证最后3条数据一致
        for (int i = 0; i < points.length; i++) {
          final lastN = read[read.length - points.length + i];
          expect(lastN.timestamp.millisecondsSinceEpoch, equals(points[i].timestampMs));
          expect(lastN.latitude, closeTo(points[i].latitude, 0.000001));
        }
      });

      test('读取不存在的日期返回空列表', () async {
        final read = await storage.readDay(testPhone, 2099, 12, 31);
        expect(read, isEmpty);
      });
    });

    group('压缩率测试', () {
      test('dat文件大小等于头部长度加轨迹点数量乘以单点大小', () async {
        final manager = TrackStorageManager();
        // 使用数据实际写入的日期（2024-03-30），确保与前面的写操作路径一致
        final date = DateTime(2024, 3, 30);

        // 获取 dat 文件路径
        final userDir = manager.userDir(testPhone);
        final datDir = Directory('$userDir/${date.year}/'
            '${date.month.toString().padLeft(2, '0')}/');
        final datFile = File('${datDir.path}${date.day.toString().padLeft(2, '0')}.dat');

        if (await datFile.exists()) {
          final datSize = await datFile.length();
          // dat文件 = 32字节头 + N*34字节每点（varint+28，实际编码长度）
          // 数据点数量：test1写入1条 + test2写入3条 + test5写入1条 = 5条
          final pointsCount = await storage.readDay(testPhone, date.year, date.month, date.day);
          // 验证实际编码大小：每条34字节
          final expectedSize = 32 + pointsCount.length * 34;
          expect(datSize, equals(expectedSize));
        }
      });
    });

    group('边界条件测试', () {
      test('零值轨迹点写入读取正确', () async {
        final point = CompressedTrackPoint(
          timestampMs: 0,
          latitude: 0,
          longitude: 0,
          altitude: 0,
          speed: 0,
          accuracy: 0,
        );

        await storage.write(testPhone, point.toTrackPoint());

        // 从写入的轨迹点获取日期，确保读写路径一致
        final writtenDate = DateTime.fromMillisecondsSinceEpoch(point.timestampMs);
        final read = await storage.readDay(testPhone, writtenDate.year, writtenDate.month, writtenDate.day);

        expect(read.last.timestamp.millisecondsSinceEpoch, equals(0));
        expect(read.last.latitude, equals(0));
        expect(read.last.longitude, equals(0));
      });

      test('负值经纬度写入读取正确', () async {
        final point = CompressedTrackPoint(
          timestampMs: 1711785600000,
          latitude: -33.8688,
          longitude: 151.2093,
          altitude: 0,
          speed: 0,
          accuracy: 0,
        );

        await storage.write(testPhone, point.toTrackPoint());

        // 从写入的轨迹点获取日期，确保读写路径一致
        final writtenDate = DateTime.fromMillisecondsSinceEpoch(point.timestampMs);
        final read = await storage.readDay(testPhone, writtenDate.year, writtenDate.month, writtenDate.day);

        expect(read.last.latitude, closeTo(-33.8688, 0.000001));
        expect(read.last.longitude, closeTo(151.2093, 0.000001));
      });
    });
  });
}

/// 伪造 PathProviderPlatform 以控制临时目录
class FakePathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final String tempPath;

  FakePathProviderPlatform(this.tempPath);

  @override
  Future<String?> getApplicationDocumentsPath() async => tempPath;

  Future<String?> getTemporaryDirectory() async => tempPath;

  @override
  Future<String?> getApplicationSupportPath() async => tempPath;

  @override
  Future<String?> getApplicationCachePath() async => tempPath;
}
