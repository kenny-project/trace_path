package com.kenny.trace_path;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.location.Location;
import android.location.LocationManager;
import android.os.Binder;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.SystemClock;

import java.util.Timer;
import java.util.TimerTask;

import androidx.core.app.NotificationCompat;

import com.google.android.gms.location.FusedLocationProviderClient;
import com.google.android.gms.location.LocationAvailability;
import com.google.android.gms.location.LocationCallback;
import com.google.android.gms.location.LocationRequest;
import com.google.android.gms.location.LocationResult;
import com.google.android.gms.location.LocationServices;
import com.google.android.gms.location.Priority;

import io.flutter.plugin.common.EventChannel;

import java.io.File;
import java.io.FileWriter;
import java.io.IOException;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * Android 前台定位服务
 */
public class LocationForegroundService extends Service {

    private static final String ALFS = "ALFS";

    public static final String ACTION_START = "com.kenny.trace_path.START";
    public static final String ACTION_STOP = "com.kenny.trace_path.STOP";
    public static final String ACTION_UPDATE_CONFIG = "com.kenny.trace_path.UPDATE_CONFIG";
    public static final String ACTION_NOTIFY_SINK_READY = "com.kenny.trace_path.NOTIFY_SINK_READY";

    private static final int DEFAULT_INTERVAL_SECONDS = 30;
    private static final boolean DEFAULT_POWER_SAVING = false;

    public static final String EVENT_CHANNEL_NAME = "com.kenny.trace_path/location_events";

    private static final AtomicBoolean _isTrackingStatic = new AtomicBoolean(false);

    public static boolean isServiceTracking() {
        return _isTrackingStatic.get();
    }

    private static final String CHANNEL_ID = "location_service_channel";
    private static final int NOTIFICATION_ID = 888;

    private Location lastLocation;
    private int intervalSeconds = DEFAULT_INTERVAL_SECONDS;
    private boolean powerSaving = DEFAULT_POWER_SAVING;

    private FusedLocationProviderClient fusedLocationClient;
    private LocationCallback locationCallback;

    private int currentPriority = Priority.PRIORITY_BALANCED_POWER_ACCURACY;
    private long lastGoodAccuracyTime = 0L;
    private long lastGpsFixTime = 0L;

    private static final float NETWORK_ACCURACY_THRESHOLD = 100f;
    private static final float GPS_ACCURACY_THRESHOLD = 50f;
    private static final int GPS_STABLE_COUNT_THRESHOLD = 3;
    private static final long GPS_NO_FIX_TIMEOUT_MS = 120_000L;
    private int _gpsStableCount = 0;

    private static final long INTERVAL_STILL = 20_000L;
    private static final long INTERVAL_WALK = 30_000L;
    private static final long INTERVAL_BIKE = 15_000L;
    private static final long INTERVAL_DRIVE = 10_000L;
    private static final float SPEED_WALK = 1.0f;
    private static final float SPEED_BIKE = 3.0f;
    private static final float SPEED_DRIVE = 8.0f;
    private long _currentIntervalMs = INTERVAL_STILL;

    private float getNetworkAccuracyThreshold() {
        return powerSaving ? 80f : NETWORK_ACCURACY_THRESHOLD;
    }

    private float getGpsAccuracyThreshold() {
        return powerSaving ? 30f : GPS_ACCURACY_THRESHOLD;
    }

    private EventChannel.EventSink eventSink;

    // GPS 健康检查定时器
    private Timer _healthTimer;
    private long _lastLocationReceivedTime = 0L;
    private Boolean _lastLocationAvailable = null; // 上一次 GPS 可用状态，仅当变化时触发重启

    private final SimpleDateFormat timeFormat = new SimpleDateFormat("HH:mm:ss", Locale.getDefault());
    private final SimpleDateFormat dateFormatFile = new SimpleDateFormat("yyyy-MM-dd", Locale.getDefault());
    private File trackFile;

    private final IBinder binder = new LocalBinder();

    class LocalBinder extends Binder {
        LocationForegroundService getService() {
            return LocationForegroundService.this;
        }
    }

