import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:csv/csv.dart';
import 'package:latlong2/latlong.dart';

/// 轨迹数据点
class TrackPoint {
  final DateTime timestamp;
  final double lat;
  final double lng;
  final double altitude;
  final double speed;
  final double accuracy;

  TrackPoint({
    required this.timestamp,
    required this.lat,
    required this.lng,
    required this.altitude,
    required this.speed,
    required this.accuracy,
  });

  factory TrackPoint.fromRow(List<dynamic> row) {
    return TrackPoint(
      timestamp: DateTime.parse(row[0].toString()),
      lat: double.parse(row[1].toString()),
      lng: double.parse(row[2].toString()),
      altitude: double.parse(row[3].toString()),
      speed: double.parse(row[4].toString()),
      accuracy: double.parse(row[5].toString()),
    );
  }

  LatLng toLatLng() => LatLng(lat, lng);

  /// 创建转换后的轨迹点（WGS84 → GCJ-02）
  TrackPoint toGcj02() {
    final gcj02 = wgs84ToGcj02(lat, lng);
    return TrackPoint(
      timestamp: timestamp,
      lat: gcj02[0],
      lng: gcj02[1],
      altitude: altitude,
      speed: speed,
      accuracy: accuracy,
    );
  }

  /// WGS84 转 GCJ-02
  static List<double> wgs84ToGcj02(double lat, double lng) {
    const double pi = 3.1415926535897932384626;
    const double a = 6378245.0;
    const double ee = 0.00669342162296594323;

    double dLat = _transformLat(lng - 105.0, lat - 35.0);
    double dLng = _transformLng(lng - 105.0, lat - 35.0);

    double radLat = lat / 180.0 * pi;
    double sinLat = math.sin(radLat);
    double cosLat = math.cos(radLat);
    double magic = 1 - ee * sinLat * sinLat;
    double sqrtMagic = math.sqrt(magic);

    dLat = (dLat * 180.0) / ((a * (1 - ee)) / (magic * sqrtMagic) * pi);
    dLng = (dLng * 180.0) / (a / sqrtMagic * cosLat * pi);

    return [lat + dLat, lng + dLng];
  }

  static double _transformLat(double x, double y) {
    const double pi = 3.1415926535897932384626;
    double ret = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y;
    double sqrtX = x >= 0 ? x : -x;
    ret += 0.2 * math.sqrt(sqrtX);
    ret += (20.0 * math.sin(6.0 * x * pi) + 20.0 * math.sin(2.0 * x * pi)) * 2.0 / 3.0;
    ret += (20.0 * math.sin(y * pi) + 40.0 * math.sin(y / 3.0 * pi)) * 2.0 / 3.0;
    ret += (160.0 * math.sin(y / 12.0 * pi) + 320.0 * math.sin(y * pi / 30.0)) * 2.0 / 3.0;
    return ret;
  }

  static double _transformLng(double x, double y) {
    const double pi = 3.1415926535897932384626;
    double ret = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y;
    double sqrtX = x >= 0 ? x : -x;
    ret += 0.1 * math.sqrt(sqrtX);
    ret += (20.0 * math.sin(6.0 * x * pi) + 20.0 * math.sin(2.0 * x * pi)) * 2.0 / 3.0;
    ret += (20.0 * math.sin(x * pi) + 40.0 * math.sin(x / 3.0 * pi)) * 2.0 / 3.0;
    ret += (150.0 * math.sin(x / 12.0 * pi) + 300.0 * math.sin(x / 30.0 * pi)) * 2.0 / 3.0;
    return ret;
  }
}

/// 轨迹服务
class TrackService {
  static final TrackService _instance = TrackService._();
  factory TrackService() => _instance;
  TrackService._();

  static const String _folderName = 'location_tracks';

