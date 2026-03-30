package com.kenny.trace_path;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Build;
import android.os.IBinder;
import androidx.core.app.NotificationCompat;

/**
 * Android 前台服务 - 仅负责保活，不做定位
 * 
 * 定位由 Dart 层的 BackgroundLocationService (Geolocator) 处理
 * 此服务确保 App 在后台时不会被系统杀死
 * 
 * 通知栏显示静态信息，定位状态由 Dart 通过 updateNotification 更新
 */
public class LocationForegroundService extends Service {

    private static final String CHANNEL_ID = "location_service_channel";
    private static final int NOTIFICATION_ID = 888;

    private final String PREFS_NAME = "location_service_prefs";
    private SharedPreferences prefs;

    @Override
    public void onCreate() {
        super.onCreate();
        prefs = getSharedPreferences(PREFS_NAME, MODE_PRIVATE);
        createNotificationChannel();
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        android.util.Log.d("LocationForegroundService", "onStartCommand called, action=" + (intent != null ? intent.getAction() : "null"));
        
        if (intent == null) return START_STICKY;

        String action = intent.getAction();
        
        if ("com.kenny.trace_path.START".equals(action)) {
            android.util.Log.d("LocationForegroundService", "START: 显示前台通知");
            prefs.edit().putBoolean("service_running", true).apply();
            startForeground(NOTIFICATION_ID, buildNotification("TracePath 正在运行", "后台定位服务已开启"));
            
        } else if ("com.kenny.trace_path.STOP".equals(action)) {
            android.util.Log.d("LocationForegroundService", "STOP: 关闭前台通知");
            prefs.edit().putBoolean("service_running", false).apply();
            stopForeground(STOP_FOREGROUND_REMOVE);
            stopSelf();
            
        } else if ("com.kenny.trace_path.UPDATE_CONFIG".equals(action)) {
            // 配置更新，通知内容不变（由 Dart 处理实际定位）
            android.util.Log.d("LocationForegroundService", "UPDATE_CONFIG: 更新配置");
        }

        return START_STICKY;
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    /**
     * 创建通知渠道（Android 8.0+）
     */
    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel channel = new NotificationChannel(
                CHANNEL_ID, 
                "实时定位", 
                NotificationManager.IMPORTANCE_LOW);  // 使用 LOW 避免打扰用户
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

    /**
     * 构建前台通知
     */
    private Notification buildNotification(String title, String content) {
        Intent notificationIntent = new Intent(this, MainActivity.class);
        notificationIntent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        PendingIntent pendingIntent = PendingIntent.getActivity(
            this, 0, notificationIntent, PendingIntent.FLAG_IMMUTABLE);

        Intent stopIntent = new Intent(this, LocationForegroundService.class);
        stopIntent.setAction("com.kenny.trace_path.STOP");
        PendingIntent stopPendingIntent = PendingIntent.getService(
            this, 1, stopIntent, PendingIntent.FLAG_IMMUTABLE);

        return new NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(content)
            .setSmallIcon(R.drawable.ic_notification_icon)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "停止", stopPendingIntent)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build();
    }
}
