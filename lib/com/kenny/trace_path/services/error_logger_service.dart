import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// 默认Tag列表（用于首次进入页面时展示）
const _defaultTags = ['ALFS', 'FBLS', 'TRACK', 'LocationPlugin', 'APP', 'GPS_FAIL', 'GPS_OK', 'NETWORK_FAIL', 'DEBUG'];

/// 日志行数据（包含原始行号）
class LogLine {
  final String fileName;
  final int lineNumber;
  final String content;
  final String? tag;

  LogLine({
    required this.fileName,
    required this.lineNumber,
    required this.content,
    this.tag,
  });
}

/// 错误日志标签类型
enum ErrorTag {
  gpsFail('[GPS_FAIL]'),
  gpsSuccess('[GPS_OK]'),
  networkFail('[NETWORK_FAIL]'),
  permission('[PERMISSION]'),
  service('[FBLS]'),
  crash('[CRASH]'),
  other('[OTHER]'),
  app('[APP]'),
  debug('[DEBUG]');

  final String label;
  const ErrorTag(this.label);
}

/// 通用错误日志服务
/// 文件轮转：error.log -> error.log.1 -> error.log.2（最多2个历史）
///
/// 使用异步队列处理高频日志写入，避免阻塞主线程
class ErrorLoggerService {
  static final ErrorLoggerService _instance = ErrorLoggerService._();
  factory ErrorLoggerService() => _instance;
  ErrorLoggerService._();

  static const String _logFileName = 'error.log';
  static const String _logDirName = 'logs';
  static const int _maxFileSizeBytes = 20 * 1024 * 1024; // 20MB

  String? _logDirPath;

  // 异步写入队列（统一处理 Flutter 和原生日志）
  final _writeQueue = <String>[];
  bool _isWriting = false;

  // 写入控制信号
  final _controller = StreamController<void>.broadcast();

  /// 初始化，获取日志目录路径
  Future<void> init() async {
    final appDir = await getApplicationDocumentsDirectory();
    _logDirPath = '${appDir.path}/$_logDirName';

    final dir = Directory(_logDirPath!);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    // 启动异步处理循环
    _startProcessingLoop();

    // 设置原生日志 MethodChannel 监听
    _setupNativeLogChannel();
  }

  static const _nativeLogChannel = MethodChannel('com.kenny.trace_path/native_log');

  void _setupNativeLogChannel() {
    _nativeLogChannel.setMethodCallHandler((call) async {
      if (call.method == 'log') {
        final args = call.arguments as Map<dynamic, dynamic>;
        final level = args['level'] as String;
        final tag = args['tag'] as String;
        final message = args['message'] as String;
        logNative(level, tag, message);
      }
      return null;
    });
  }

  /// 启动异步处理循环
  void _startProcessingLoop() {
    _controller.stream.listen((_) {
      _processQueueAsync();
    });
  }

  /// 触发队列处理
  void _scheduleProcess() {
    _controller.add(null);
  }

  /// 处理写入队列（异步）
  Future<void> _processQueueAsync() async {
    if (_isWriting || _writeQueue.isEmpty) return;

    _isWriting = true;
    try {
      final batch = <String>[];
      while (_writeQueue.isNotEmpty) {
        batch.add(_writeQueue.removeAt(0));
      }

      if (batch.isNotEmpty) {
        await _writeBatchToFile(batch);
      }
    } catch (e) {
      print('[ErrorLogger] 写入失败: $e');
    } finally {
      _isWriting = false;

      if (_writeQueue.isNotEmpty) {
        Future.microtask(_processQueueAsync);
      }
    }
  }

  /// 批量写入日志到文件
  Future<void> _writeBatchToFile(List<String> batch) async {
    if (_logDirPath == null) return;

    final file = File('$_logDirPath/$_logFileName');

    try {
      if (await file.exists()) {
        final size = await file.length();
        if (size >= _maxFileSizeBytes) {
          await _rotateFile();
        }
      }

      final raf = await file.open(mode: FileMode.append);
      try {
        for (final line in batch) {
          await raf.writeString('$line\n');
        }
      } finally {
        await raf.close();
      }
    } catch (e) {
      print('[ErrorLogger] 批量写入日志失败: $e');
    }
  }

  /// 记录错误日志（异步写入，不阻塞）
  Future<void> log(ErrorTag tag, String message) async {
    if (_logDirPath == null) {
      await init();
    }

    final timestamp = _formatTimestamp(DateTime.now());
    final logLine = '[$timestamp] ${tag.label} $message';

    _writeQueue.add(logLine);
    _scheduleProcess();
  }

