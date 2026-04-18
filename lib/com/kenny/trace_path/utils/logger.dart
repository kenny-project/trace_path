import 'package:flutter/foundation.dart';
import '../services/error_logger_service.dart';

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

  static const debug = LogTag('DEBUG', '🔍');
  static const location = LogTag('LOCATION', '📍');
  static const track = LogTag('TRACK', '🛤️');
  static const service = LogTag('SERVICE', '⚙️');
  static const ui = LogTag('UI', '🖼️');
  static const storage = LogTag('STORAGE', '💾');
  static const network = LogTag('NET', '🌐');
  static const error = LogTag('ERROR', '❌');
}

/// 统一日志门面
///
/// 使用方式：
/// ```dart
/// import '../utils/logger.dart';
///
/// Log.d(LogTag.location, '服务启动');
/// Log.e(LogTag.error, '定位失败: $e');
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
    final logLine = '[$timestamp] $levelStr [${tag.name}] ${tag.emoji} $message';

    // 输出到控制台
    if (kDebugMode) {
      if (level == LogLevel.error && error != null) {
        debugPrintStack(label: logLine, stackTrace: stackTrace);
      } else {
        debugPrint(logLine);
      }
    }

    // 写入 ErrorLoggerService（异步，不阻塞）
    ErrorLoggerService().logNative(levelStr, tag.name, error != null ? '$message $error' : message);
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
