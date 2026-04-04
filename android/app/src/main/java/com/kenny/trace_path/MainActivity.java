package com.kenny.trace_path;

import android.content.Intent;
import android.net.Uri;
import android.os.PowerManager;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodChannel;

public class MainActivity extends FlutterActivity {
    private static final String LOCATION_SERVICE_CHANNEL = "com.kenny.trace_path/location_service";
    private static final String LOCATION_EVENTS_CHANNEL = "com.kenny.trace_path/location_events";

    private LocationPlugin locationPlugin;

    @Override
    public void configureFlutterEngine(FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);

        // 注册原生定位处理器（native_location 通道）
        NativeLocationHandler.registerWith(this, flutterEngine);

        // 注册定位服务插件（不创建独立 channel，由 MainActivity 统一管理）
        locationPlugin = new LocationPlugin(this);
        locationPlugin.registerWith(flutterEngine);

        // 统一管理 location_service MethodChannel
        // location_service 通道：同时处理定位服务方法（由 LocationPlugin 提供）
        //                       也处理系统方法（getManufacturer 等）
        EventChannel eventChannel = new EventChannel(
            flutterEngine.getDartExecutor().getBinaryMessenger(),
            LOCATION_EVENTS_CHANNEL
        );
        eventChannel.setStreamHandler(locationPlugin.getEventStreamHandler());

        MethodChannel methodChannel = new MethodChannel(
            flutterEngine.getDartExecutor().getBinaryMessenger(),
            LOCATION_SERVICE_CHANNEL
        );
        methodChannel.setMethodCallHandler((call, result) -> {
            android.util.Log.d("MainActivity", "MethodChannel: method=" + call.method + ", args=" + call.arguments());

            // 定位服务方法（委托给 LocationPlugin）
            switch (call.method) {
                case "startLocationService":
                case "start":
                    int interval = 30;
                    boolean powerSaving = false;
                    if (call.arguments() != null && call.arguments() instanceof java.util.Map) {
                        java.util.Map args = (java.util.Map) call.arguments();
                        interval = args.containsKey("interval") ? ((Number) args.get("interval")).intValue() : 30;
                        powerSaving = args.containsKey("powerSaving") && (Boolean) args.get("powerSaving");
                    }
                    locationPlugin.startLocationService(interval, powerSaving, result);
                    return;

                case "stopLocationService":
                case "stop":
                    locationPlugin.stopLocationService(result);
                    return;

                case "updateLocationConfig":
                case "updateConfig":
                    int updInterval = 30;
                    boolean updPowerSaving = false;
                    if (call.arguments() != null && call.arguments() instanceof java.util.Map) {
                        java.util.Map args = (java.util.Map) call.arguments();
                        updInterval = args.containsKey("interval") ? ((Number) args.get("interval")).intValue() : 30;
                        updPowerSaving = args.containsKey("powerSaving") && (Boolean) args.get("powerSaving");
                    }
                    locationPlugin.updateLocationConfig(updInterval, updPowerSaving, result);
                    return;

                case "isLocationServiceRunning":
                case "isRunning":
                    result.success(locationPlugin.isLocationServiceRunning());
                    return;

                case "setPhoneNumber":
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

            // 系统相关方法
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
                    String pkg = call.argument("package");
                    String cls = call.argument("class");
                    if (pkg != null && cls != null) {
                        Intent i = new Intent();
                        i.setComponent(new android.content.ComponentName(pkg, cls));
                        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                        startActivity(i);
                        result.success(true);
                    } else {
                        Intent intent = new Intent(android.provider.Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS);
                        intent.setData(Uri.parse("package:" + getPackageName()));
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                        startActivity(intent);
                        result.success(true);
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

            result.notImplemented();
        });
    }
}
