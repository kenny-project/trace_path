import 'package:flutter/foundation.dart';
import 'package:trace_path/com/kenny/trace_path/services/error_logger_service.dart';

/// 日志级别
enum LogLevel {
  debug,
  info,
  warning,
  error,
}

/// 日志标签
class LogTag {
  final String name;
  final String emoji;

  const LogTag(this.name, this.emoji);

  static const DEBUG = LogTag('DEBUG', '🔍');
  static const FBLS = LogTag('FBLS', '📍');
  static const TRACK = LogTag('TRACK', '🛤️');
  static const SRVC = LogTag('SRVC', '⚙️');
  static const UI = LogTag('UI', '🖼️');
  static const STORAGE = LogTag('STORAGE', '💾');
  static const NETWORK = LogTag('NET', '🌐');
  static const ERROR = LogTag('ERROR', '❌');
}

/// 统一日志门面
///
/// 使用方式：
/// ```dart
/// import '../utils/logger.dart';
///
/// Log.d(LogTag.FBLS, '服务启动');
/// Log.e(LogTag.ERROR, '定位失败: $e');
/// ```
class Log {
  Log._();

  /// 是否启用调试日志（生产环境可关闭）
  static bool _debugMode = true;

  /// 设置调试模式
  static void setDebugMode(bool enabled) {
    _debugMode = enabled;
  }

  /// 调试日志
  static void d(LogTag tag, String message) {
    if (!_debugMode) return;
    _log(LogLevel.debug, tag, message);
  }

  /// 信息日志
  static void i(LogTag tag, String message) {
    _log(LogLevel.info, tag, message);
  }

  /// 警告日志
  static void w(LogTag tag, String message) {
    _log(LogLevel.warning, tag, message);
  }

  /// 错误日志
  static void e(LogTag tag, String message, [Object? error, StackTrace? stackTrace]) {
    _log(LogLevel.error, tag, message, error, stackTrace);
  }

  static void _log(
    LogLevel level,
    LogTag tag,
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) {
    final timestamp = DateTime.now().toString().substring(11, 23);
    final levelStr = _levelString(level);
    final callerInfo = _getCallerInfo();
    final logLine = '[$timestamp] $levelStr [${tag.name}] ${tag.emoji} $callerInfo $message';

    // 输出到控制台
    if (kDebugMode) {
      if (level == LogLevel.error && error != null) {
        debugPrintStack(label: logLine, stackTrace: stackTrace);
      } else {
        debugPrint(logLine);
      }
    }

    // 写入 ErrorLoggerService（异步，不阻塞）
    final fileMessage = '$callerInfo $message${error != null ? ' $error' : ''}';
    ErrorLoggerService().logNative(levelStr, tag.name, fileMessage);
  }

  /// 从堆栈提取调用方的文件名和行号
  /// 格式：xxx.dart:123
  static String _getCallerInfo() {
    try {
      final stack = StackTrace.current.toString().split('\n');
      // stack[0]=Log._getCallerInfo, stack[1]=Log._log, stack[2]=Log.d/i/w/e, stack[3]=实际调用者
      if (stack.length >= 4) {
        final frame = stack[3].trim();
        // 匹配 (path/file.dart:line:col) → 提取 path/file.dart:line
        final match = RegExp(r'\(([^)]+:\d+)').firstMatch(frame);
        if (match != null) {
          final full = match.group(1)!;
          // 提取最后一个路径段（文件名）
          final lastSlash = full.lastIndexOf('/');
          final fileAndLine = lastSlash >= 0 ? full.substring(lastSlash + 1) : full;
          return '[$fileAndLine]';
        }
      }
    } catch (_) {}
    return '';
  }

  static String _levelString(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return 'D';
      case LogLevel.info:
        return 'I';
      case LogLevel.warning:
        return 'W';
      case LogLevel.error:
        return 'E';
    }
  }
}
