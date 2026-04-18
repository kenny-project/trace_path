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

    public static void d(String tag, String message) {
        Log.d(tag, message);
        sendToFlutter("D", tag, message);
    }

    public static void i(String tag, String message) {
        Log.i(tag, message);
        sendToFlutter("I", tag, message);
    }

    public static void w(String tag, String message) {
        Log.w(tag, message);
        sendToFlutter("W", tag, message);
    }

    public static void w(String tag, String message, Throwable throwable) {
        Log.w(tag, message, throwable);
        sendToFlutter("W", tag, message);
    }

    public static void e(String tag, String message) {
        Log.e(tag, message);
        sendToFlutter("E", tag, message);
    }

    public static void e(String tag, String message, Throwable throwable) {
        Log.e(tag, message, throwable);
        sendToFlutter("E", tag, message);
    }

    public static void v(String tag, String message) {
        Log.v(tag, message);
        sendToFlutter("D", tag, message);
    }

    public static void wtf(String tag, String message) {
        Log.wtf(tag, message);
        sendToFlutter("E", tag, message);
    }

    public static void wtf(String tag, Throwable throwable) {
        Log.wtf(tag, throwable);
        sendToFlutter("E", tag, throwable.getMessage());
    }
}