  /// 获取轨迹根目录（使用Android的files目录，与原生代码一致）
  Future<String> get _tracksRootDir async {
    try {
      // 通过MethodChannel获取Android的files目录路径
      final result = await const MethodChannel('com.kenny.trace_path/location_service')
          .invokeMethod<String>('getFilesDir');
      if (result != null) {
        return '$result/$_folderName';
      }
    } catch (e) {
      print('[TrackService] 获取files目录失败: $e');
    }
    // fallback到应用文档目录
    final dir = await const MethodChannel('com.kenny.trace_path/location_service')
        .invokeMethod<String>('getFilesDir');
    return dir ?? '';
  }

  /// 获取指定手机号的轨迹目录
  Future<String> _phoneDir(String phoneNumber) async {
    final root = await _tracksRootDir;
    return '$root/$phoneNumber';
  }

  /// 删除指定日期的轨迹文件
  Future<bool> deleteDayTrack(String phoneNumber, int year, int month, int day) async {
    try {
      final path = await _phoneDir(phoneNumber);
      final datePath = '$year/${month.toString().padLeft(2, '0')}/${day.toString().padLeft(2, '0')}.csv';
      final file = File('$path/$datePath');
      if (await file.exists()) {
        await file.delete();
        print('[TrackService] 已删除: $path/$datePath');
        return true;
      }
      return false;
    } catch (e) {
      print('[TrackService] 删除失败: $e');
      return false;
    }
  }

  /// 保存一条定位记录
  Future<bool> saveLocation({
    required String phoneNumber,
    required double lat,
    required double lng,
    required double altitude,
    required double speed,
    required double accuracy,
  }) async {
    try {
      final now = DateTime.now();
      final path = await _phoneDir(phoneNumber);
      final dir = Directory(path);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      // 路径格式: {phoneNumber}/{year}/{month}/{day}.csv
      final datePath = '${now.year}/${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')}.csv';
      final file = File('$path/$datePath');

      // 检查是否需要添加表头（文件不存在或为空）
      bool needsHeader = !await file.exists() || await file.length() == 0;

      // 构建CSV行
      final timestamp = now.toIso8601String();
      final dataRow = '$timestamp,${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)},${altitude.toStringAsFixed(2)},${speed.toStringAsFixed(2)},${accuracy.toStringAsFixed(1)}';

      String content = '';
      if (needsHeader) {
        content = 'timestamp,latitude,longitude,altitude,speed,accuracy\n$dataRow\n';
      } else {
        content = '$dataRow\n';
      }