    @Override
    public void onCreate() {
        super.onCreate();
        TraceLog.d(ALFS, "onCreate");
        fusedLocationClient = LocationServices.getFusedLocationProviderClient(this);
        createNotificationChannel();
        initTrackFile();
    }

    @Override
    public IBinder onBind(Intent intent) {
        return binder;
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        TraceLog.d(ALFS, "onStartCommand: action=" + (intent != null ? intent.getAction() : null));

        if (intent == null) return START_STICKY;

        String action = intent.getAction();
        switch (action) {
            case ACTION_START:
                intervalSeconds = intent.getIntExtra("interval", DEFAULT_INTERVAL_SECONDS);
                powerSaving = intent.getBooleanExtra("powerSaving", DEFAULT_POWER_SAVING);
                TraceLog.d(ALFS, "onStartCommand START: interval=" + intervalSeconds + "s, powerSaving=" + powerSaving);
                startTracking();
                break;

            case ACTION_STOP:
                stopTracking();
                break;
            case ACTION_UPDATE_CONFIG:
                intervalSeconds = intent.getIntExtra("interval", DEFAULT_INTERVAL_SECONDS);
                powerSaving = intent.getBooleanExtra("powerSaving", DEFAULT_POWER_SAVING);
                TraceLog.d(ALFS, "Config updated: interval=" + intervalSeconds + "s, powerSaving=" + powerSaving);
                if (_isTrackingStatic.get() && locationCallback != null) {
                    if (powerSaving && currentPriority == Priority.PRIORITY_HIGH_ACCURACY) {
                        switchToBalanced();
                    }
                    reRegisterLocationUpdates();
                }
                break;

            case ACTION_NOTIFY_SINK_READY:
                EventChannel.EventSink sink = eventSink != null ? eventSink : LocationPluginBinder.getEventSink();
                TraceLog.d(ALFS, "ACTION_NOTIFY_SINK_READY: isTracking=" + _isTrackingStatic.get() + ", lastLocation=" + (lastLocation != null) + ", sink=" + (sink != null));
                if (sink == null) {
                    TraceLog.e(ALFS, "onStartCommand fail, ACTION_NOTIFY_SINK_READY: sink is null, cannot send");
                } else if (_isTrackingStatic.get() && locationCallback != null) {
                    if (lastLocation != null) {
                        sendLocationToFlutter(lastLocation);
                    }
                } else {
                    TraceLog.d(ALFS, "onStartCommand debug, ACTION_NOTIFY_SINK_READY: service was killed, auto-restarting tracking");
                    startTracking();
                }
                break;
        }

        return START_STICKY;
    }

    private void startTracking() {

        if (_isTrackingStatic.get() && locationCallback != null)
        {
            TraceLog.d(ALFS, "startTracking debug, stopping first then restart with new config");
            stopTracking();
        }
        TraceLog.d(ALFS, "startTracking: started with priority=" + currentPriority);

        _isTrackingStatic.set(false);
        lastGoodAccuracyTime = 0L;
        lastGpsFixTime = 0L;
        _gpsStableCount = 0;
        currentPriority = Priority.PRIORITY_BALANCED_POWER_ACCURACY;

        _isTrackingStatic.set(true);
        startForeground(NOTIFICATION_ID, buildStartNotification());

        locationCallback = new LocationCallback() {
            @Override
            public void onLocationResult(LocationResult result) {
                TraceLog.d(ALFS, "[Callback] onLocationResult called, lastLocation=" + (result.getLastLocation() != null));
                if (result.getLastLocation() != null) {
                    handleLocationResult(result.getLastLocation());
                }
            }

            @Override
            public void onLocationAvailability(LocationAvailability availability) {
                boolean available = availability.isLocationAvailable();
                TraceLog.d(ALFS, "LocationAvailability: isLocationAvailable=" + available);
                if (!available && currentPriority == Priority.PRIORITY_HIGH_ACCURACY) {
                    lastGpsFixTime = System.currentTimeMillis();
                }
                // 仅当状态从 false → true 变化时才触发重启，避免重复消息死循环
                if (available && (_lastLocationAvailable == null || !_lastLocationAvailable)) {
                    lastGpsFixTime = 0L;
                    TraceLog.d(ALFS, "GPS restored, re-registering location updates");
                    reRegisterLocationUpdates();
                }
                _lastLocationAvailable = available;
            }
        };

        requestLocationUpdates();
        _startHealthTimer();
    }

