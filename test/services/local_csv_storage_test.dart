import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:trace_path/com/kenny/trace_path/services/track_recorder.dart';
import '../mocks/mock_local_csv_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  
  group('LocalCsvStorage', () {
    late Directory tempDir;
    late TestableLocalCsvStorage storage;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('track_test_');
      storage = TestableLocalCsvStorage(tempDir.path);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    group('write', () {
      test('写入轨迹点生成 CSV 文件', () async {
        final point = TrackPoint(
          timestamp: DateTime(2024, 3, 30, 10, 0, 0),
          latitude: 39.908823,
          longitude: 116.397470,
          altitude: 50.0,
          speed: 5.0,
          accuracy: 10.0,
        );

        await storage.write('13800138000', point);

        final file = File('${tempDir.path}/location_tracks/13800138000/2024/03/30.csv');
        expect(await file.exists(), isTrue);
      });

      test('首次写入添加 CSV 表头', () async {
        final point = TrackPoint(
          timestamp: DateTime(2024, 3, 30, 10, 0, 0),
          latitude: 39.908823,
          longitude: 116.397470,
        );

        await storage.write('13800138000', point);

        final file = File('${tempDir.path}/location_tracks/13800138000/2024/03/30.csv');
        final content = await file.readAsString();
        expect(content, contains('timestamp,latitude,longitude,altitude,speed,accuracy'));
      });

      test('追加写入不重复添加表头', () async {
        final point1 = TrackPoint(
          timestamp: DateTime(2024, 3, 30, 10, 0, 0),
          latitude: 39.908823,
          longitude: 116.397470,
        );
        final point2 = TrackPoint(
          timestamp: DateTime(2024, 3, 30, 10, 1, 0),
          latitude: 39.908824,
          longitude: 116.397471,
        );

        await storage.write('13800138000', point1);
        await storage.write('13800138000', point2);

        final file = File('${tempDir.path}/location_tracks/13800138000/2024/03/30.csv');
        final lines = (await file.readAsString()).split('\n');
        final nonEmptyLines = lines.where((l) => l.isNotEmpty).toList();
        expect(nonEmptyLines.length, equals(3)); // 表头 + 2条数据
      });
    });

    group('readDay', () {
      test('读取 CSV 文件解析出轨迹点', () async {
        final point1 = TrackPoint(
          timestamp: DateTime(2024, 3, 30, 10, 0, 0),
          latitude: 39.908823,
          longitude: 116.397470,
          altitude: 50.0,
          speed: 5.0,
          accuracy: 10.0,
        );
        final point2 = TrackPoint(
          timestamp: DateTime(2024, 3, 30, 10, 1, 0),
          latitude: 39.908824,
          longitude: 116.397471,
          altitude: 51.0,
          speed: 6.0,
          accuracy: 11.0,
        );

        await storage.write('13800138000', point1);
        await storage.write('13800138000', point2);

        final points = await storage.readDay('13800138000', 2024, 3, 30);

        expect(points.length, equals(2));
        expect(points[0].latitude, equals(39.908823));
        expect(points[1].latitude, equals(39.908824));
      });

      test('文件不存在返回空列表', () async {
        final points = await storage.readDay('99999999999', 2024, 3, 30);
        expect(points, isEmpty);
      });
    });

    group('deleteDay', () {
      test('删除存在的轨迹文件', () async {
        final point = TrackPoint(
          timestamp: DateTime(2024, 3, 30, 10, 0, 0),
          latitude: 39.908823,
          longitude: 116.397470,
        );

        await storage.write('13800138000', point);
        
        var file = File('${tempDir.path}/location_tracks/13800138000/2024/03/30.csv');
        expect(await file.exists(), isTrue);

        await storage.deleteDay('13800138000', 2024, 3, 30);

        expect(await file.exists(), isFalse);
      });

      test('删除不存在的文件不报错', () async {
        await expectLater(
          storage.deleteDay('99999999999', 2024, 3, 30),
          completes,
        );
      });
    });

    group('getTrackFilePath', () {
      test('返回正确的文件路径', () async {
        final path = await storage.getTrackFilePath('13800138000', 2024, 3, 30);
        expect(path, contains('location_tracks'));
        expect(path, contains('13800138000'));
        expect(path, contains('2024'));
        expect(path, contains('03'));
        expect(path, contains('30.csv'));
      });
    });

    group('getFileModifyTime', () {
      test('文件存在时返回修改时间', () async {
        final point = TrackPoint(
          timestamp: DateTime(2024, 3, 30, 10, 0, 0),
          latitude: 39.908823,
          longitude: 116.397470,
        );

        await storage.write('13800138000', point);
        final modifyTime = await storage.getFileModifyTime('13800138000', 2024, 3, 30);

        expect(modifyTime, isNotNull);
      });

      test('文件不存在时返回 null', () async {
        final modifyTime = await storage.getFileModifyTime('99999999999', 2024, 3, 30);
        expect(modifyTime, isNull);
      });
    });
  });
}
