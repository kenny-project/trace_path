package com.kenny.trace_path;

import android.content.Context;
import android.content.Intent;
import android.location.Geocoder;
import android.os.Build;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

import java.io.IOException;
import java.util.List;
import java.util.Locale;

/**
 * 定位服务 MethodChannel 处理器
 */
public class LocationPlugin {

    private static final String TAG = "LocationPlugin";

    public static final String METHOD_CHANNEL_NAME = "com.kenny.trace_path/location_service";
    public static final String EVENT_CHANNEL_NAME = "com.kenny.trace_path/location_events";
    public static final String GEOCODER_CHANNEL_NAME = "com.kenny.trace_path/geocoder_service";
    private static final int DEFAULT_INTERVAL = 30;
    private static final boolean DEFAULT_POWER_SAVING = false;

    private EventChannel eventChannel;
    private MethodChannel methodChannel;
    private MethodChannel geocoderChannel;
    private EventChannel.EventSink eventSink;
    private Intent serviceIntent;
    private EventChannel.StreamHandler streamHandler;
    private final Context context;
    private Geocoder geocoder;

    public LocationPlugin(Context context) {
        this.context = context;
        this.geocoder = new Geocoder(context, Locale.getDefault());
    }

    public void registerWith(FlutterEngine flutterEngine) {
        streamHandler = new EventChannel.StreamHandler() {
            @Override
            public void onListen(Object arguments, EventChannel.EventSink events) {
                TraceLog.d(TAG, "EventChannel onListen: sink=" + (events != null));
                eventSink = events;
                LocationPluginBinder.setEventSink(events);
            }

            @Override
            public void onCancel(Object arguments) {
                TraceLog.d(TAG, "EventChannel onCancel: eventSink will be null");
                eventSink = null;
                LocationPluginBinder.setEventSink(null);
            }
        };

        eventChannel = new EventChannel(
                flutterEngine.getDartExecutor().getBinaryMessenger(),
                EVENT_CHANNEL_NAME
        );
        eventChannel.setStreamHandler(streamHandler);

        methodChannel = new MethodChannel(
                flutterEngine.getDartExecutor().getBinaryMessenger(),
                METHOD_CHANNEL_NAME
        );
        methodChannel.setMethodCallHandler((call, result) -> handleMethodCall(call, result));

        // Geocoder MethodChannel for native Android reverse geocoding
        geocoderChannel = new MethodChannel(
                flutterEngine.getDartExecutor().getBinaryMessenger(),
                GEOCODER_CHANNEL_NAME
        );
        geocoderChannel.setMethodCallHandler((call, result) -> handleGeocoderMethodCall(call, result));

        // Initialize TraceLog to forward Android logs to Flutter
        TraceLog.init(flutterEngine.getDartExecutor().getBinaryMessenger());

        notifyServiceEventSinkReady();
        TraceLog.d(TAG, "LocationPlugin registered");
    }

    private void notifyServiceEventSinkReady() {
        try {
            Intent intent = new Intent(context, LocationForegroundService.class);
            intent.setAction(LocationForegroundService.ACTION_NOTIFY_SINK_READY);
            context.startService(intent);
            TraceLog.d(TAG, "notifyServiceEventSinkReady sent");
        } catch (Exception e) {
            TraceLog.e(TAG, "notifyServiceEventSinkReady failed", e);
        }
    }

    public EventChannel.StreamHandler getEventStreamHandler() {
        return streamHandler;
    }

    private void handleMethodCall(MethodCall call, MethodChannel.Result result) {
        TraceLog.d(TAG, "handleMethodCall: method=" + call.method + ", args=" + call.arguments);

        switch (call.method) {
            case "startLocationService":
            case "start":
                Integer interval = call.argument("interval");
                Boolean powerSaving = call.argument("powerSaving");
                startLocationService(interval != null ? interval : DEFAULT_INTERVAL,
                        powerSaving != null ? powerSaving : DEFAULT_POWER_SAVING, result);
                break;

            case "stopLocationService":
            case "stop":
                stopLocationService(result);
                break;

            case "updateLocationConfig":
            case "updateConfig":
                Integer interval2 = call.argument("interval");
                Boolean powerSaving2 = call.argument("powerSaving");
                updateLocationConfig(interval2 != null ? interval2 : DEFAULT_INTERVAL,
                        powerSaving2 != null ? powerSaving2 : DEFAULT_POWER_SAVING, result);
                break;

            case "isLocationServiceRunning":
            case "isRunning":
                result.success(isLocationServiceRunning());
                break;

            default:
                result.notImplemented();
                break;
        }
    }