    private void requestLocationUpdates() {
        if (!_isTrackingStatic.get()) {
            TraceLog.e(ALFS, "requestLocationUpdates fail, skipped, _isTrackingStatic=false");
            return;
        }

        if (locationCallback == null) {
            TraceLog.e(ALFS, "requestLocationUpdates fail, skipped, locationCallback=null");
            return;
        }

        long actualInterval = _currentIntervalMs;

        try {
            TraceLog.d(ALFS, "requestLocationUpdates: start with priority=" + currentPriority + ", interval=" + actualInterval + "ms");
            LocationRequest locationRequest = LocationRequest.create()
                    .setPriority(currentPriority)
                    .setInterval(actualInterval)
                    .setFastestInterval(5000); // 5 seconds

            fusedLocationClient.requestLocationUpdates(
                    locationRequest,
                    locationCallback,
                    Looper.getMainLooper()
            );
            TraceLog.d(ALFS, "requestLocationUpdates success");
        } catch (SecurityException e) {
            TraceLog.e(ALFS, "requestLocationUpdates fail, SecurityException", e);
        } catch (Exception e) {
            TraceLog.e(ALFS, "requestLocationUpdates fail, Exception", e);
        }
    }

    private void stopTracking() {
        TraceLog.d(ALFS, "stopTracking called");
        _isTrackingStatic.set(false);

        if (locationCallback != null) {
            try {
                fusedLocationClient.removeLocationUpdates(locationCallback);
            } catch (Exception e) {
                TraceLog.w(ALFS, "removeLocationUpdates failed", e);
            }
        }
        locationCallback = null;
        _cancelHealthTimer();

        stopForeground(STOP_FOREGROUND_REMOVE);
        stopSelf();
    }

    private void handleLocationResult(Location location) {
        boolean isGps = location.getProvider().equals(LocationManager.GPS_PROVIDER);
        float accuracy = location.getAccuracy();
        long now = System.currentTimeMillis();
        float speed = location.hasSpeed() ? location.getSpeed() : -1f;
        _lastLocationReceivedTime = now;

        TraceLog.d(ALFS, "handleLocationResult: pos=" + location.getLongitude() + "," + location.getLatitude() + ", isGps=" + isGps + ", accuracy=" + accuracy + ",speed=" + speed + "m/s");

        if (accuracy <= 0f || accuracy > 500f) {
            TraceLog.e(ALFS, "handleLocationResult skip accuracy=" + accuracy + "m");
            return;
        }

        if (lastLocation != null) {
            long timeDelta = location.getTime() - lastLocation.getTime();
            float distanceDelta = lastLocation.distanceTo(location);

            if (timeDelta < 2000 && distanceDelta < 10.0f) {
                TraceLog.e(ALFS, "handleLocationResult skip timeDelta=" + timeDelta + "ms, distanceDelta=" + distanceDelta + "m, accuracy=" + accuracy + "m");
                return;
            }
        }

        if (isGps) {
            if (accuracy > 200f) {
                TraceLog.e(ALFS, "handleLocationResult skip  Gps accuracy=" + accuracy + "m");
                return;
            }
        } else {
            if (accuracy > 300f) {
                TraceLog.e(ALFS, "handleLocationResult skip  Network accuracy=" + accuracy + "m");
                return;
            }
        }

        evaluateAndSwitchPriority(isGps, accuracy, now);

        TraceLog.d(ALFS, "handleLocationResult:updateNotification");
        updateNotification(location);
        TraceLog.d(ALFS, "handleLocationResult:sendLocationToFlutter");
        sendLocationToFlutter(location);

        lastLocation = location;
    }

