package com.kenny.trace_path;

import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodChannel;
import java.util.HashMap;

/**
 * 统一日志门面
 *
 * 同时完成：
 * - Log.* 输出到控制台（原生行为）
 * - MethodChannel 转发到 Flutter 落盘
 *
 * 使用方式与原生 Log 完全一致：
 * TraceLog.d(TAG, "message");
 * TraceLog.e(TAG, "error", throwable);
 */
public class TraceLog {

    private static final String CHANNEL_NAME = "com.kenny.trace_path/native_log";
    private static MethodChannel channel;
    private static final Handler mainHandler = new Handler(Looper.getMainLooper());

    private TraceLog() {}

    public static void init(BinaryMessenger messenger) {
        if (channel != null) return;
        channel = new MethodChannel(messenger, CHANNEL_NAME);
        Log.i("TraceLog", "TraceLog initialized");
    }

    private static void sendToFlutter(String level, String tag, String message) {
        if (channel == null) {
            Log.w("TraceLog", "Channel not initialized, log dropped");
            return;
        }

        mainHandler.post(() -> {
            try {
                channel.invokeMethod("log", new HashMap() {{
                    put("level", level);
                    put("tag", tag);
                    put("message", message);
                }});
            } catch (Exception e) {
                Log.e("TraceLog", "Failed to send log to Flutter", e);
            }
        });
    }

    /// 从堆栈提取调用方的文件名和行号，格式：xxx.java:123
    private static String _callerInfo() {
        try {
            StackTraceElement[] stack = Thread.currentThread().getStackTrace();
            // stack[0]=Thread.getStackTrace, stack[1]=_callerInfo, stack[2]=实际调用者
            if (stack.length >= 3) {
                StackTraceElement caller = stack[2];
                String fileName = caller.getFileName();
                int lineNumber = caller.getLineNumber();
                if (fileName != null && lineNumber > 0) {
                    return "[" + fileName + ":" + lineNumber + "] ";
                }
            }
        } catch (Exception ignored) {}
        return "";
    }

    public static void d(String tag, String message) {
        String info = _callerInfo();
        Log.d(tag, info + message);
        sendToFlutter("D", tag, info + message);
    }

    public static void i(String tag, String message) {
        String info = _callerInfo();
        Log.i(tag, info + message);
        sendToFlutter("I", tag, info + message);
    }

    public static void w(String tag, String message) {
        String info = _callerInfo();
        Log.w(tag, info + message);
        sendToFlutter("W", tag, info + message);
    }

    public static void w(String tag, String message, Throwable throwable) {
        String info = _callerInfo();
        Log.w(tag, info + message, throwable);
        sendToFlutter("W", tag, info + message);
    }

    public static void e(String tag, String message) {
        String info = _callerInfo();
        Log.e(tag, info + message);
        sendToFlutter("E", tag, info + message);
    }

    public static void e(String tag, String message, Throwable throwable) {
        String info = _callerInfo();
        Log.e(tag, info + message, throwable);
        sendToFlutter("E", tag, info + message);
    }

    public static void v(String tag, String message) {
        String info = _callerInfo();
        Log.v(tag, info + message);
        sendToFlutter("D", tag, info + message);
    }

    public static void wtf(String tag, String message) {
        String info = _callerInfo();
        Log.wtf(tag, info + message);
        sendToFlutter("E", tag, info + message);
    }

    public static void wtf(String tag, Throwable throwable) {
        String info = _callerInfo();
        Log.wtf(tag, info + throwable.getMessage(), throwable);
        sendToFlutter("E", tag, info + throwable.getMessage());
    }
}