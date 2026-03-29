package com.example.trace_path;

import android.Manifest;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.location.Location;
import android.location.LocationListener;
import android.location.LocationManager;
import android.os.Build;
import android.os.IBinder;
import androidx.core.app.ActivityCompat;
import androidx.core.app.NotificationCompat;
import java.io.BufferedWriter;
import java.io.File;
import java.io.FileWriter;
import java.io.IOException;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;
import java.util.Timer;
import java.util.TimerTask;

public class LocationForegroundService extends Service {

    private static final String CHANNEL_ID = "location_service_channel";
    private static final int NOTIFICATION_ID = 888;
    private static final long MIN_INTERVAL_DEFAULT = 10000; // 10秒
    private static final long POWER_SAVING_INTERVAL = 60000; // 1分钟
    private static final double MIN_DISTANCE = 10.0; // 10米

    private LocationManager locationManager;
    private Timer updateTimer;
    private boolean isTracking = false;
    private boolean powerSaving = false;

    private double lastLat = 0;
    private double lastLng = 0;
    private long lastTime = 0;

    private final String PREFS_NAME = "location_service_prefs";
    private SharedPreferences prefs;

    @Override
    public void onCreate() {
        super.onCreate();
        locationManager = (LocationManager) getSystemService(Context.LOCATION_SERVICE);
        prefs = getSharedPreferences(PREFS_NAME, MODE_PRIVATE);
        createNotificationChannel();
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        android.util.Log.d("LocationForegroundService", "onStartCommand called, intent=" + intent + ", action=" + (intent != null ? intent.getAction() : "null"));
        if (intent == null) return START_STICKY;

        String action = intent.getAction();
        if ("com.example.trace_path.START".equals(action)) {
            android.util.Log.d("LocationForegroundService", "START action received, calling startForeground");
            isTracking = true;
            powerSaving = intent.getBooleanExtra("power_saving", false);
            long interval = intent.getLongExtra("interval", MIN_INTERVAL_DEFAULT);
            android.util.Log.d("LocationForegroundService", "interval=" + interval + ", powerSaving=" + powerSaving);
            try {
                startForeground(NOTIFICATION_ID, buildNotification("实时定位服务运行中", "等待定位..."));
                android.util.Log.d("LocationForegroundService", "startForeground 成功!");
            } catch (Exception e) {
                android.util.Log.e("LocationForegroundService", "startForeground 失败: " + e.getMessage());
            }
            startLocationUpdates(interval);
        } else if ("com.example.trace_path.STOP".equals(action)) {
            isTracking = false;
            stopLocationUpdates();
            stopForeground(STOP_FOREGROUND_REMOVE);
            stopSelf();
        } else if ("com.example.trace_path.UPDATE_CONFIG".equals(action)) {
            powerSaving = intent.getBooleanExtra("power_saving", false);
            long interval = intent.getLongExtra("interval", MIN_INTERVAL_DEFAULT);
            if (isTracking) {
                stopLocationUpdates();
                startLocationUpdates(interval);
            }
        }

        return START_STICKY;
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel channel = new NotificationChannel(
                CHANNEL_ID, "实时定位", NotificationManager.IMPORTANCE_DEFAULT);
            channel.setDescription("TracePath 实时定位服务");
            channel.setShowBadge(false);
            NotificationManager manager = getSystemService(NotificationManager.class);
            if (manager != null) manager.createNotificationChannel(channel);
        }
    }

    private Notification buildNotification(String title, String content) {
        Intent notificationIntent = new Intent(this, MainActivity.class);
        notificationIntent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        PendingIntent pendingIntent = PendingIntent.getActivity(
            this, 0, notificationIntent, PendingIntent.FLAG_IMMUTABLE);

        Intent stopIntent = new Intent(this, LocationForegroundService.class);
        stopIntent.setAction("com.example.trace_path.STOP");
        PendingIntent stopPendingIntent = PendingIntent.getService(
            this, 1, stopIntent, PendingIntent.FLAG_IMMUTABLE);

        return new NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(content)
            .setSmallIcon(R.drawable.ic_notification_icon)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "停止", stopPendingIntent)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build();
    }

    private void updateNotification(double speed, double accuracy) {
        String speedText = speed < 0.5 ? "静止" : String.format(Locale.US, "%.1fm/s", speed);
        String content = String.format(Locale.US, "速度: %s | 精度: %.0fm", speedText, accuracy);
        NotificationManager manager = getSystemService(NotificationManager.class);
        if (manager != null) {
            manager.notify(NOTIFICATION_ID, buildNotification("TracePath 正在定位", content));
        }
    }

    private void startLocationUpdates(long intervalMs) {
        if (ActivityCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED &&
            ActivityCompat.checkSelfPermission(this, Manifest.permission.ACCESS_COARSE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            return;
        }

        long minTime = powerSaving ? POWER_SAVING_INTERVAL : intervalMs;
        float minDistance = (float) MIN_DISTANCE;

        locationManager.requestLocationUpdates(
            LocationManager.GPS_PROVIDER,
            minTime,
            minDistance,
            locationListener
        );
    }

    private void stopLocationUpdates() {
        if (locationManager != null) {
            locationManager.removeUpdates(locationListener);
        }
        if (updateTimer != null) {
            updateTimer.cancel();
            updateTimer = null;
        }
    }

    private final LocationListener locationListener = new LocationListener() {
        @Override
        public void onLocationChanged(Location location) {
            processLocation(location);
        }
        @Override
        public void onProviderEnabled(String provider) {}
        @Override
        public void onProviderDisabled(String provider) {}
    };

    private void processLocation(Location location) {
        double lat = location.getLatitude();
        double lng = location.getLongitude();
        double altitude = location.getAltitude();
        double speed = location.getSpeed();
        double accuracy = location.getAccuracy();
        long time = location.getTime();

        // 智能去重规则：
        // 1. 距离<10米且时间<60秒 → 不保存
        // 2. 时间>=1小时 → 即使距离近也要保存
        // 3. 其他情况 → 保存
        if (lastLat != 0 && lastLng != 0) {
            float[] results = new float[1];
            Location.distanceBetween(lastLat, lastLng, lat, lng, results);
            double distance = results[0];
            long timeDiff = time - lastTime;
            
            // 距离<10米且时间<60秒 → 跳过
            // 时间>=1小时(3600000ms) → 强制保存
            if (distance < MIN_DISTANCE && timeDiff < 60000) {
                // 跳过，不保存
                android.util.Log.i("LocationService", "跳过: 距离=" + distance + "米, 时间差=" + timeDiff + "ms");
            } else {
                // 保存（可能是距离远或时间够了1小时）
                saveToCsv(lat, lng, altitude, speed, accuracy, time);
            }
        } else {
            // 首次定位，保存
            saveToCsv(lat, lng, altitude, speed, accuracy, time);
        }

        lastLat = lat;
        lastLng = lng;
        lastTime = time;

        updateNotification(speed, accuracy);
    }

    private void saveToCsv(double lat, double lng, double altitude, double speed, double accuracy, long time) {
        try {
            // 使用新的目录结构: {phoneNumber}/{year}/{month}/{day}.csv
            // 默认使用18511698488，后续可以通过方法设置
            String phoneNumber = getPhoneNumber();
            SimpleDateFormat yearFormat = new SimpleDateFormat("yyyy", Locale.US);
            SimpleDateFormat monthFormat = new SimpleDateFormat("MM", Locale.US);
            SimpleDateFormat dayFormat = new SimpleDateFormat("dd", Locale.US);
            SimpleDateFormat tsFormat = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS", Locale.US);

            String year = yearFormat.format(new Date(time));
            String month = monthFormat.format(new Date(time));
            String day = dayFormat.format(new Date(time));
            String timestamp = tsFormat.format(new Date(time));

            File dir = new File(getFilesDir(), "location_tracks/" + phoneNumber + "/" + year + "/" + month);
            if (!dir.exists()) dir.mkdirs();
            File file = new File(dir, day + ".csv");

            // 检查是否需要写入表头
            boolean needsHeader = !file.exists() || file.length() == 0;
            
            FileWriter fw = new FileWriter(file, true);
            BufferedWriter bw = new BufferedWriter(fw);
            
            if (needsHeader) {
                bw.write("timestamp,latitude,longitude,altitude,speed,accuracy\n");
            }
            bw.write(String.format(Locale.US, "%s,%.6f,%.6f,%.2f,%.2f,%.1f\n",
                timestamp, lat, lng, altitude, speed, accuracy));
            bw.close();
        } catch (IOException e) {
            android.util.Log.e("LocationService", "CSV写失败: " + e.getMessage());
        }
    }

    // 获取当前使用的手机号（后续可以从SharedPreferences或方法获取）
    private String getPhoneNumber() {
        // 默认使用主用户手机号
        return "18511698488";
    }
}