    private void evaluateAndSwitchPriority(boolean isGps, float accuracy, long now) {
        String currentMode = (currentPriority == Priority.PRIORITY_HIGH_ACCURACY) ? "GPS" : "network";
        TraceLog.d(ALFS, "evaluateAndSwitchPriority debug, currentMode=" + currentMode + ", isGps=" + isGps + ", accuracy=" + accuracy);

        float networkThreshold = getNetworkAccuracyThreshold();
        float gpsThreshold = getGpsAccuracyThreshold();

        if (currentPriority == Priority.PRIORITY_BALANCED_POWER_ACCURACY) {
            if (accuracy > networkThreshold) {
                TraceLog.d(ALFS, "evaluateAndSwitchPriority debug, network accuracy=" + accuracy + "m > " + networkThreshold + "m, switch to Gps accuracy mode");
                switchToHighAccuracy();
            }
        } else {
            if (isGps && accuracy <= gpsThreshold) {
                _gpsStableCount++;
                TraceLog.d(ALFS, "evaluateAndSwitchPriority debug, gps accuracy=" + accuracy + "m (" + _gpsStableCount + "/" + GPS_STABLE_COUNT_THRESHOLD + ")");
                if (_gpsStableCount >= GPS_STABLE_COUNT_THRESHOLD) {
                    TraceLog.d(ALFS, "evaluateAndSwitchPriority debug, gps accuracy stable " + _gpsStableCount + " times");
                    _gpsStableCount = 0;
                    switchToBalanced();
                }
            } else if (isGps && accuracy > gpsThreshold) {
                _gpsStableCount = 0;
            }

            if (isGps && lastGpsFixTime > 0) {
                long gpsNoFixDuration = now - lastGpsFixTime;
                if (gpsNoFixDuration > GPS_NO_FIX_TIMEOUT_MS) {
                    TraceLog.d(ALFS, "evaluateAndSwitchPriority debug, gps no fix duration " + gpsNoFixDuration + "ms");
                    _gpsStableCount = 0;
                    switchToBalanced();
                }
            }
        }
    }

    private void switchToHighAccuracy() {
        if (currentPriority == Priority.PRIORITY_HIGH_ACCURACY) {
            TraceLog.d(ALFS, "[切换] switchToHighAccuracy: 已是GPS模式，跳过");
            return;
        }
        TraceLog.d(ALFS, "[切换] switchToHighAccuracy: 从" + currentPriority + "切换到GPS");
        currentPriority = Priority.PRIORITY_HIGH_ACCURACY;
        lastGoodAccuracyTime = System.currentTimeMillis();
        reRegisterLocationUpdates();
    }

    private void switchToBalanced() {
        if (currentPriority == Priority.PRIORITY_BALANCED_POWER_ACCURACY) {
            TraceLog.d(ALFS, "[切换] switchToBalanced: 已是网络模式，跳过");
            return;
        }
        TraceLog.d(ALFS, "[切换] switchToBalanced: 从" + currentPriority + "切换到网络");
        currentPriority = Priority.PRIORITY_BALANCED_POWER_ACCURACY;
        reRegisterLocationUpdates();
    }

    private void reRegisterLocationUpdates() {
        if (locationCallback != null) {
            try {
                fusedLocationClient.removeLocationUpdates(locationCallback);
            } catch (Exception e) {
                // ignore
            }
        }
        requestLocationUpdates();
    }

    /// 启动 GPS 健康检查定时器
    private void _startHealthTimer() {
        _cancelHealthTimer();
        long checkInterval = Math.max(_currentIntervalMs * 2, 30_000L); // 至少30秒
        _healthTimer = new Timer();
        _healthTimer.scheduleAtFixedRate(new TimerTask() {
            @Override
            public void run() {
                _checkLocationHealth();
            }
        }, checkInterval, checkInterval);
        TraceLog.d(ALFS, "Health timer started, interval=" + checkInterval + "ms");
    }

    /// 取消 GPS 健康检查定时器
    private void _cancelHealthTimer() {
        if (_healthTimer != null) {
            _healthTimer.cancel();
            _healthTimer = null;
        }
    }

