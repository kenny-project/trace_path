import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:trace_path/com/kenny/trace_path/services/track_recorder.dart';
import 'package:trace_path/com/kenny/trace_path/services/user_service.dart';
import '../mocks/in_memory_user_storage.dart';
import '../mocks/mock_local_csv_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TrackRecorder', () {
    late Directory tempDir;
    late TestableLocalCsvStorage storage;
    late UserService userService;
    late InMemoryUserStorage userStorage;
    late TrackRecorder recorder;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('track_recorder_test_');
      storage = TestableLocalCsvStorage(tempDir.path);
      userStorage = InMemoryUserStorage();
      userService = UserService();
      recorder = TrackRecorder();

      userService.setStorage(userStorage);
      recorder.setStorage(storage);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    group('record', () {
      test('录制轨迹点成功', () async {
        await userService.init();
        await userService.saveUser(User(phoneNumber: '13800138000'));

        final position = Position(
          latitude: 39.908823,
          longitude: 116.397470,
          timestamp: DateTime(2024, 3, 30, 10, 0, 0),
          altitude: 50.0,
          speed: 5.0,
          accuracy: 10.0,
          altitudeAccuracy: 5.0,
          heading: 0.0,
          headingAccuracy: 0.0,
          speedAccuracy: 1.0,
        );

        await recorder.record(position);

        final points = await storage.readDay('13800138000', 2024, 3, 30);
        expect(points.length, equals(1));
        expect(points[0].latitude, equals(39.908823));
      });

      test('未登录时使用默认手机号录制', () async {
        await userService.init();
        // 不保存用户

        final position = Position(
          latitude: 39.908823,
          longitude: 116.397470,
          timestamp: DateTime(2024, 3, 30, 10, 0, 0),
          altitude: 0,
          speed: 0,
          accuracy: 0,
          altitudeAccuracy: 0,
          heading: 0,
          headingAccuracy: 0,
          speedAccuracy: 0,
        );

        await recorder.record(position);

        final points = await storage.readDay('1000000', 2024, 3, 30);
        expect(points.length, equals(1));
      });

      test('连续录制多个轨迹点', () async {
        await userService.init();
        await userService.saveUser(User(phoneNumber: '13800138000'));

        for (int i = 0; i < 5; i++) {
          final position = Position(
            latitude: 39.908823 + i * 0.0001,
            longitude: 116.397470 + i * 0.0001,
            timestamp: DateTime(2024, 3, 30, 10, i, 0),
            altitude: 50.0 + i,
            speed: 5.0,
            accuracy: 10.0,
            altitudeAccuracy: 5.0,
            heading: 0.0,
            headingAccuracy: 0.0,
            speedAccuracy: 1.0,
          );
          await recorder.record(position);
        }

        final points = await storage.readDay('13800138000', 2024, 3, 30);
        expect(points.length, equals(5));
      });

      test('录制后文件正确生成', () async {
        await userService.init();
        await userService.saveUser(User(phoneNumber: '13800138000'));

        final position = Position(
          latitude: 39.908823,
          longitude: 116.397470,
          timestamp: DateTime(2024, 3, 30, 10, 0, 0),
          altitude: 0,
          speed: 0,
          accuracy: 0,
          altitudeAccuracy: 0,
          heading: 0,
          headingAccuracy: 0,
          speedAccuracy: 0,
        );

        await recorder.record(position);

        final filePath = await storage.getTrackFilePath('13800138000', 2024, 3, 30);
        final file = File(filePath);
        expect(await file.exists(), isTrue);
      });
    });

    group('readDay', () {
      test('读取某天的轨迹', () async {
        await userService.init();
        await userService.saveUser(User(phoneNumber: '13800138000'));

        final point1 = TrackPoint(
          timestamp: DateTime(2024, 3, 30, 10, 0, 0),
          latitude: 39.908823,
          longitude: 116.397470,
          altitude: 50.0,
          speed: 5.0,
          accuracy: 10.0,
        );
        final point2 = TrackPoint(
          timestamp: DateTime(2024, 3, 30, 11, 0, 0),
          latitude: 39.908824,
          longitude: 116.397471,
          altitude: 51.0,
          speed: 6.0,
          accuracy: 11.0,
        );

        await storage.write('13800138000', point1);
        await storage.write('13800138000', point2);

        final points = await recorder.readDay('13800138000', 2024, 3, 30);

        expect(points.length, equals(2));
        expect(points[0].latitude, equals(39.908823));
        expect(points[1].latitude, equals(39.908824));
      });

      test('读取不存在的日期返回空列表', () async {
        final points = await recorder.readDay('13800138000', 2024, 12, 31);

        expect(points, isEmpty);
      });

      test('读取不同用户的数据隔离', () async {
        await userService.init();
        await userService.saveUser(User(phoneNumber: '13800138000'));

        final point = TrackPoint(
          timestamp: DateTime(2024, 3, 30, 10, 0, 0),
          latitude: 39.908823,
          longitude: 116.397470,
        );

        await storage.write('13800138000', point);
        await storage.write('13900001111', TrackPoint(
          timestamp: DateTime(2024, 3, 30, 10, 0, 0),
          latitude: 31.230416,
          longitude: 121.473701,
        ));

        final pointsUser1 = await recorder.readDay('13800138000', 2024, 3, 30);
        final pointsUser2 = await recorder.readDay('13900001111', 2024, 3, 30);

        expect(pointsUser1.length, equals(1));
        expect(pointsUser2.length, equals(1));
        expect(pointsUser1[0].latitude, equals(39.908823));
        expect(pointsUser2[0].latitude, equals(31.230416));
      });
    });

    group('deleteDay', () {
      test('删除某天的轨迹', () async {
        await userService.init();
        await userService.saveUser(User(phoneNumber: '13800138000'));

        final point = TrackPoint(
          timestamp: DateTime(2024, 3, 30, 10, 0, 0),
          latitude: 39.908823,
          longitude: 116.397470,
        );

        await storage.write('13800138000', point);
        await recorder.deleteDay('13800138000', 2024, 3, 30);

        final points = await recorder.readDay('13800138000', 2024, 3, 30);
        expect(points, isEmpty);
      });

      test('删除不存在的轨迹不报错', () async {
        await expectLater(
          recorder.deleteDay('99999999999', 2024, 3, 30),
          completes,
        );
      });

      test('删除后文件不存在', () async {
        await userService.init();
        await userService.saveUser(User(phoneNumber: '13800138000'));

        final point = TrackPoint(
          timestamp: DateTime(2024, 3, 30, 10, 0, 0),
          latitude: 39.908823,
          longitude: 116.397470,
        );

        await storage.write('13800138000', point);

        final filePath = await storage.getTrackFilePath('13800138000', 2024, 3, 30);
        var file = File(filePath);
        expect(await file.exists(), isTrue);

        await recorder.deleteDay('13800138000', 2024, 3, 30);

        expect(await file.exists(), isFalse);
      });

      test('删除后不影响其他日期数据', () async {
        await userService.init();
        await userService.saveUser(User(phoneNumber: '13800138000'));

        final point1 = TrackPoint(
          timestamp: DateTime(2024, 3, 30, 10, 0, 0),
          latitude: 39.908823,
          longitude: 116.397470,
        );
        final point2 = TrackPoint(
          timestamp: DateTime(2024, 3, 31, 10, 0, 0),
          latitude: 39.908825,
          longitude: 116.397472,
        );

        await storage.write('13800138000', point1);
        await storage.write('13800138000', point2);

        await recorder.deleteDay('13800138000', 2024, 3, 30);

        final points30 = await recorder.readDay('13800138000', 2024, 3, 30);
        final points31 = await recorder.readDay('13800138000', 2024, 3, 31);

        expect(points30, isEmpty);
        expect(points31.length, equals(1));
      });
    });

    group('与 LocalCsvStorage 的集成', () {
      test('TrackRecorder 使用 LocalCsvStorage 正常工作', () async {
        // 使用实际的 LocalCsvStorage（通过 TrackStorage 接口）
        final realStorage = TestableLocalCsvStorage(tempDir.path);
        recorder.setStorage(realStorage);

        await userService.init();
        await userService.saveUser(User(phoneNumber: '13800138000'));

        final position = Position(
          latitude: 39.908823,
          longitude: 116.397470,
          timestamp: DateTime(2024, 3, 30, 10, 0, 0),
          altitude: 50.0,
          speed: 5.0,
          accuracy: 10.0,
          altitudeAccuracy: 5.0,
          heading: 0.0,
          headingAccuracy: 0.0,
          speedAccuracy: 1.0,
        );

        await recorder.record(position);

        final points = await recorder.readDay('13800138000', 2024, 3, 30);
        expect(points.length, equals(1));
      });

      test('TrackRecorder 支持存储切换', () async {
        // 创建两个不同的存储
        final storage1 = TestableLocalCsvStorage(tempDir.path + '/storage1');
        final storage2 = TestableLocalCsvStorage(tempDir.path + '/storage2');

        // 使用第一个存储
        recorder.setStorage(storage1);
        await storage1.write('13800138000', TrackPoint(
          timestamp: DateTime(2024, 3, 30, 10, 0, 0),
          latitude: 39.908823,
          longitude: 116.397470,
        ));

        // 切换到第二个存储
        recorder.setStorage(storage2);
        await storage2.write('13800138000', TrackPoint(
          timestamp: DateTime(2024, 3, 30, 10, 0, 0),
          latitude: 31.230416,
          longitude: 121.473701,
        ));

        // 第一个存储的数据应该不受影响
        final points1 = await storage1.readDay('13800138000', 2024, 3, 30);
        expect(points1.length, equals(1));
        expect(points1[0].latitude, equals(39.908823));

        // 第二个存储有自己的数据
        final points2 = await storage2.readDay('13800138000', 2024, 3, 30);
        expect(points2.length, equals(1));
        expect(points2[0].latitude, equals(31.230416));
      });

      test('getFileModifyTime 返回正确时间', () async {
        await userService.init();
        await userService.saveUser(User(phoneNumber: '13800138000'));

        final position = Position(
          latitude: 39.908823,
          longitude: 116.397470,
          timestamp: DateTime(2024, 3, 30, 10, 0, 0),
          altitude: 0,
          speed: 0,
          accuracy: 0,
          altitudeAccuracy: 0,
          heading: 0,
          headingAccuracy: 0,
          speedAccuracy: 0,
        );

        await recorder.record(position);

        final modifyTime = await recorder.getFileModifyTime('13800138000', 2024, 3, 30);

        expect(modifyTime, isNotNull);
      });

      test('文件不存在时 getFileModifyTime 返回 null', () async {
        final modifyTime = await recorder.getFileModifyTime('99999999999', 2024, 3, 30);

        expect(modifyTime, isNull);
      });
    });

    group('边界条件', () {
      test('recordFor 指定手机号录制', () async {
        final position = Position(
          latitude: 39.908823,
          longitude: 116.397470,
          timestamp: DateTime(2024, 3, 30, 10, 0, 0),
          altitude: 0,
          speed: 0,
          accuracy: 0,
          altitudeAccuracy: 0,
          heading: 0,
          headingAccuracy: 0,
          speedAccuracy: 0,
        );

        await recorder.recordFor('13900001111', position);

        final points = await recorder.readDay('13900001111', 2024, 3, 30);
        expect(points.length, equals(1));
        expect(points[0].latitude, equals(39.908823));
      });

      test('跨年录制轨迹', () async {
        await userService.init();
        await userService.saveUser(User(phoneNumber: '13800138000'));

        final position = Position(
          latitude: 39.908823,
          longitude: 116.397470,
          timestamp: DateTime(2024, 12, 31, 23, 59, 59),
          altitude: 0,
          speed: 0,
          accuracy: 0,
          altitudeAccuracy: 0,
          heading: 0,
          headingAccuracy: 0,
          speedAccuracy: 0,
        );

        await recorder.record(position);

        final points = await recorder.readDay('13800138000', 2024, 12, 31);
        expect(points.length, equals(1));
      });

      test('闰年2月29日录制轨迹', () async {
        await userService.init();
        await userService.saveUser(User(phoneNumber: '13800138000'));

        final position = Position(
          latitude: 39.908823,
          longitude: 116.397470,
          timestamp: DateTime(2024, 2, 29, 10, 0, 0),
          altitude: 0,
          speed: 0,
          accuracy: 0,
          altitudeAccuracy: 0,
          heading: 0,
          headingAccuracy: 0,
          speedAccuracy: 0,
        );

        await recorder.record(position);

        final points = await recorder.readDay('13800138000', 2024, 2, 29);
        expect(points.length, equals(1));
      });
    });
  });
}