    private void handleGeocoderMethodCall(MethodCall call, MethodChannel.Result result) {
        TraceLog.d(TAG, "handleGeocoderMethodCall: method=" + call.method + ", args=" + call.arguments);

        switch (call.method) {
            case "getAddressFromLatLng":
                Double lat = call.argument("latitude");
                Double lng = call.argument("longitude");
                if (lat == null || lng == null) {
                    result.error("INVALID_ARGS", "latitude and longitude are required", null);
                    return;
                }
                getAddressFromLatLng(lat, lng, result);
                break;

            default:
                result.notImplemented();
                break;
        }
    }

    private void getAddressFromLatLng(double latitude, double longitude, MethodChannel.Result result) {
        TraceLog.d(TAG, "getAddressFromLatLng: lat=" + latitude + ", lng=" + longitude);

        if (!Geocoder.isPresent()) {
            TraceLog.w(TAG, "Geocoder is not present on this device");
            result.success(null);
            return;
        }

        try {
            List<android.location.Address> addresses = geocoder.getFromLocation(latitude, longitude, 1);
            if (addresses != null && !addresses.isEmpty()) {
                android.location.Address address = addresses.get(0);
                StringBuilder sb = new StringBuilder();

                // Build formatted address from address lines
                for (int i = 0; i <= address.getMaxAddressLineIndex(); i++) {
                    if (i > 0) sb.append("\n");
                    sb.append(address.getAddressLine(i));
                }

                String formattedAddress = sb.toString();
                TraceLog.d(TAG, "Geocoder result: " + formattedAddress);
                result.success(formattedAddress);
            } else {
                TraceLog.d(TAG, "Geocoder returned no addresses");
                result.success(null);
            }
        } catch (IOException e) {
            TraceLog.e(TAG, "Geocoder.getFromLocation failed", e);
            result.error("GEOCODER_ERROR", e.getMessage(), null);
        } catch (Exception e) {
            TraceLog.e(TAG, "getAddressFromLatLng unexpected error", e);
            result.error("UNKNOWN_ERROR", e.getMessage(), null);
        }
    }

    public void startLocationService(int interval, boolean powerSaving, MethodChannel.Result result) {
        TraceLog.d(TAG, "startLocationService: interval=" + interval + "s, powerSaving=" + powerSaving);

        try {
            serviceIntent = new Intent(context, LocationForegroundService.class);
            serviceIntent.setAction(LocationForegroundService.ACTION_START);
            serviceIntent.putExtra("interval", interval);
            serviceIntent.putExtra("powerSaving", powerSaving);

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(serviceIntent);
            } else {
                context.startService(serviceIntent);
            }

            result.success(true);
        } catch (Exception e) {
            TraceLog.e(TAG, "startLocationService failed", e);
            result.error("START_FAILED", e.getMessage(), null);
        }
    }

    public void stopLocationService(MethodChannel.Result result) {
        TraceLog.d(TAG, "stopLocationService");

        try {
            serviceIntent = new Intent(context, LocationForegroundService.class);
            serviceIntent.setAction(LocationForegroundService.ACTION_STOP);
            context.startService(serviceIntent);
            result.success(true);
        } catch (Exception e) {
            TraceLog.e(TAG, "stopLocationService failed", e);
            result.error("STOP_FAILED", e.getMessage(), null);
        }
    }

    public void updateLocationConfig(int interval, boolean powerSaving, MethodChannel.Result result) {
        TraceLog.d(TAG, "updateLocationConfig: interval=" + interval + "s, powerSaving=" + powerSaving);

        try {
            serviceIntent = new Intent(context, LocationForegroundService.class);
            serviceIntent.setAction(LocationForegroundService.ACTION_UPDATE_CONFIG);
            serviceIntent.putExtra("interval", interval);
            serviceIntent.putExtra("powerSaving", powerSaving);
            context.startService(serviceIntent);
            result.success(true);
        } catch (Exception e) {
            TraceLog.e(TAG, "updateLocationConfig failed", e);
            result.error("UPDATE_CONFIG_FAILED", e.getMessage(), null);
        }
    }

    public boolean isLocationServiceRunning() {
        boolean tracking = LocationForegroundService.isServiceTracking();
        TraceLog.d(TAG, "isLocationServiceRunning: tracking=" + tracking);
        return tracking;
    }

    public void dispose() {
        if (eventChannel != null) {
            eventChannel.setStreamHandler(null);
        }
        if (methodChannel != null) {
            methodChannel.setMethodCallHandler(null);
        }
        eventSink = null;
        TraceLog.d(TAG, "LocationPlugin disposed");
    }
}