  /// 记录原生日志（异步写入，不阻塞）
  /// 原生日志和 Flutter 日志都写入同一个文件
  Future<void> logNative(String level, String tag, String message) async {
    if (_logDirPath == null) {
      await init();
    }

    final timestamp = _formatTimestamp(DateTime.now());
    final logLine = '[$timestamp] $level [$tag] $message';

    _writeQueue.add(logLine);
    _scheduleProcess();
  }

  /// 记录应用启动
  void logAppStart() {
    _writeQueue.add('--- APP STARTED ---');
    _scheduleProcess();
  }

  /// 记录应用关闭
  void logAppStop() {
    _writeQueue.add('--- APP STOPPED ---');
    _scheduleProcess();
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

  /// 通用调试日志
  Future<void> logDebug(String message) async {
    await log(ErrorTag.debug, message);
  }

  /// 执行文件轮转（最多保留5个历史文件）
  Future<void> _rotateFile() async {
    final file = File('$_logDirPath/$_logFileName');

    try {
      // 删除最旧的 .4 文件
      final log4 = File('$_logDirPath/$_logFileName.4');
      if (await log4.exists()) await log4.delete();

      // 依次轮转 .3 -> .4, .2 -> .3, .1 -> .2
      for (int i = 3; i >= 1; i--) {
        final current = File('$_logDirPath/$_logFileName.$i');
        final next = File('$_logDirPath/$_logFileName.${i + 1}');
        if (await current.exists()) {
          await current.rename(next.path);
        }
      }

      // 当前文件 -> .1
      await file.rename('$_logDirPath/$_logFileName.1');
      await file.writeAsString('');
    } catch (e) {
      print('[ErrorLogger] 文件轮转失败: $e');
    }
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

  /// 读取所有日志文件（支持最多5个历史文件）
  Future<Map<String, String>> readAllLogs() async {
    if (_logDirPath == null) await init();

    final result = <String, String>{};

    final currentFile = File('$_logDirPath/$_logFileName');
    if (await currentFile.exists()) {
      try {
        result['error.log'] = await currentFile.readAsString();
      } catch (e) {
        result['error.log'] = '读取失败: $e';
      }
    }

    for (int i = 1; i <= 4; i++) {
      final logFile = File('$_logDirPath/$_logFileName.$i');
      if (await logFile.exists()) {
        try {
          result['error.log.$i'] = await logFile.readAsString();
        } catch (e) {
          result['error.log.$i'] = '读取失败: $e';
        }
      }
    }

    return result;
  }

  /// 清空当前日志
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

  /// 获取队列中待写入的日志数量
  int get pendingLogs => _writeQueue.length;

  /// 从日志内容中提取所有唯一的Tag
  /// [logContent] 原始日志内容
  /// 返回Tag列表（按发现顺序）
  Set<String> _extractTagsFromContent(String logContent) {
    final tags = <String>{};
    // 匹配 [TAG] 格式的Tag（支持大小写混合）
    final tagRegex = RegExp(r'\[([A-Za-z0-9_]+)\]');
    for (final match in tagRegex.allMatches(logContent)) {
      tags.add(match.group(1)!);
    }
    return tags;
  }

  /// 获取所有日志文件中的唯一Tag列表（首次扫描时调用）
  /// 返回所有发现的Tag，包含默认Tag列表
  Future<Set<String>> getUniqueTags() async {
    if (_logDirPath == null) await init();

    final allTags = <String>{..._defaultTags};
    final logs = await readAllLogs();

    for (final content in logs.values) {
      allTags.addAll(_extractTagsFromContent(content));
    }

    return allTags;
  }

  /// 读取所有日志并按Tag过滤
  /// [selectedTags] 要显示的Tag集合，null表示显示所有
  /// 返回按文件组织的日志行列表
  Future<List<LogLine>> readLogsWithFilter(Set<String>? selectedTags) async {
    if (_logDirPath == null) await init();

    final result = <LogLine>[];
    final logs = await readAllLogs();

    for (final entry in logs.entries) {
      final fileName = entry.key;
      final content = entry.value;
      final lines = content.split('\n');

      for (int i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.isEmpty) continue;

        // 提取Tag
        final tagMatch = RegExp(r'\[([A-Za-z0-9_]+)\]').firstMatch(line);
        final tag = tagMatch?.group(1);

        // 如果没有选择过滤条件，或Tag在选中列表中，则添加
        if (selectedTags == null || selectedTags.isEmpty || (tag != null && selectedTags.contains(tag))) {
          result.add(LogLine(
            fileName: fileName,
            lineNumber: i + 1,
            content: line,
            tag: tag,
          ));
        }
      }
    }

    return result;
  }

  String _formatTimestamp(DateTime t) {
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} '
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}.${t.millisecond.toString().padLeft(3, '0')}';
  }
}