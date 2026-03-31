import 'package:path_provider/path_provider.dart';

/// 轨迹存储管理器（单例）
/// 统一管理轨迹文件的根目录，避免路径不一致问题
class TrackStorageManager {
  static final TrackStorageManager _instance = TrackStorageManager._();
  factory TrackStorageManager() => _instance;
  TrackStorageManager._();

  static const String _folderName = 'location_tracks';

  String? _rootPath;
  bool _initialized = false;

  /// 是否已初始化
  bool get isInitialized => _initialized;

  /// 根目录路径（如未初始化会抛出异常）
  String get rootPath {
    if (_rootPath == null) {
      throw Exception('TrackStorageManager 未初始化，请先调用 init()');
    }
    return _rootPath!;
  }

  /// 初始化（应在 App 启动时调用一次）
  Future<void> init() async {
    if (_initialized) return;

    try {
      final dir = await getApplicationDocumentsDirectory();
      _rootPath = '${dir.path}/$_folderName';
      _initialized = true;
      print('[TrackStorageManager] 初始化完成: $_rootPath');
    } catch (e) {
      print('[TrackStorageManager] 初始化失败: $e');
      rethrow;
    }
  }

  /// 获取指定用户的轨迹目录
  String userDir(String phoneNumber) {
    return '$rootPath/$phoneNumber';
  }

  /// 获取指定日期的轨迹文件路径
  String dayFilePath(String phoneNumber, DateTime date) {
    return '$rootPath/$phoneNumber/'
        '${date.year}/'
        '${_padZero(date.month)}/'
        '${_padZero(date.day)}.csv';
  }

  /// 获取指定年月日的轨迹文件路径
  String dayFilePathByYMD(String phoneNumber, int year, int month, int day) {
    return '$rootPath/$phoneNumber/'
        '$year/'
        '${_padZero(month)}/'
        '${_padZero(day)}.csv';
  }

  String _padZero(int n) => n.toString().padLeft(2, '0');
}
