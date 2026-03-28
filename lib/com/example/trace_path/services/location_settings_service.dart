import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// 定位设置持久化
/// 存放在应用文件目录/location_settings.json
class LocationSettingsService {
  static const String _fileName = 'location_settings.json';

  TracePathLocationSettings _settings = TracePathLocationSettings.defaults();

  TracePathLocationSettings get settings => _settings;

  Future<void> load() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$_fileName');
      if (!await file.exists()) return;

      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      _settings = TracePathLocationSettings.fromJson(json);
    } catch (e) {
      print('[LocationSettingsService] 加载失败: $e');
    }
  }

  Future<void> save() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$_fileName');
      await file.writeAsString(jsonEncode(_settings.toJson()));
    } catch (e) {
      print('[LocationSettingsService] 保存失败: $e');
    }
  }

  Future<void> update({
    bool? enabled,
    int? intervalSeconds,
    bool? powerSaving,
  }) async {
    if (enabled != null) _settings.enabled = enabled;
    if (intervalSeconds != null) _settings.intervalSeconds = intervalSeconds;
    if (powerSaving != null) _settings.powerSaving = powerSaving;
    await save();
  }
}

/// 定位设置实体
class TracePathLocationSettings {
  bool enabled; // 是否开启实时定位
  int intervalSeconds; // 定位频率（秒）
  bool powerSaving; // 省电模式

  // 备用字段（方便后续扩展）
  Map<String, dynamic> extra;

  TracePathLocationSettings({
    required this.enabled,
    required this.intervalSeconds,
    required this.powerSaving,
    this.extra = const {},
  });

  factory TracePathLocationSettings.defaults() {
    return TracePathLocationSettings(
      enabled: false,
      intervalSeconds: 30,
      powerSaving: false,
    );
  }

  factory TracePathLocationSettings.fromJson(Map<String, dynamic> json) {
    return TracePathLocationSettings(
      enabled: json['enabled'] as bool? ?? false,
      intervalSeconds: json['intervalSeconds'] as int? ?? 30,
      powerSaving: json['powerSaving'] as bool? ?? false,
      extra: (json['extra'] as Map<String, dynamic>?) ?? {},
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'intervalSeconds': intervalSeconds,
      'powerSaving': powerSaving,
      'extra': extra,
    };
  }

  TracePathLocationSettings copyWith({
    bool? enabled,
    int? intervalSeconds,
    bool? powerSaving,
  }) {
    return TracePathLocationSettings(
      enabled: enabled ?? this.enabled,
      intervalSeconds: intervalSeconds ?? this.intervalSeconds,
      powerSaving: powerSaving ?? this.powerSaving,
      extra: extra,
    );
  }
}

/// 定位频率选项
class LocationInterval {
  final String label;
  final int seconds;

  const LocationInterval(this.label, this.seconds);

  static const List<LocationInterval> options = [
    LocationInterval('5秒', 5),
    LocationInterval('10秒', 10),
    LocationInterval('30秒', 30),
    LocationInterval('45秒', 45),
    LocationInterval('1分钟', 60),
    LocationInterval('3分钟', 180),
    LocationInterval('5分钟', 300),
  ];
}
