import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:latlong2/latlong.dart';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

/// CSV存储服务
/// 保存路径：应用文件目录/location_tracks/YYYY-MM-DD.csv
/// 格式：timestamp,latitude,longitude,altitude,speed,accuracy
class CsvStorageService {
  static const String _folderName = 'location_tracks';
  static const double _minDistance = 10.0; // 前后距离小于10米不保存

  String? _currentDate;
  File? _currentFile;
  LatLng? _lastPoint;

  /// 获取轨迹文件夹路径
  Future<String> get tracksDir async {
    final dir = await getApplicationDocumentsDirectory();
    final tracksDir = Directory('${dir.path}/$_folderName');
    if (!await tracksDir.exists()) {
      await tracksDir.create(recursive: true);
    }
    return tracksDir.path;
  }

  /// 保存一条定位记录
  /// [lat] 纬度
  /// [lng] 经度
  /// [altitude] 海拔
  /// [speed] 速度 m/s
  /// [accuracy] 精度 m
  Future<bool> saveLocation({
    required double lat,
    required double lng,
    required double altitude,
    required double speed,
    required double accuracy,
  }) async {
    try {
      final now = DateTime.now();
      final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      // 日期切换时重置
      if (_currentDate != dateStr) {
        _currentDate = dateStr;
        _lastPoint = null;
      }

      final currentPoint = LatLng(lat, lng);

      // 智能去重：距离小于10米不存
      if (_lastPoint != null) {
        final distance = _calculateDistance(_lastPoint!, currentPoint);
        if (distance < _minDistance) {
          return false; // 跳过
        }
      }

      _lastPoint = currentPoint;

      // 确保当日文件存在
      final dirPath = await tracksDir;
      final file = File('$dirPath/$dateStr.csv');
      _currentFile = file;

      final timestamp = now.toIso8601String();
      final row = [timestamp, lat.toString(), lng.toString(), altitude.toString(), speed.toString(), accuracy.toString()];

      final csv = const ListToCsvConverter().convert([row]);

      if (!await file.exists()) {
        // 写入表头
        await file.writeAsString('timestamp,latitude,longitude,altitude,speed,accuracy\n');
      }

      // 追加写入
      await file.writeAsString('$csv\n', mode: FileMode.append);
      return true;
    } catch (e) {
      print('[CsvStorageService] 保存失败: $e');
      return false;
    }
  }

  /// 计算两点间距离（米）
  double _calculateDistance(LatLng from, LatLng to) {
    const distance = Distance();
    return distance.as(LengthUnit.Meter, from, to);
  }

  /// 读取指定日期的轨迹文件
  Future<List<List<dynamic>>?> readDayTrack(String date) async {
    try {
      final dirPath = await tracksDir;
      final file = File('$dirPath/$date.csv');
      if (!await file.exists()) return null;

      final content = await file.readAsString();
      final rows = const CsvToListConverter().convert(content);
      if (rows.isEmpty) return null;

      // 去掉表头
      return rows.length > 1 ? rows.sublist(1) : null;
    } catch (e) {
      print('[CsvStorageService] 读取失败: $e');
      return null;
    }
  }

  /// 获取所有轨迹文件列表
  Future<List<String>> listTrackFiles() async {
    try {
      final dirPath = await tracksDir;
      final dir = Directory(dirPath);
      if (!await dir.exists()) return [];

      final files = await dir.list().toList();
      return files
          .whereType<File>()
          .where((f) => f.path.endsWith('.csv'))
          .map((f) => f.path.split('/').last.replaceAll('.csv', ''))
          .toList()
        ..sort((a, b) => b.compareTo(a)); // 最新日期排前面
    } catch (e) {
      return [];
    }
  }

  /// 删除指定日期的轨迹
  Future<bool> deleteDayTrack(String date) async {
    try {
      final dirPath = await tracksDir;
      final file = File('$dirPath/$date.csv');
      if (await file.exists()) {
        await file.delete();
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  /// 清空所有轨迹
  Future<void> clearAll() async {
    try {
      final dirPath = await tracksDir;
      final dir = Directory(dirPath);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        await dir.create(recursive: true);
      }
      _currentDate = null;
      _lastPoint = null;
      _currentFile = null;
    } catch (e) {
      print('[CsvStorageService] 清空失败: $e');
    }
  }

  /// 导出指定日期的轨迹（分享CSV文件）
  /// 返回是否成功
  Future<bool> exportDayTrack(String date) async {
    try {
      final dirPath = await tracksDir;
      final file = File('$dirPath/$date.csv');
      if (!await file.exists()) {
        print('[CsvStorageService] 导出失败: 文件不存在 $date.csv');
        return false;
      }

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: '轨迹数据 $date',
        text: '轨迹导出日期: $date',
      );
      return true;
    } catch (e) {
      print('[CsvStorageService] 导出失败: $e');
      return false;
    }
  }

  /// 导入轨迹（从文件选择器选择CSV）
  /// 返回导入的记录数，失败返回-1
  Future<int> importDayTrack() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (result == null || result.files.isEmpty) {
        return 0; // 用户取消
      }

      final filePath = result.files.single.path;
      if (filePath == null) {
        print('[CsvStorageService] 导入失败: 文件路径为空');
        return -1;
      }

      final sourceFile = File(filePath);
      final content = await sourceFile.readAsString();
      final rows = const CsvToListConverter().convert(content);

      if (rows.isEmpty) {
        return -1;
      }

      // 去掉表头
      final dataRows = rows.length > 1 ? rows.sublist(1) : rows;
      if (dataRows.isEmpty) {
        return -1;
      }

      // 获取目标日期（从文件名或当前日期）
      final fileName = filePath.split('/').last.replaceAll('.csv', '');
      final dateStr = _parseDateString(fileName) ?? _formatDate(DateTime.now());

      final dirPath = await tracksDir;
      final targetFile = File('$dirPath/$dateStr.csv');

      // 追加写入（保留原数据）
      final buffer = StringBuffer();
      if (!await targetFile.exists()) {
        buffer.writeln('timestamp,latitude,longitude,altitude,speed,accuracy');
      }

      int count = 0;
      for (final row in dataRows) {
        if (row.length >= 6) {
          // 验证数据格式
          final lat = double.tryParse(row[1].toString());
          final lng = double.tryParse(row[2].toString());
          if (lat != null && lng != null) {
            buffer.writeln(row.join(','));
            count++;
          }
        }
      }

      if (count > 0) {
        await targetFile.writeAsString(buffer.toString(), mode: FileMode.append);
      }

      print('[CsvStorageService] 导入成功: $count 条记录到 $dateStr.csv');
      return count;
    } catch (e) {
      print('[CsvStorageService] 导入失败: $e');
      return -1;
    }
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  String? _parseDateString(String input) {
    // 尝试解析 YYYY-MM-DD 格式
    final regex = RegExp(r'(\d{4})-(\d{1,2})-(\d{1,2})');
    final match = regex.firstMatch(input);
    if (match != null) {
      final year = int.tryParse(match.group(1)!);
      final month = int.tryParse(match.group(2)!);
      final day = int.tryParse(match.group(3)!);
      if (year != null && month != null && day != null) {
        return '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
      }
    }
    return null;
  }
}