    /// GPS 健康检查：超过 interval*3 没有新位置则强制重启定位
    private void _checkLocationHealth() {
        if (!_isTrackingStatic.get() || _lastLocationReceivedTime == 0L) {
            TraceLog.e(ALFS, "Location health check fail, not tracking or no location received, skip, isTracking="+_isTrackingStatic.get() + ", lastLocationReceivedTime="+_lastLocationReceivedTime);
            return;
        }
        long elapsed = System.currentTimeMillis() - _lastLocationReceivedTime;
        long threshold = _currentIntervalMs * 3;
        if (elapsed > threshold) {
            TraceLog.w(ALFS, "Location health check: no location for " + elapsed + "ms, force restart (threshold="
                    + threshold + "ms)");
            reRegisterLocationUpdates();
            _lastLocationReceivedTime = System.currentTimeMillis(); // 重置避免重复触发
        }
        else {
            TraceLog.d(ALFS, "Location health check: location received, skip, elapsed="+elapsed+"ms, threshold="+threshold+"ms");
        }
    }

    private Location requestSingleLocation() {
        TraceLog.d(ALFS, "requestSingleLocation: start");

        Location location = requestSingleLocationWithPriority(
                powerSaving ? Priority.PRIORITY_BALANCED_POWER_ACCURACY : Priority.PRIORITY_HIGH_ACCURACY,
                45
        );

        if (location != null) {
            TraceLog.d(ALFS, "requestSingleLocation: GPS success lat=" + location.getLatitude() + ", lng=" + location.getLongitude() + ", accuracy=" + location.getAccuracy() + "m");
            return location;
        }

        TraceLog.w(ALFS, "requestSingleLocation: GPS timeout, falling back to network positioning");
        Location networkLocation = requestSingleLocationWithPriority(
                Priority.PRIORITY_BALANCED_POWER_ACCURACY,
                30
        );

        if (networkLocation != null) {
            TraceLog.d(ALFS, "requestSingleLocation: network success lat=" + networkLocation.getLatitude() + ", lng=" + networkLocation.getLongitude() + ", accuracy=" + networkLocation.getAccuracy() + "m");
        } else {
            TraceLog.w(ALFS, "requestSingleLocation: all methods failed");
        }

        return networkLocation;
    }

    private Location requestSingleLocationWithPriority(int priority, long timeoutSeconds) {
        try {
            LocationRequest.Builder builder = new LocationRequest.Builder(priority, 0)
                    .setMaxUpdates(1)
                    .setWaitForAccurateLocation(false);

            final Location[] resultLocation = new Location[1];
            CountDownLatch latch = new CountDownLatch(1);

            LocationCallback singleCallback = new LocationCallback() {
                @Override
                public void onLocationResult(LocationResult result) {
                    resultLocation[0] = result.getLastLocation();
                    try {
                        fusedLocationClient.removeLocationUpdates(this);
                    } catch (Exception e) {
                        // ignore
                    }
                    latch.countDown();
                }
            };

            fusedLocationClient.requestLocationUpdates(
                    builder.build(),
                    singleCallback,
                    Looper.getMainLooper()
            );

            boolean waited = latch.await(timeoutSeconds, TimeUnit.SECONDS);
            if (!waited) {
                TraceLog.w(ALFS, "requestSingleLocationWithPriority(" + priority + "): timeout after " + timeoutSeconds + "s");
                try {
                    fusedLocationClient.removeLocationUpdates(singleCallback);
                } catch (Exception e) {
                    // ignore
                }
            }

            return resultLocation[0];

        } catch (SecurityException e) {
            TraceLog.e(ALFS, "SecurityException in requestSingleLocationWithPriority", e);
            return null;
        } catch (Exception e) {
            TraceLog.e(ALFS, "Exception in requestSingleLocationWithPriority", e);
            return null;
        }
    }

