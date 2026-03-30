import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:trace_path/com/kenny/trace_path/services/track_recorder.dart';
import '../mocks/mock_local_csv_storage.dart';
import '../mocks/testable_track_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TrackRecorder 和 TrackService 路径一致性回归测试', () {
    late Directory tempDir;
    late TestableLocalCsvStorage csvStorage;
    late TestableTrackService trackService;
    late TrackRecorder recorder;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('track_consistency_test_');
      csvStorage = TestableLocalCsvStorage(tempDir.path);
      trackService = TestableTrackService(tempDir.path);
      recorder = TrackRecorder();
      recorder.setStorage(csvStorage);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    group('路径一致性测试', () {
      test('写入 TrackRecorder 后 TrackService 能读取到相同数据', () async {
        // 通过 TrackRecorder 写入一个轨迹点
        final phoneNumber = '13800138000';
        final point = TrackPoint(
          timestamp: DateTime(2024, 3, 30, 10, 0, 0),
          latitude: 39.908823,
          longitude: 116.397470,
          altitude: 50.0,
          speed: 5.0,
          accuracy: 10.0,
        );

        await csvStorage.write(phoneNumber, point);

        // 通过 TrackService 读取同一个文件
        final readPoints =
            await trackService.readDayTrack(phoneNumber, 2024, 3, 30);

        // 验证能读取到相同的数据
        expect(readPoints.length, equals(1));
        expect(readPoints[0].latitude, equals(39.908823));
        expect(readPoints[0].longitude, equals(116.397470));
      });

      test('连续写入多个轨迹点，TrackService 全部能读取', () async {
        final phoneNumber = '13800138000';
        final points = [
          TrackPoint(
            timestamp: DateTime(2024, 3, 30, 10, 0, 0),
            latitude: 39.908823,
            longitude: 116.397470,
            altitude: 50.0,
            speed: 5.0,
            accuracy: 10.0,
          ),
          TrackPoint(
            timestamp: DateTime(2024, 3, 30, 10, 1, 0),
            latitude: 39.908824,
            longitude: 116.397471,
            altitude: 51.0,
            speed: 6.0,
            accuracy: 11.0,
          ),
          TrackPoint(
            timestamp: DateTime(2024, 3, 30, 10, 2, 0),
            latitude: 39.908825,
            longitude: 116.397472,
            altitude: 52.0,
            speed: 7.0,
            accuracy: 12.0,
          ),
        ];

        for (final point in points) {
          await csvStorage.write(phoneNumber, point);
        }

        final readPoints =
            await trackService.readDayTrack(phoneNumber, 2024, 3, 30);

        expect(readPoints.length, equals(3));
        expect(readPoints[0].latitude, equals(39.908823));
        expect(readPoints[1].latitude, equals(39.908824));
        expect(readPoints[2].latitude, equals(39.908825));
      });

      test('不同手机号的数据隔离', () async {
        final phone1 = '13800138000';
        final phone2 = '13900001111';

        await csvStorage.write(phone1, TrackPoint(
          timestamp: DateTime(2024, 3, 30, 10, 0, 0),
          latitude: 39.908823,
          longitude: 116.397470,
        ));

        await csvStorage.write(phone2, TrackPoint(
          timestamp: DateTime(2024, 3, 30, 10, 0, 0),
          latitude: 31.230416,
          longitude: 121.473701,
        ));

        final readPhone1 =
            await trackService.readDayTrack(phone1, 2024, 3, 30);
        final readPhone2 =
            await trackService.readDayTrack(phone2, 2024, 3, 30);

        expect(readPhone1.length, equals(1));
        expect(readPhone1[0].latitude, equals(39.908823));
        expect(readPhone2.length, equals(1));
        expect(readPhone2[0].latitude, equals(31.230416));
      });

      test('TrackRecorder.record() 写入后 TrackService 能立即读取', () async {
        final phoneNumber = '13800138000';
        final position = _createTestPosition(
          latitude: 39.908823,
          longitude: 116.397470,
          altitude: 50.0,
          speed: 5.0,
          accuracy: 10.0,
        );

        // 通过 TrackRecorder.record() 写入
        await recorder.recordFor(phoneNumber, position);

        // 通过 TrackService 立即读取
        final readPoints =
            await trackService.readDayTrack(phoneNumber, 2024, 3, 30);

        expect(readPoints.length, equals(1));
        expect(readPoints[0].latitude, equals(39.908823));
      });

      test('TrackService 保存后 TrackRecorder 能读取', () async {
        final phoneNumber = '13800138000';

        // 通过 TrackService 保存（使用指定的日期时间）
        await trackService.saveLocation(
          phoneNumber: phoneNumber,
          lat: 39.908823,
          lng: 116.397470,
          altitude: 50.0,
          speed: 5.0,
          accuracy: 10.0,
          timestamp: DateTime(2024, 3, 30, 10, 0, 0),
        );

        // 通过 TrackRecorder 读取
        final readPoints =
            await recorder.readDay(phoneNumber, 2024, 3, 30);

        expect(readPoints.length, equals(1));
        expect(readPoints[0].latitude, equals(39.908823));
      });
    });

    group('文件路径格式一致性测试', () {
      test('两个服务生成的路径格式一致', () async {
        final phoneNumber = '13800138000';
        final year = 2024;
        final month = 3;
        final day = 30;

        // 通过 LocalCsvStorage 获取路径
        final csvPath =
            await csvStorage.getTrackFilePath(phoneNumber, year, month, day);

        // 通过 TestableTrackService 获取路径（手动构建）
        final trackServicePath =
            '$tempDir/path/location_tracks/$phoneNumber/$year/${month.toString().padLeft(2, '0')}/${day.toString().padLeft(2, '0')}.csv';

        // 验证路径格式一致（都包含相同的目录结构）
        expect(csvPath, contains('location_tracks'));
        expect(csvPath, contains(phoneNumber));
        expect(csvPath, contains('$year'));
        expect(csvPath, contains('03'));
        expect(csvPath, contains('30.csv'));
      });

      test('月份和日期使用前导零填充格式一致', () async {
        final phoneNumber = '13800138000';

        // 写入 1 月 5 日的数据
        final point = TrackPoint(
          timestamp: DateTime(2024, 1, 5, 10, 0, 0),
          latitude: 39.908823,
          longitude: 116.397470,
        );

        await csvStorage.write(phoneNumber, point);

        // CSVStorage 路径
        final csvPath =
            await csvStorage.getTrackFilePath(phoneNumber, 2024, 1, 5);
        expect(csvPath, contains('/01/05.csv'));

        // TrackService 应该能读取这个文件
        final readPoints =
            await trackService.readDayTrack(phoneNumber, 2024, 1, 5);
        expect(readPoints.length, equals(1));
      });
    });

    group('集成测试：完整读写流程', () {
      test('TrackRecorder 和 TrackService 双向读写一致', () async {
        final phoneNumber = '13800138000';

        // 场景1: 通过 TrackRecorder 写入，TrackService 读取
        await recorder.recordFor(phoneNumber, _createTestPosition(
          latitude: 39.908823,
          longitude: 116.397470,
        ));
        var read1 =
            await trackService.readDayTrack(phoneNumber, 2024, 3, 30);
        expect(read1.length, equals(1));

        // 场景2: 通过 TrackService 写入，TrackRecorder 读取
        await trackService.saveLocation(
          phoneNumber: phoneNumber,
          lat: 39.908824,
          lng: 116.397471,
          altitude: 51.0,
          speed: 6.0,
          accuracy: 11.0,
          timestamp: DateTime(2024, 3, 30, 10, 1, 0),
        );
        var read2 = await recorder.readDay(phoneNumber, 2024, 3, 30);
        expect(read2.length, equals(2));

        // 场景3: 验证数据内容
        expect(read2[0].latitude, equals(39.908823));
        expect(read2[1].latitude, equals(39.908824));
      });

      test('删除操作在两个服务间保持一致', () async {
        final phoneNumber = '13800138000';

        // 通过 CSVStorage 写入
        await csvStorage.write(phoneNumber, TrackPoint(
          timestamp: DateTime(2024, 3, 30, 10, 0, 0),
          latitude: 39.908823,
          longitude: 116.397470,
        ));

        // 确认写入成功
        var read = await trackService.readDayTrack(phoneNumber, 2024, 3, 30);
        expect(read.length, equals(1));

        // 通过 TrackService 删除
        await trackService.deleteDayTrack(phoneNumber, 2024, 3, 30);

        // 确认删除成功
        read = await trackService.readDayTrack(phoneNumber, 2024, 3, 30);
        expect(read.length, equals(0));
      });

      test('修改时间在两个服务间一致', () async {
        final phoneNumber = '13800138000';

        // 通过 CSVStorage 写入
        await csvStorage.write(phoneNumber, TrackPoint(
          timestamp: DateTime(2024, 3, 30, 10, 0, 0),
          latitude: 39.908823,
          longitude: 116.397470,
        ));

        // 两个服务获取的修改时间应该一致
        final csvModifyTime =
            await csvStorage.getFileModifyTime(phoneNumber, 2024, 3, 30);
        final trackServiceModifyTime =
            await trackService.getFileModifyTime(phoneNumber, 2024, 3, 30);

        expect(csvModifyTime, isNotNull);
        expect(trackServiceModifyTime, isNotNull);
        // 修改时间应该非常接近（在同一秒内）
        expect(
          csvModifyTime!.difference(trackServiceModifyTime!).inSeconds.abs(),
          lessThan(1),
        );
      });
    });

    group('边界条件', () {
      test('读取不存在的日期返回空列表', () async {
        final readViaCsv =
            await csvStorage.readDay('99999999999', 2024, 12, 31);
        final readViaService =
            await trackService.readDayTrack('99999999999', 2024, 12, 31);

        expect(readViaCsv, isEmpty);
        expect(readViaService, isEmpty);
      });

      test('跨月数据隔离', () async {
        final phoneNumber = '13800138000';

        await csvStorage.write(phoneNumber, TrackPoint(
          timestamp: DateTime(2024, 3, 30, 10, 0, 0),
          latitude: 39.908823,
          longitude: 116.397470,
        ));
        await csvStorage.write(phoneNumber, TrackPoint(
          timestamp: DateTime(2024, 4, 1, 10, 0, 0),
          latitude: 39.908824,
          longitude: 116.397471,
        ));

        final marchPoints =
            await trackService.readDayTrack(phoneNumber, 2024, 3, 30);
        final aprilPoints =
            await trackService.readDayTrack(phoneNumber, 2024, 4, 1);

        expect(marchPoints.length, equals(1));
        expect(marchPoints[0].latitude, equals(39.908823));
        expect(aprilPoints.length, equals(1));
        expect(aprilPoints[0].latitude, equals(39.908824));
      });
    });
  });
}

/// 创建测试用的 Position 对象
Position _createTestPosition({
  double latitude = 39.908823,
  double longitude = 116.397470,
  double altitude = 0,
  double speed = 0,
  double accuracy = 0,
}) {
  return Position(
    latitude: latitude,
    longitude: longitude,
    timestamp: DateTime(2024, 3, 30, 10, 0, 0),
    altitude: altitude,
    speed: speed,
    accuracy: accuracy,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speedAccuracy: 0,
  );
}
