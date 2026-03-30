package com.kenny.trace_path;

import android.content.Intent;
import android.net.Uri;
import android.os.PowerManager;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

public class MainActivity extends FlutterActivity {
    private static final String CHANNEL = "com.kenny.trace_path/location_service";

    @Override
    public void configureFlutterEngine(FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);

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

                Intent intent = new Intent(MainActivity.this, LocationForegroundService.class);

                if (call.method.equals("start")) {
                    int interval = 10;
                    boolean powerSaving = false;
                    if (call.arguments() != null && call.arguments() instanceof java.util.Map) {
                        java.util.Map args = (java.util.Map) call.arguments();
                        interval = args.containsKey("interval") ? ((Number) args.get("interval")).intValue() : 10;
                        powerSaving = args.containsKey("powerSaving") && (Boolean) args.get("powerSaving");
                    }
                    intent.setAction("com.kenny.trace_path.START");
                    intent.putExtra("interval", interval * 1000L);
                    intent.putExtra("powerSaving", powerSaving);
                    MainActivity.this.startForegroundService(intent);
                    result.success(true);
                } else if (call.method.equals("stop")) {
                    intent.setAction("com.kenny.trace_path.STOP");
                    MainActivity.this.startService(intent);
                    result.success(true);
                } else if (call.method.equals("updateConfig")) {
                    if (call.arguments() != null && call.arguments() instanceof java.util.Map) {
                        java.util.Map args = (java.util.Map) call.arguments();
                        int interval = args.containsKey("interval") ? ((Number) args.get("interval")).intValue() : 10;
                        boolean powerSaving = args.containsKey("powerSaving") && (Boolean) args.get("powerSaving");
                        intent.setAction("com.kenny.trace_path.UPDATE_CONFIG");
                        intent.putExtra("interval", interval * 1000L);
                        intent.putExtra("powerSaving", powerSaving);
                        MainActivity.this.startService(intent);
                    }
                    result.success(true);
                } else if (call.method.equals("setPhoneNumber")) {
                    // 保存手机号到 SharedPreferences，供 LocationForegroundService 读取
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
                } else if (call.method.equals("isRunning")) {
                    // 使用 ActivityManager 检查真实运行状态
                    try {
                        android.app.ActivityManager am = (android.app.ActivityManager) getSystemService(android.content.Context.ACTIVITY_SERVICE);
                        for (android.app.ActivityManager.RunningServiceInfo service : am.getRunningServices(Integer.MAX_VALUE)) {
                            if ("com.kenny.trace_path.LocationForegroundService".equals(service.service.getClassName())) {
                                android.util.Log.d("MainActivity", "isRunning: service is ACTIVE");
                                result.success(true);
                                return;
                            }
                        }
                        android.util.Log.d("MainActivity", "isRunning: service NOT found");
                        result.success(false);
                    } catch (Exception e) {
                        android.util.Log.e("MainActivity", "isRunning check error: " + e.getMessage());
                        result.success(false);
                    }
                } else {
                    result.notImplemented();
                }
            });
    }
}
