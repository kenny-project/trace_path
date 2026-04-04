import 'dart:io';
import 'dart:async';
import 'package:path_provider/path_provider.dart';

/// 错误日志标签类型
enum ErrorTag {
  gpsFail('[GPS_FAIL]'),
  gpsSuccess('[GPS_OK]'),
  networkFail('[NETWORK_FAIL]'),
  permission('[PERMISSION]'),
  service('[SERVICE]'),
  crash('[CRASH]'),
  other('[OTHER]'),
  app('[APP]');

  final String label;
  const ErrorTag(this.label);
}

/// 通用错误日志服务
/// 文件轮转：error.log -> error.log.1 -> error.log.2（最多2个历史）
class ErrorLoggerService {
  static final ErrorLoggerService _instance = ErrorLoggerService._();
  factory ErrorLoggerService() => _instance;
  ErrorLoggerService._();

  static const String _logFileName = 'error.log';
  static const String _logDirName = 'logs';
  static const int _maxFileSizeBytes = 20 * 1024 * 1024; // 20MB

  String? _logDirPath;
  
  // 写入队列，确保日志不丢失
  final _writeQueue = <String>[];
  bool _isWriting = false;

  /// 初始化，获取日志目录路径
  Future<void> init() async {
    final appDir = await getApplicationDocumentsDirectory();
    _logDirPath = '${appDir.path}/$_logDirName';
    
    final dir = Directory(_logDirPath!);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  /// 记录错误日志（异步写入，不阻塞）
  Future<void> log(ErrorTag tag, String message) async {
    if (_logDirPath == null) await init();
    
    final timestamp = _formatTimestamp(DateTime.now());
    final logLine = '[$timestamp] ${tag.label} $message';
    
    // 加入写入队列
    _writeQueue.add(logLine);
    _processWriteQueue();
  }

  /// 处理写入队列
  Future<void> _processWriteQueue() async {
    if (_isWriting || _writeQueue.isEmpty) return;
    try {
      _isWriting = true;
      while (_writeQueue.isNotEmpty) {
        await _writeToFile(_writeQueue.removeAt(0));
      }
    } finally {
      _isWriting = false;
    }
  }

  /// 记录应用启动
  Future<void> logAppStart() async {
    // 添加分割线
    _writeQueue.add('--- APP STARTED ---');
    _processWriteQueue();
  }

  /// 记录应用关闭
  Future<void> logAppStop() async {
    _writeQueue.add('--- APP STOPPED ---');
    _processWriteQueue();
  }

  /// 写入单个日志行到文件
  Future<void> _writeToFile(String logLine) async {
    final file = File('$_logDirPath/$_logFileName');
    
    try {
      // 检查文件大小，必要时轮转
      if (await file.exists()) {
        final size = await file.length();
        if (size >= _maxFileSizeBytes) {
          await _rotateFile();
        }
      }
      
      // 追加写入
      final raf = await file.open(mode: FileMode.append);
      await raf.writeString('$logLine\n');
      await raf.close();
    } catch (e) {
      print('[ErrorLogger] 写入日志失败: $e');
    }
  }

  /// 执行文件轮转
  Future<void> _rotateFile() async {
    final file = File('$_logDirPath/$_logFileName');
    final log1 = File('$_logDirPath/$_logFileName.1');
    final log2 = File('$_logDirPath/$_logFileName.2');
    
    try {
      // 删除最老的
      if (await log2.exists()) {
        await log2.delete();
      }
      
      // log1 -> log2
      if (await log1.exists()) {
        await log1.rename('$_logDirPath/$_logFileName.2');
      }
      
      // 当前日志 -> log1
      await file.rename('$_logDirPath/$_logFileName.1');
      
      // 创建新的空文件
      await file.writeAsString('');
    } catch (e) {
      print('[ErrorLogger] 文件轮转失败: $e');
    }
  }

  /// GPS定位失败日志
  Future<void> logGpsFail({
    required String reason,
    double? accuracy,
    int? timeout,
    int failCount = 1,
    String? extra,
  }) async {
    String msg = 'reason=$reason failCount=$failCount';
    if (accuracy != null) msg += ' accuracy=${accuracy}m';
    if (timeout != null) msg += ' timeout=${timeout}s';
    if (extra != null) msg += ' extra=$extra';
    
    await log(ErrorTag.gpsFail, msg);
  }

  /// 网络定位失败日志
  Future<void> logNetworkFail({
    required String reason,
    int? timeout,
    String? extra,
  }) async {
    String msg = 'reason=$reason';
    if (timeout != null) msg += ' timeout=${timeout}s';
    if (extra != null) msg += ' extra=$extra';
    
    await log(ErrorTag.networkFail, msg);
  }

  /// GPS定位成功日志（每10次记录一次）
  Future<void> logGpsSuccess({
    required double lat,
    required double lng,
    required double accuracy,
    int successCount = 1,
  }) async {
    String msg = 'lat=$lat lng=$lng accuracy=${accuracy}m successCount=$successCount';
    await log(ErrorTag.gpsSuccess, msg);
  }

  /// 首次定位日志
  Future<void> logFirstLocation({
    required double lat,
    required double lng,
    required double accuracy,
  }) async {
    String msg = 'lat=$lat lng=$lng accuracy=${accuracy}m type=FIRST';
    await log(ErrorTag.gpsSuccess, msg);
  }

  /// 权限问题日志
  Future<void> logPermission({
    required String permission,
    required String reason,
  }) async {
    await log(ErrorTag.permission, 'permission=$permission reason=$reason');
  }

  /// 服务状态变更日志
  Future<void> logService({
    required String action,
    String? extra,
  }) async {
    String msg = 'action=$action';
    if (extra != null) msg += ' $extra';
    
    await log(ErrorTag.service, msg);
  }

  /// 读取当前日志文件内容
  Future<String> readCurrentLogs() async {
    if (_logDirPath == null) await init();
    
    final file = File('$_logDirPath/$_logFileName');
    if (!await file.exists()) {
      return '';
    }
    
    try {
      return await file.readAsString();
    } catch (e) {
      return '读取日志失败: $e';
    }
  }

  /// 读取所有日志文件（当前 + 轮转的）
  Future<Map<String, String>> readAllLogs() async {
    if (_logDirPath == null) await init();
    
    final result = <String, String>{};
    
    // 读取当前日志
    final currentFile = File('$_logDirPath/$_logFileName');
    if (await currentFile.exists()) {
      try {
        result['error.log'] = await currentFile.readAsString();
      } catch (e) {
        result['error.log'] = '读取失败: $e';
      }
    }
    
    // 读取轮转日志
    final log1 = File('$_logDirPath/$_logFileName.1');
    if (await log1.exists()) {
      try {
        result['error.log.1'] = await log1.readAsString();
      } catch (e) {
        result['error.log.1'] = '读取失败: $e';
      }
    }
    
    final log2 = File('$_logDirPath/$_logFileName.2');
    if (await log2.exists()) {
      try {
        result['error.log.2'] = await log2.readAsString();
      } catch (e) {
        result['error.log.2'] = '读取失败: $e';
      }
    }
    
    return result;
  }

  /// 清空当前日志（不删除文件）
  Future<void> clearCurrentLogs() async {
    if (_logDirPath == null) await init();
    
    final file = File('$_logDirPath/$_logFileName');
    if (await file.exists()) {
      await file.writeAsString('');
    }
  }

  /// 获取日志文件信息
  Future<Map<String, dynamic>> getLogInfo() async {
    if (_logDirPath == null) await init();
    
    final file = File('$_logDirPath/$_logFileName');
    int size = 0;
    int lineCount = 0;
    
    if (await file.exists()) {
      size = await file.length();
      final content = await file.readAsString();
      lineCount = content.split('\n').where((l) => l.isNotEmpty).length;
    }
    
    return {
      'currentSize': size,
      'currentLines': lineCount,
      'maxSizeBytes': _maxFileSizeBytes,
    };
  }

  /// 检查是否需要轮转
  Future<void> _rotateIfNeeded(File file) async {
    if (!await file.exists()) return;
    
    final size = await file.length();
    if (size < _maxFileSizeBytes) return;
    
    // 文件超过20MB，执行轮转
    // error.log -> error.log.1 -> error.log.2 -> 删除
    
    final dir = file.parent.path;
    final log1 = File('$dir/$_logFileName.1');
    final log2 = File('$dir/$_logFileName.2');
    
    // 删除最老的
    if (await log2.exists()) {
      await log2.delete();
    }
    
    // log1 -> log2
    if (await log1.exists()) {
      await log1.rename('$dir/$_logFileName.2');
    }
    
    // 当前日志 -> log1
    await file.rename('$dir/$_logFileName.1');
    
    // 创建新的空文件
    await file.writeAsString('');
  }

  String _formatTimestamp(DateTime t) {
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} '
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}.${t.millisecond.toString().padLeft(3, '0')}';
  }
}