    private void sendLocationToFlutter(Location location) {
        EventChannel.EventSink sink = eventSink != null ? eventSink : LocationPluginBinder.getEventSink();
        if (sink == null) {
            TraceLog.e(ALFS, "sendLocationToFlutter fail, sink is null, event dropped!");
            return;
        }
        TraceLog.d(ALFS, "sendLocationToFlutter debug, sink available, sending pos=" + location.getLatitude() + "," + location.getLongitude());

        java.util.Map<String, Object> locationMap = new java.util.HashMap<>();
        locationMap.put("latitude", location.getLatitude());
        locationMap.put("longitude", location.getLongitude());
        locationMap.put("accuracy", (double) location.getAccuracy());
        locationMap.put("altitude", location.hasAltitude() ? location.getAltitude() : 0.0);
        locationMap.put("speed", location.hasSpeed() ? (double) location.getSpeed() : 0.0);
        locationMap.put("heading", 0.0);
        locationMap.put("timestamp", (double) location.getTime());

        try {
            new Handler(Looper.getMainLooper()).post(() -> {
                sink.success(locationMap);
                TraceLog.d(ALFS, "Location sent to Flutter: lat=" + location.getLatitude() + ", lng=" + location.getLongitude());
            });
        } catch (Exception e) {
            TraceLog.e(ALFS, "sendLocationToFlutter Failed, error sending location to Flutter: ", e);
        }

        saveLocationToFile(location);
    }

    private void initTrackFile() {
        try {
            File trackDir = new File(getFilesDir(), "location_tracks");
            if (!trackDir.exists()) trackDir.mkdirs();
            String dateStr = dateFormatFile.format(new Date());
            trackFile = new File(trackDir, "track_" + dateStr + ".csv");

            if (!trackFile.exists()) {
                FileWriter writer = new FileWriter(trackFile, true);
                writer.append("timestamp,latitude,longitude,accuracy,altitude,speed\n");
                writer.flush();
                writer.close();
            }
            TraceLog.d(ALFS, "initTrackFile debug, track file initialized: " + trackFile.getAbsolutePath());
        } catch (Exception e) {
            TraceLog.e(ALFS, "initTrackFile Failed, init track file", e);
        }
    }

    private void saveLocationToFile(Location location) {
        try {
            if (trackFile == null) {
                initTrackFile();
            }

            long timestamp = (long) location.getTime();
            double latitude = location.getLatitude();
            double longitude = location.getLongitude();
            double accuracy = location.getAccuracy();
            double altitude = location.hasAltitude() ? location.getAltitude() : 0.0;
            double speed = location.hasSpeed() ? location.getSpeed() : 0.0;

            String line = timestamp + "," + latitude + "," + longitude + "," + accuracy + "," + altitude + "," + speed + "\n";

            FileWriter writer = new FileWriter(trackFile, true);
            writer.append(line);
            writer.flush();
            writer.close();
            TraceLog.d(ALFS, "saveLocationToFile debug, pos=" + latitude + "," + longitude);
        } catch (IOException e) {
            TraceLog.e(ALFS, "saveLocationToFile Failed to save location to file", e);
        } catch (Exception e) {
            TraceLog.e(ALFS, "saveLocationToFile Failed to save location to file", e);
        }
    }

    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel channel = new NotificationChannel(
                    CHANNEL_ID,
                    "实时定位",
                    NotificationManager.IMPORTANCE_LOW
            );
            channel.setDescription("TracePath 后台定位服务");
            channel.setShowBadge(false);
            channel.enableLights(false);
            channel.enableVibration(false);

