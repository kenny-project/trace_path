package com.example.trace_path;

import android.content.Intent;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

public class MainActivity extends FlutterActivity {
    private static final String CHANNEL = "com.example.trace_path/location_service";

    @Override
    public void configureFlutterEngine(FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);

        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), CHANNEL)
            .setMethodCallHandler((call, result) -> {
                android.util.Log.d("MainActivity", "MethodChannel: method=" + call.method + ", args=" + call.arguments());
                Intent intent = new Intent(MainActivity.this, LocationForegroundService.class);

                if (call.method.equals("start")) {
                    // 从 args 获取配置（interval秒，powerSaving）
                    int interval = 10;
                    boolean powerSaving = false;
                    if (call.arguments() != null && call.arguments() instanceof java.util.Map) {
                        java.util.Map args = (java.util.Map) call.arguments();
                        interval = args.containsKey("interval") ? ((Number) args.get("interval")).intValue() : 10;
                        powerSaving = args.containsKey("powerSaving") && (Boolean) args.get("powerSaving");
                    }
                    android.util.Log.d("MainActivity", "start: interval=" + interval + ", powerSaving=" + powerSaving);
                    intent.setAction("com.example.trace_path.START");
                    intent.putExtra("interval", interval * 1000L); // 转毫秒
                    intent.putExtra("powerSaving", powerSaving);
                    MainActivity.this.startForegroundService(intent);
                    android.util.Log.d("MainActivity", "startForegroundService started");
                    result.success(true);
                } else if (call.method.equals("stop")) {
                    intent.setAction("com.example.trace_path.STOP");
                    MainActivity.this.startService(intent);
                    result.success(true);
                } else if (call.method.equals("updateConfig")) {
                    // 热更新配置
                    if (call.arguments() != null && call.arguments() instanceof java.util.Map) {
                        java.util.Map args = (java.util.Map) call.arguments();
                        int interval = args.containsKey("interval") ? ((Number) args.get("interval")).intValue() : 10;
                        boolean powerSaving = args.containsKey("powerSaving") && (Boolean) args.get("powerSaving");
                        intent.setAction("com.example.trace_path.UPDATE_CONFIG");
                        intent.putExtra("interval", interval * 1000L);
                        intent.putExtra("powerSaving", powerSaving);
                        MainActivity.this.startService(intent);
                    }
                    result.success(true);
                } else if (call.method.equals("isRunning")) {
                    result.success(false);
                } else {
                    result.notImplemented();
                }
            });
    }
}
