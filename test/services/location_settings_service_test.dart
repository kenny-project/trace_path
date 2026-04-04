import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:trace_path/com/kenny/trace_path/services/location_settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocationSettingsService', () {
    late Directory tempDir;
    late File settingsFile;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('location_settings_test_');
      settingsFile = File('${tempDir.path}/location_settings.json');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    group('load / save', () {
      test('首次 load 不报错（文件不存在）', () async {
        final service = _TestableLocationSettingsService(tempDir.path);
        await service.load(); // 不应该抛异常
        expect(service.settings.enabled, isFalse);
        expect(service.settings.intervalSeconds, equals(30));
        expect(service.settings.powerSaving, isFalse);
      });

      test('save 后 load 能恢复相同的设置', () async {
        final service = _TestableLocationSettingsService(tempDir.path);

        service.injectSettings(TracePathLocationSettings(
          enabled: true,
          intervalSeconds: 60,
          powerSaving: true,
        ));
        await service.save();

        // 新建实例验证能恢复
        final service2 = _TestableLocationSettingsService(tempDir.path);
        await service2.load();

        expect(service2.settings.enabled, isTrue);
        expect(service2.settings.intervalSeconds, equals(60));
        expect(service2.settings.powerSaving, isTrue);
      });

      test('load 能正确解析保存的 JSON', () async {
        final service = _TestableLocationSettingsService(tempDir.path);

        service.injectSettings(TracePathLocationSettings(
          enabled: true,
          intervalSeconds: 45,
          powerSaving: true,
        ));
        await service.save();

        // 直接验证文件内容
        final content = await settingsFile.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;

        expect(json['enabled'], isTrue);
        expect(json['intervalSeconds'], equals(45));
        expect(json['powerSaving'], isTrue);
      });

      test('load 遇到损坏的 JSON 不抛异常', () async {
        // 写入损坏的 JSON
        await settingsFile.writeAsString('{ bad json }');

        final service = _TestableLocationSettingsService(tempDir.path);
        await service.load(); // 不应该抛异常，使用默认值

        // 应该使用默认值
        expect(service.settings.enabled, isFalse);
      });

      test('load 缺少部分字段时使用默认值', () async {
        // 写入不完整的 JSON
        await settingsFile.writeAsString(jsonEncode({
          'enabled': true,
          // 缺少 intervalSeconds 和 powerSaving
        }));

        final service = _TestableLocationSettingsService(tempDir.path);
        await service.load();

        expect(service.settings.enabled, isTrue);
        expect(service.settings.intervalSeconds, equals(30)); // 默认值
        expect(service.settings.powerSaving, isFalse); // 默认值
      });
    });

    group('update', () {
      test('update enabled', () async {
        final service = _TestableLocationSettingsService(tempDir.path);
        await service.load();

        await service.update(enabled: true);

        expect(service.settings.enabled, isTrue);
      });

      test('update intervalSeconds', () async {
        final service = _TestableLocationSettingsService(tempDir.path);
        await service.load();

        await service.update(intervalSeconds: 60);

        expect(service.settings.intervalSeconds, equals(60));
      });

      test('update powerSaving', () async {
        final service = _TestableLocationSettingsService(tempDir.path);
        await service.load();

        await service.update(powerSaving: true);

        expect(service.settings.powerSaving, isTrue);
      });

      test('update 多个字段', () async {
        final service = _TestableLocationSettingsService(tempDir.path);
        await service.load();

        await service.update(
          enabled: true,
          intervalSeconds: 180,
          powerSaving: true,
        );

        expect(service.settings.enabled, isTrue);
        expect(service.settings.intervalSeconds, equals(180));
        expect(service.settings.powerSaving, isTrue);
      });

      test('update 后保存的文件包含新值', () async {
        final service = _TestableLocationSettingsService(tempDir.path);
        await service.load();

        await service.update(intervalSeconds: 120);

        final content = await settingsFile.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;

        expect(json['intervalSeconds'], equals(120));
      });

      test('update null 字段不改变现有值', () async {
        final service = _TestableLocationSettingsService(tempDir.path);
        await service.load();

        await service.update(enabled: true, intervalSeconds: 60, powerSaving: true);
        await service.update(enabled: false); // 只更新 enabled

        expect(service.settings.enabled, isFalse);
        expect(service.settings.intervalSeconds, equals(60)); // 未变
        expect(service.settings.powerSaving, isTrue); // 未变
      });
    });
  });

  group('TracePathLocationSettings', () {
    test('defaults() 返回正确的默认值', () {
      final settings = TracePathLocationSettings.defaults();

      expect(settings.enabled, isFalse);
      expect(settings.intervalSeconds, equals(30));
      expect(settings.powerSaving, isFalse);
      expect(settings.extra, isEmpty);
    });

    test('fromJson 正确解析完整 JSON', () {
      final json = {
        'enabled': true,
        'intervalSeconds': 60,
        'powerSaving': true,
        'extra': {'custom': 'value'},
      };

      final settings = TracePathLocationSettings.fromJson(json);

      expect(settings.enabled, isTrue);
      expect(settings.intervalSeconds, equals(60));
      expect(settings.powerSaving, isTrue);
      expect(settings.extra['custom'], equals('value'));
    });

    test('fromJson 缺失字段使用默认值', () {
      final json = <String, dynamic>{};

      final settings = TracePathLocationSettings.fromJson(json);

      expect(settings.enabled, isFalse);
      expect(settings.intervalSeconds, equals(30));
      expect(settings.powerSaving, isFalse);
    });

    test('toJson 正确序列化为 Map', () {
      final settings = TracePathLocationSettings(
        enabled: true,
        intervalSeconds: 45,
        powerSaving: false,
        extra: {'key': 'value'},
      );

      final json = settings.toJson();

      expect(json['enabled'], isTrue);
      expect(json['intervalSeconds'], equals(45));
      expect(json['powerSaving'], isFalse);
      expect(json['extra']['key'], equals('value'));
    });

    test('copyWith 创建新实例并保留未修改的字段', () {
      final original = TracePathLocationSettings(
        enabled: true,
        intervalSeconds: 60,
        powerSaving: true,
      );

      final copy = original.copyWith(intervalSeconds: 120);

      expect(copy.enabled, isTrue); // 保留
      expect(copy.intervalSeconds, equals(120)); // 修改
      expect(copy.powerSaving, isTrue); // 保留
    });

    test('copyWith 所有字段都传则等价于重新创建', () {
      final original = TracePathLocationSettings(
        enabled: true,
        intervalSeconds: 60,
        powerSaving: true,
      );

      final copy = original.copyWith(
        enabled: false,
        intervalSeconds: 30,
        powerSaving: false,
      );

      expect(copy.enabled, isFalse);
      expect(copy.intervalSeconds, equals(30));
      expect(copy.powerSaving, isFalse);
    });

    test('extra 字段可以存储任意数据', () {
      final settings = TracePathLocationSettings(
        enabled: false,
        intervalSeconds: 30,
        powerSaving: false,
        extra: {
          'string': 'value',
          'number': 42,
          'list': [1, 2, 3],
          'nested': {'a': 'b'},
        },
      );

      final json = settings.toJson();
      expect(json['extra']['string'], equals('value'));
      expect(json['extra']['number'], equals(42));
      expect(json['extra']['list'], equals([1, 2, 3]));
      expect(json['extra']['nested']['a'], equals('b'));
    });
  });

  group('LocationInterval', () {
    test('options 包含预期的频率选项', () {
      expect(LocationInterval.options.length, equals(7));
      expect(LocationInterval.options[0].label, equals('5秒'));
      expect(LocationInterval.options[0].seconds, equals(5));
      expect(LocationInterval.options[2].label, equals('30秒'));
      expect(LocationInterval.options[2].seconds, equals(30));
      expect(LocationInterval.options[4].label, equals('1分钟'));
      expect(LocationInterval.options[4].seconds, equals(60));
      expect(LocationInterval.options[6].label, equals('5分钟'));
      expect(LocationInterval.options[6].seconds, equals(300));
    });

    test('每个选项的 label 和 seconds 对应正确', () {
      for (final option in LocationInterval.options) {
        expect(option.label.isNotEmpty, isTrue);
        expect(option.seconds, greaterThan(0));
      }
    });
  });
}

/// 使用注入路径的 LocationSettingsService 测试版本
class _TestableLocationSettingsService extends LocationSettingsService {
  final String _testBasePath;

  _TestableLocationSettingsService(this._testBasePath);

  @override
  Future<void> save() async {
    try {
      final file = File('$_testBasePath/location_settings.json');
      await file.writeAsString(jsonEncode(settings.toJson()));
    } catch (e) {
      print('[LocationSettingsService] 保存失败: $e');
    }
  }

  @override
  Future<void> load() async {
    try {
      final file = File('$_testBasePath/location_settings.json');
      if (!await file.exists()) return;

      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      injectSettings(TracePathLocationSettings.fromJson(json));
    } catch (e) {
      print('[LocationSettingsService] 加载失败: $e');
    }
  }
}
