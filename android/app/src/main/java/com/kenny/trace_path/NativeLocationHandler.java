package com.kenny.trace_path;

import android.Manifest;
import android.content.Context;
import android.content.pm.PackageManager;
import android.location.Location;
import android.os.Looper;
import android.util.Log;

import androidx.annotation.NonNull;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;

import com.google.android.gms.location.FusedLocationProviderClient;
import com.google.android.gms.location.LocationCallback;
import com.google.android.gms.location.LocationRequest;
import com.google.android.gms.location.LocationResult;
import com.google.android.gms.location.LocationServices;
import com.google.android.gms.location.Priority;

import java.util.HashMap;
import java.util.Map;

import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/**
 * Android 原生定位处理器
 * 使用 FusedLocationProviderClient 获取位置
 */
public class NativeLocationHandler implements MethodChannel.MethodCallHandler {
    private static final String TAG = "NativeLocationHandler";
    private static final String CHANNEL_NAME = "com.kenny.trace_path/native_location";

    // 权限请求码
    private static final int PERMISSION_REQUEST_CODE = 1001;

    private final Context context;
    private final FusedLocationProviderClient fusedLocationClient;

    public NativeLocationHandler(Context context) {
        this.context = context;
        this.fusedLocationClient = LocationServices.getFusedLocationProviderClient(context);
    }

    /**
     * 注册 MethodChannel
     */
    public static void registerWith(Context context, io.flutter.embedding.engine.FlutterEngine flutterEngine) {
        MethodChannel channel = new MethodChannel(
                flutterEngine.getDartExecutor().getBinaryMessenger(),
                CHANNEL_NAME
        );
        NativeLocationHandler handler = new NativeLocationHandler(context);
        channel.setMethodCallHandler(handler);
        Log.d(TAG, "NativeLocationHandler registered");
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        Log.d(TAG, "onMethodCall: method=" + call.method + ", args=" + call.arguments());

        switch (call.method) {
            case "getCurrentLocation":
                handleGetCurrentLocation(call, result);
                break;
            case "checkPermission":
                handleCheckPermission(result);
                break;
            case "isLocationServiceEnabled":
                handleIsLocationServiceEnabled(result);
                break;
            case "requestPermission":
                // Flutter 端通过 permission_handler 处理权限，这里只做兜底检查
                handleRequestPermission(result);
                break;
            default:
                result.notImplemented();
                break;
        }
    }

    /**
     * 获取当前位置
     * args: {useHighAccuracy: bool, timeoutMs: int}
     */
    /**
     * 获取当前位置
     * args: {useHighAccuracy: bool, timeoutMs: int}
     * 
     * 超时时间设置参考（来自高德/百度建议）：
     * - GPS首次定位：通常30-60秒，信号差环境（地铁/室内）可能更长
     * - 默认超时：45000ms (45秒) = GPS 30秒 + 网络15秒
     */
    private void handleGetCurrentLocation(MethodCall call, MethodChannel.Result result) {
        boolean useHighAccuracy = call.argument("useHighAccuracy") != null
                && (Boolean) call.argument("useHighAccuracy");
        // 默认45秒超时（GPS 30秒 + 网络15秒），参考高德/百度建议
        int timeoutMs = call.argument("timeoutMs") != null
                ? ((Number) call.argument("timeoutMs")).intValue()
                : 45000;

        Log.d(TAG, "getCurrentLocation: useHighAccuracy=" + useHighAccuracy + ", timeoutMs=" + timeoutMs);

        // 检查权限
        if (!hasLocationPermission()) {
            Log.w(TAG, "getCurrentLocation: no permission");
            result.error("PERMISSION_DENIED", "Location permission not granted", null);
            return;
        }

        // 检查服务是否启用
        if (!isLocationServiceEnabled()) {
            Log.w(TAG, "getCurrentLocation: location service disabled");
            result.error("SERVICE_DISABLED", "Location service is disabled", null);
            return;
        }

        // 使用 FusedLocationProviderClient 获取一次性位置
        try {
            fusedLocationClient.getCurrentLocation(
                    useHighAccuracy ? Priority.PRIORITY_HIGH_ACCURACY : Priority.PRIORITY_BALANCED_POWER_ACCURACY,
                    null // 使用最后一次已知位置（如果足够新鲜）或请求新的
            ).addOnSuccessListener(location -> {
                if (location != null) {
                    Log.d(TAG, "getCurrentLocation success: lat=" + location.getLatitude()
                            + ", lng=" + location.getLongitude()
                            + ", acc=" + location.getAccuracy());
                    Map<String, Object> positionMap = locationToMap(location);
                    result.success(positionMap);
                } else {
                    Log.w(TAG, "getCurrentLocation: location is null, try requesting fresh location");
                    // 如果最后位置为空，尝试请求新位置
                    requestFreshLocation(useHighAccuracy, timeoutMs, result);
                }
            }).addOnFailureListener(e -> {
                Log.e(TAG, "getCurrentLocation failed", e);
                String errorCode = "LOCATION_FAILED";
                if (e instanceof SecurityException) {
                    errorCode = "PERMISSION_DENIED";
                } else if (e instanceof java.lang.IllegalStateException) {
                    errorCode = "SERVICE_NOT_AVAILABLE";
                }
                result.error(errorCode, e.getMessage(), null);
            });
        } catch (SecurityException e) {
            Log.e(TAG, "SecurityException in getCurrentLocation", e);
            result.error("PERMISSION_DENIED", e.getMessage(), null);
        }
    }