            NotificationManager manager = getSystemService(NotificationManager.class);
            if (manager != null) {
                manager.createNotificationChannel(channel);
            }
        }
    }

    private Notification buildStartNotification() {
        String title = "TracePath 正在启动";
        String content = "定位服务初始化中...";

        TraceLog.d(ALFS, "buildStartNotification: title=" + title + ", content=" + content);

        Intent notificationIntent = new Intent(this, MainActivity.class);
        notificationIntent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        PendingIntent pendingIntent = PendingIntent.getActivity(
                this, 0, notificationIntent, PendingIntent.FLAG_IMMUTABLE
        );

        Intent stopIntent = new Intent(this, LocationForegroundService.class);
        stopIntent.setAction(ACTION_STOP);
        PendingIntent stopPendingIntent = PendingIntent.getService(
                this, 1, stopIntent, PendingIntent.FLAG_IMMUTABLE
        );

        Notification notification = new NotificationCompat.Builder(this, CHANNEL_ID)
                .setContentTitle(title)
                .setContentText(content)
                .setSmallIcon(R.drawable.ic_notification_icon)
                .setContentIntent(pendingIntent)
                .setOngoing(true)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setCategory(NotificationCompat.CATEGORY_SERVICE)
                .setStyle(new NotificationCompat.BigTextStyle().bigText(content))
                .addAction(android.R.drawable.ic_menu_close_clear_cancel, "停止", stopPendingIntent)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
                .build();

        TraceLog.d(ALFS, "buildStartNotification debug, hashCode=" + notification.hashCode());
        return notification;
    }

    private Notification buildNotification(Location loc) {
        String mode = powerSaving ? "省电" : "常态";
        String source = currentPriority == Priority.PRIORITY_HIGH_ACCURACY ? "GPS" : "网络";

        if (loc == null) {
            TraceLog.w(ALFS, "buildNotification: loc is null, return null");
            return null;
        }

        String locationText = String.format(Locale.getDefault(), "位置: %.6f, %.6f", loc.getLatitude(), loc.getLongitude());
        String accuracyText = String.format(Locale.getDefault(), "精度: %.0f米", loc.getAccuracy());
        String updateTime = "更新: " + timeFormat.format(new Date(loc.getTime()));

        String title = "TracePath [" + source + "] 正在运行";
        String content = mode + " | " + locationText + " | " + accuracyText + " | " + updateTime;

        Intent notificationIntent = new Intent(this, MainActivity.class);
        notificationIntent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        PendingIntent pendingIntent = PendingIntent.getActivity(
                this, 0, notificationIntent, PendingIntent.FLAG_IMMUTABLE
        );

        Intent stopIntent = new Intent(this, LocationForegroundService.class);
        stopIntent.setAction(ACTION_STOP);
        PendingIntent stopPendingIntent = PendingIntent.getService(
                this, 1, stopIntent, PendingIntent.FLAG_IMMUTABLE
        );

        Notification notification = new NotificationCompat.Builder(this, CHANNEL_ID)
                .setContentTitle(title)
                .setContentText(content)
                .setSmallIcon(R.drawable.ic_notification_icon)
                .setContentIntent(pendingIntent)
                .setOngoing(true)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setCategory(NotificationCompat.CATEGORY_SERVICE)
                .setStyle(new NotificationCompat.BigTextStyle().bigText(content))
                .addAction(android.R.drawable.ic_menu_close_clear_cancel, "停止", stopPendingIntent)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
                .build();

        TraceLog.d(ALFS, "buildNotification END, hashCode=" + notification.hashCode() + ", updateTime=" + updateTime);
        return notification;
    }

    private void updateNotification(Location loc)
    {
        if (loc == null)
        {
            TraceLog.w(ALFS, "updateNotification: loc is null");
            return;
        }

        NotificationManager manager = getSystemService(NotificationManager.class);
        if (manager == null) {
            TraceLog.w(ALFS, "updateNotification: NotificationManager is null!");
            return;
        }
        Notification notification = buildNotification(loc);
        if( notification == null)
        {
            TraceLog.w(ALFS, "updateNotification: notification is null!");
            return;
        }
        manager.notify(NOTIFICATION_ID, notification);
        TraceLog.d(ALFS, "updateNotification pos=" + loc.getLatitude() + "," + loc.getLongitude());
    }

    @Override
    public void onDestroy() {
        TraceLog.d(ALFS, "onDestroy");
        _isTrackingStatic.set(false);
        if (locationCallback != null) {
            try {
                fusedLocationClient.removeLocationUpdates(locationCallback);
            } catch (Exception e) {
                // ignore
            }
        }
        locationCallback = null;
        _cancelHealthTimer();
        super.onDestroy();
    }

    public void setEventSink(EventChannel.EventSink sink) {
        this.eventSink = sink;
    }

    public boolean isServiceRunning() {
        return _isTrackingStatic.get();
    }
}