      await file.writeAsString(content, mode: FileMode.append);
      print('[TrackService] 保存成功: $dataRow');
      return true;
    } catch (e) {
      print('[TrackService] 保存失败: $e');
      return false;
    }
  }

  /// 读取指定日期的轨迹数据
  Future<List<TrackPoint>> readDayTrack(String phoneNumber, int year, int month, int day) async {
    try {
      final path = await _phoneDir(phoneNumber);
      final datePath = '$year/${month.toString().padLeft(2, '0')}/${day.toString().padLeft(2, '0')}.csv';
      final fullPath = '$path/$datePath';
      print('[TrackService] 读取轨迹: $fullPath');
      
      final file = File(fullPath);
      if (!await file.exists()) {
        print('[TrackService] 文件不存在');
        return [];
      }

      final content = await file.readAsString();
      print('[TrackService] 文件内容: $content');
      
      // 按行分割，支持 \r\n 或 \n
      final lines = content.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).toList();
      print('[TrackService] 行数: ${lines.length}');
      
      if (lines.isEmpty) {
        print('[TrackService] 无数据行');
        return [];
      }

      // 检查第一行是否是表头
      final firstLine = lines.first;
      final isHeader = firstLine.contains('timestamp') || firstLine.contains('latitude');
      final dataLines = isHeader ? lines.skip(1) : lines;
      
      final points = <TrackPoint>[];
      for (final line in dataLines) {
        if (line.trim().isEmpty) continue;
        final parts = line.split(',');
        if (parts.length < 6) continue;
        try {
          points.add(TrackPoint(
            timestamp: DateTime.parse(parts[0].trim()),
            lat: double.parse(parts[1].trim()),
            lng: double.parse(parts[2].trim()),
            altitude: double.parse(parts[3].trim()),
            speed: double.parse(parts[4].trim()),
            accuracy: double.parse(parts[5].trim()),
          ));
        } catch (e) {
          print('[TrackService] 解析行失败: $line, $e');
        }
      }
      
      points.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      // WGS84 → GCJ-02 坐标转换（用于高德/腾讯地图显示）
      final convertedPoints = points.map((p) => p.toGcj02()).toList();
      print('[TrackService] 转换成功: ${convertedPoints.length} 个点');
      return convertedPoints;
    } catch (e) {
      print('[TrackService] 读取失败: $e');
      return [];
    }
  }

  /// 获取所有轨迹文件列表（按人员、年、月、日分级）
  Future<Map<String, Map<String, Map<String, List<String>>>>> getTrackHierarchy() async {
    final hierarchy = <String, Map<String, Map<String, List<String>>>>{};

    try {
      final root = await _tracksRootDir;
      final rootDir = Directory(root);
      if (!await rootDir.exists()) return hierarchy;

      // 遍历手机号目录
      for (final phoneEntity in await rootDir.list().toList()) {
        if (phoneEntity is! Directory) continue;
        final phoneNumber = phoneEntity.path.split('/').last;

        hierarchy[phoneNumber] = <String, Map<String, List<String>>>{};
        final yearDirs = await phoneEntity.list().toList();

        for (final yearEntity in yearDirs) {
          if (yearEntity is! Directory) continue;
          final year = yearEntity.path.split('/').last;
          if (int.tryParse(year) == null) continue;

          hierarchy[phoneNumber]![year] = <String, List<String>>{};
          final monthDirs = await yearEntity.list().toList();

          for (final monthEntity in monthDirs) {
            if (monthEntity is! Directory) continue;
            final month = monthEntity.path.split('/').last;
            if (int.tryParse(month) == null) continue;

            hierarchy[phoneNumber]![year]![month] = <String>[];
            final csvFiles = await monthEntity.list().toList();

            for (final file in csvFiles) {
              if (file is File && file.path.endsWith('.csv')) {
                final day = file.path.split('/').last.replaceAll('.csv', '');
                hierarchy[phoneNumber]![year]![month]!.add(day);
              }
            }
            // 按日期降序排列
            hierarchy[phoneNumber]![year]![month]!.sort((a, b) => b.compareTo(a));
          }
        }
      }
    } catch (e) {
      print('[TrackService] 获取层级失败: $e');
    }

    return hierarchy;
  }

  /// 获取有轨迹数据的手机号列表
  Future<List<String>> getPhonesWithTracks() async {
    final hierarchy = await getTrackHierarchy();
    return hierarchy.keys.toList();
  }

  /// 获取指定手机号的年列表（按最新年份排序）
  Future<List<String>> getYearsWithTracks(String phoneNumber) async {
    final hierarchy = await getTrackHierarchy();
    if (!hierarchy.containsKey(phoneNumber)) return [];
    final years = hierarchy[phoneNumber]!.keys.toList();
    years.sort((a, b) => b.compareTo(a)); // 降序
    return years;
  }

  /// 获取指定手机号和年份的月列表
  Future<List<String>> getMonthsWithTracks(String phoneNumber, String year) async {
    final hierarchy = await getTrackHierarchy();
    if (!hierarchy.containsKey(phoneNumber) || !hierarchy[phoneNumber]!.containsKey(year)) return [];
    final months = hierarchy[phoneNumber]![year]!.keys.toList();
    months.sort((a, b) => b.compareTo(a)); // 降序
    return months;
  }

  /// 获取指定手机号、年、月的日列表
  Future<List<String>> getDaysWithTracks(String phoneNumber, String year, String month) async {
    final hierarchy = await getTrackHierarchy();
    if (!hierarchy.containsKey(phoneNumber) || !hierarchy[phoneNumber]!.containsKey(year)) return [];
    final days = hierarchy[phoneNumber]![year]![month] ?? [];
    return days;
  }
}