    /**
     * 请求新鲜位置（一次性定位）
     */
    private void requestFreshLocation(boolean useHighAccuracy, int timeoutMs, MethodChannel.Result result) {
        LocationRequest locationRequest = new LocationRequest.Builder(
                useHighAccuracy ? Priority.PRIORITY_HIGH_ACCURACY : Priority.PRIORITY_BALANCED_POWER_ACCURACY,
                0 // 立即获取，不需要周期性更新
        ).setMaxUpdates(1).build();

        LocationCallback locationCallback = new LocationCallback() {
            @Override
            public void onLocationResult(@NonNull LocationResult locationResult) {
                fusedLocationClient.removeLocationUpdates(this);
                Location location = locationResult.getLastLocation();
                if (location != null) {
                    Log.d(TAG, "requestFreshLocation success: lat=" + location.getLatitude()
                            + ", lng=" + location.getLongitude());
                    Map<String, Object> positionMap = locationToMap(location);
                    result.success(positionMap);
                } else {
                    Log.w(TAG, "requestFreshLocation: location is null");
                    result.error("TIMEOUT", "Unable to get location within timeout", null);
                }
            }
        };

        try {
            fusedLocationClient.requestLocationUpdates(locationRequest, locationCallback, Looper.getMainLooper());

            // 超时处理
            android.os.Handler mainHandler = new android.os.Handler(Looper.getMainLooper());
            mainHandler.postDelayed(() -> {
                fusedLocationClient.removeLocationUpdates(locationCallback);
                Log.w(TAG, "requestFreshLocation: timeout after " + timeoutMs + "ms");
                result.error("TIMEOUT", "Location request timed out", null);
            }, timeoutMs);
        } catch (SecurityException e) {
            Log.e(TAG, "SecurityException in requestFreshLocation", e);
            result.error("PERMISSION_DENIED", e.getMessage(), null);
        }
    }

    /**
     * 将 Location 对象转换为 Map
     */
    private Map<String, Object> locationToMap(Location location) {
        Map<String, Object> map = new HashMap<>();
        map.put("latitude", location.getLatitude());
        map.put("longitude", location.getLongitude());
        map.put("accuracy", (double) location.getAccuracy());
        map.put("altitude", location.hasAltitude() ? location.getAltitude() : 0.0);
        map.put("speed", location.hasSpeed() ? location.getSpeed() : 0.0);
        map.put("heading", 0.0);
        map.put("timestamp", location.getTime());
        return map;
    }

    /**
     * 检查定位权限
     */
    private void handleCheckPermission(MethodChannel.Result result) {
        boolean hasPermission = hasLocationPermission();
        Log.d(TAG, "checkPermission: hasPermission=" + hasPermission);
        result.success(hasPermission);
    }

    /**
     * 检查是否有定位权限
     */
    private boolean hasLocationPermission() {
        return ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION)
                == PackageManager.PERMISSION_GRANTED
                || ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION)
                == PackageManager.PERMISSION_GRANTED;
    }

    /**
     * 定位服务是否启用
     */
    private void handleIsLocationServiceEnabled(MethodChannel.Result result) {
        android.location.LocationManager locationManager =
                (android.location.LocationManager) context.getSystemService(Context.LOCATION_SERVICE);
        boolean isEnabled = locationManager != null
                && (locationManager.isProviderEnabled(android.location.LocationManager.GPS_PROVIDER)
                || locationManager.isProviderEnabled(android.location.LocationManager.NETWORK_PROVIDER));
        Log.d(TAG, "isLocationServiceEnabled: " + isEnabled);
        result.success(isEnabled);
    }

    /**
     * 服务是否启用（通过系统 API）
     */
    private boolean isLocationServiceEnabled() {
        android.location.LocationManager locationManager =
                (android.location.LocationManager) context.getSystemService(Context.LOCATION_SERVICE);
        return locationManager != null
                && (locationManager.isProviderEnabled(android.location.LocationManager.GPS_PROVIDER)
                || locationManager.isProviderEnabled(android.location.LocationManager.NETWORK_PROVIDER));
    }

    /**
     * 请求权限（实际由 Flutter 端通过 permission_handler 处理）
     */
    private void handleRequestPermission(MethodChannel.Result result) {
        // 权限申请由 Flutter 端处理，这里只是检查状态
        result.success(hasLocationPermission());
    }
}
