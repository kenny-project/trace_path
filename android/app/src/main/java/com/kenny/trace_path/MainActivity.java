package com.kenny.trace_path;

import android.content.Intent;
import android.net.Uri;
import android.os.PowerManager;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

public class MainActivity extends FlutterActivity {
    private static final String CHANNEL = "com.kenny.trace_path/location_service";
    private LocationPlugin locationPlugin;

    @Override
    public void configureFlutterEngine(FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);

        // 注册原生定位处理器（native_location 通道）
        NativeLocationHandler.registerWith(this, flutterEngine);

        // 注册定位服务插件（包含 MethodChannel 和 EventChannel）
        locationPlugin = new LocationPlugin(this);
        locationPlugin.registerWith(flutterEngine);

        // 保留原有的系统相关 MethodChannel
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), CHANNEL)
            .setMethodCallHandler((call, result) -> {
                android.util.Log.d("MainActivity", "MethodChannel: method=" + call.method + ", args=" + call.arguments());

                if (call.method.equals("getManufacturer")) {
                    result.success(android.os.Build.MANUFACTURER);
                    return;
                }

                if (call.method.equals("openAutoStart")) {
                    try {
                        String pkg = call.argument("package");
                        String cls = call.argument("class");
                        if (pkg != null && cls != null) {
                            Intent i = new Intent();
                            i.setComponent(new android.content.ComponentName(pkg, cls));
                            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                            startActivity(i);
                            result.success(true);
                        } else {
                            result.success(false);
                        }
                    } catch (Exception e) {
                        Intent i = new Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS);
                        i.setData(Uri.parse("package:" + getPackageName()));
                        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                        startActivity(i);
                        result.success(false);
                    }
                    return;
                }

                if (call.method.equals("openBatteryOptimization")) {
                    try {
                        // 尝试跳转到品牌的电池优化页面
                        String pkg = call.argument("package");
                        String cls = call.argument("class");
                        if (pkg != null && cls != null) {
                            Intent i = new Intent();
                            i.setComponent(new android.content.ComponentName(pkg, cls));
                            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                            startActivity(i);
                            result.success(true);
                        } else {
                            // fallback到标准方式
                            Intent intent = new Intent(android.provider.Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS);
                            intent.setData(Uri.parse("package:" + getPackageName()));
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                            startActivity(intent);
                            result.success(true);
                        }
                    } catch (Exception e) {
                        // fallback到应用详情页
                        Intent i = new Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS);
                        i.setData(Uri.parse("package:" + getPackageName()));
                        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                        startActivity(i);
                        result.success(false);
                    }
                    return;
                }

                if (call.method.equals("isIgnoringBatteryOptimizations")) {
                    try {
                        PowerManager pm = (PowerManager) getSystemService(POWER_SERVICE);
                        boolean isIgnoring = pm.isIgnoringBatteryOptimizations(getPackageName());
                        result.success(isIgnoring);
                    } catch (Exception e) {
                        result.success(false);
                    }
                    return;
                }

                if (call.method.equals("getFilesDir")) {
                    try {
                        String filesPath = getFilesDir().getAbsolutePath();
                        result.success(filesPath);
                    } catch (Exception e) {
                        result.success(null);
                    }
                    return;
                }

                if (call.method.equals("setPhoneNumber")) {
                    // 保存手机号到 SharedPreferences
                    String phoneNumber = null;
                    if (call.arguments() != null && call.arguments() instanceof java.util.Map) {
                        java.util.Map args = (java.util.Map) call.arguments();
                        phoneNumber = args.containsKey("phoneNumber") ? (String) args.get("phoneNumber") : null;
                    }
                    if (phoneNumber != null) {
                        android.content.SharedPreferences prefs = getSharedPreferences("location_service_prefs", MODE_PRIVATE);
                        prefs.edit().putString("phone_number", phoneNumber).apply();
                        android.util.Log.d("MainActivity", "setPhoneNumber: " + phoneNumber);
                    }
                    result.success(true);
                    return;
                }

                // 其他方法转发给 locationPlugin 处理
                // 注意：start/stop/updateConfig/isRunning 已由 LocationPlugin 处理
                result.notImplemented();
            });
    }
}
