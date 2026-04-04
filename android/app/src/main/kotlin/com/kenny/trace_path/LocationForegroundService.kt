package com.kenny.trace_path

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.location.Location
import android.os.Binder
import android.os.Build
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat
import com.google.android.gms.location.*
import io.flutter.plugin.common.EventChannel
import java.text.SimpleDateFormat
import java.util.*
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Android 前台定位服务
 * 
 * 内置定位循环，通过 EventChannel 推送位置给 Flutter
 * 通知栏由服务自己管理，动态更新
 */
class LocationForegroundService : Service() {

    companion object {
        private const val TAG = "LocationForegroundService"
        
        // 状态
        const val ACTION_START = "com.kenny.trace_path.START"
        const val ACTION_STOP = "com.kenny.trace_path.STOP"
        const val ACTION_UPDATE_CONFIG = "com.kenny.trace_path.UPDATE_CONFIG"
        
        // 默认值
        const val DEFAULT_INTERVAL_SECONDS = 30
        const val DEFAULT_POWER_SAVING = false
        
        // EventChannel
        const val EVENT_CHANNEL_NAME = "com.kenny.trace_path/location_events"
    }

    // 通知渠道
    private val CHANNEL_ID = "location_service_channel"
    private val NOTIFICATION_ID = 888

    // 状态
    private var isTracking = AtomicBoolean(false)
    private var lastLocation: Location? = null
    private var intervalSeconds = DEFAULT_INTERVAL_SECONDS
    private var powerSaving = DEFAULT_POWER_SAVING
    
    // FusedLocationProvider
    private lateinit var fusedLocationClient: FusedLocationProviderClient
    private var locationCallback: LocationCallback? = null
    
    // EventChannel
    private var eventSink: EventChannel.EventSink? = null
    
    // 定位线程
    private var locationThread: Thread? = null
    
    // 日期格式
    private val timeFormat = SimpleDateFormat("HH:mm:ss", Locale.getDefault())

    private val binder = LocalBinder()

    inner class LocalBinder : Binder() {
        fun getService(): LocationForegroundService = this@LocationForegroundService
    }

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "onCreate")
        fusedLocationClient = LocationServices.getFusedLocationProviderClient(this)
        createNotificationChannel()
    }

    override fun onBind(intent: Intent?): IBinder {
        return binder
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "onStartCommand: action=${intent?.action}")
        
        if (intent == null) return START_STICKY

        when (intent.action) {
            ACTION_START -> {
                intervalSeconds = intent.getIntExtra("interval", DEFAULT_INTERVAL_SECONDS)
                powerSaving = intent.getBooleanExtra("powerSaving", DEFAULT_POWER_SAVING)
                startTracking()
            }
            ACTION_STOP -> {
                stopTracking()
            }
            ACTION_UPDATE_CONFIG -> {
                intervalSeconds = intent.getIntExtra("interval", DEFAULT_INTERVAL_SECONDS)
                powerSaving = intent.getBooleanExtra("powerSaving", DEFAULT_POWER_SAVING)
                Log.d(TAG, "Config updated: interval=${intervalSeconds}s, powerSaving=$powerSaving")
            }
        }

        return START_STICKY
    }

    /**
     * 开始定位追踪
     */
    private fun startTracking() {
        if (isTracking.get()) {
            Log.w(TAG, "Already tracking, ignore")
            return
        }
        
        isTracking.set(true)
        startForeground(NOTIFICATION_ID, buildNotification())
        
        // 在独立线程中运行定位循环
        locationThread = Thread {
            Log.d(TAG, "Location loop started")
            while (isTracking.get()) {
                val location = requestSingleLocation()
                if (location != null) {
                    lastLocation = location
                    // 发送位置到 Flutter
                    sendLocationToFlutter(location)
                    // 更新通知栏
                    updateNotification()
                }
                
                if (isTracking.get()) {
                    // 计算实际间隔（省电模式最小60秒）
                    val actualInterval = if (powerSaving) {
                        maxOf(intervalSeconds, 60)
                    } else {
                        intervalSeconds
                    }
                    
                    // 等待下次定位
                    try {
                        Thread.sleep(actualInterval * 1000L)
                    } catch (e: InterruptedException) {
                        Log.d(TAG, "Location loop interrupted")
                        break
                    }
                }
            }
            Log.d(TAG, "Location loop exited")
        }
        locationThread?.start()
    }

    /**
     * 停止定位追踪
     */
    private fun stopTracking() {
        Log.d(TAG, "stopTracking called")
        isTracking.set(false)
        
        locationThread?.interrupt()
        locationThread = null
        
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    /**
     * 请求单次定位
     */
    private fun requestSingleLocation(): Location? {
        Log.d(TAG, "requestSingleLocation: start")
        
        try {
            val builder = LocationRequest.Builder(
                if (powerSaving) Priority.PRIORITY_BALANCED_POWER_ACCURACY
                else Priority.PRIORITY_HIGH_ACCURACY,
                0 // 立即获取
            ).setMaxUpdates(1)
            
            val callback = object : LocationCallback() {
                override fun onLocationResult(result: LocationResult) {
                    Log.d(TAG, "onLocationResult: ${result.lastLocation}")
                }
            }
            
            // 创建一个 CompletableFuture 来等待结果
            var resultLocation: Location? = null
            val latch = java.util.concurrent.CountDownLatch(1)
            
            val singleCallback = object : LocationCallback() {
                override fun onLocationResult(result: LocationResult) {
                    resultLocation = result.lastLocation
                    fusedLocationClient.removeLocationUpdates(this)
                    latch.countDown()
                }
            }
            
            fusedLocationClient.requestLocationUpdates(
                builder.build(),
                singleCallback,
                Looper.getMainLooper()
            )
            
            // 等待最多45秒
            latch.await(45, java.util.concurrent.TimeUnit.SECONDS)
            
            if (resultLocation != null) {
                Log.d(TAG, "requestSingleLocation: success lat=${resultLocation!!.latitude}, lng=${resultLocation!!.longitude}")
            } else {
                Log.w(TAG, "requestSingleLocation: timeout or failed")
            }
            
            return resultLocation
            
        } catch (e: SecurityException) {
            Log.e(TAG, "SecurityException in requestSingleLocation", e)
            return null
        } catch (e: Exception) {
            Log.e(TAG, "Exception in requestSingleLocation", e)
            return null
        }
    }

    /**
     * 发送位置到 Flutter
     */
    private fun sendLocationToFlutter(location: Location) {
        // 优先使用直接设置的 eventSink，否则使用 LocationPluginBinder
        val sink = eventSink ?: LocationPluginBinder.getEventSink()
        sink ?: return
        
        val locationMap = HashMap<String, Any>()
        locationMap["latitude"] = location.latitude
        locationMap["longitude"] = location.longitude
        locationMap["accuracy"] = location.accuracy.toDouble()
        locationMap["altitude"] = if (location.hasAltitude()) location.altitude else 0.0
        locationMap["speed"] = if (location.hasSpeed()) location.speed.toDouble() else 0.0
        locationMap["heading"] = 0.0
        locationMap["timestamp"] = location.time
        
        try {
            runOnMainThread {
                sink.success(locationMap)
                Log.d(TAG, "Location sent to Flutter: lat=${location.latitude}, lng=${location.longitude}")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error sending location to Flutter", e)
        }
    }

    /**
     * 在主线程执行
     */
    private fun runOnMainThread(runnable: Runnable) {
        android.os.Handler(Looper.getMainLooper()).post(runnable)
    }

    /**
     * 创建通知渠道
     */
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID, 
                "实时定位", 
                NotificationManager.IMPORTANCE_LOW
            )
            channel.description = "TracePath 后台定位服务"
            channel.setShowBadge(false)
            channel.enableLights(false)
            channel.enableVibration(false)
            
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(channel)
        }
    }

    /**
     * 构建通知
     */
    private fun buildNotification(): Notification {
        val status = if (isTracking.get()) "运行中" else "已停止"
        val mode = if (powerSaving) "省电模式 ${maxOf(intervalSeconds, 60)}秒" else "精准模式 ${intervalSeconds}秒"
        val locationText = lastLocation?.let {
            String.format("位置: %.6f, %.6f", it.latitude, it.longitude)
        } ?: "位置: 获取中..."
        val accuracyText = lastLocation?.let {
            String.format("精度: %.0f米", it.accuracy)
        } ?: ""
        val updateTime = lastLocation?.let {
            "更新: ${timeFormat.format(Date(it.time))}"
        } ?: ""
        
        val title = "TracePath 正在运行"
        val content = "$mode | $locationText | $accuracyText | $updateTime"

        val notificationIntent = Intent(this, MainActivity::class.java)
        notificationIntent.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        val pendingIntent = PendingIntent.getActivity(
            this, 0, notificationIntent, PendingIntent.FLAG_IMMUTABLE
        )

        val stopIntent = Intent(this, LocationForegroundService::class.java)
        stopIntent.action = ACTION_STOP
        val stopPendingIntent = PendingIntent.getService(
            this, 1, stopIntent, PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(content)
            .setSmallIcon(R.drawable.ic_notification_icon)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setStyle(NotificationCompat.BigTextStyle().bigText(content))
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "停止", stopPendingIntent)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()
    }

    /**
     * 更新通知
     */
    private fun updateNotification() {
        val manager = getSystemService(NotificationManager::class.java)
        manager?.notify(NOTIFICATION_ID, buildNotification())
    }

    override fun onDestroy() {
        Log.d(TAG, "onDestroy")
        isTracking.set(false)
        locationThread?.interrupt()
        super.onDestroy()
    }

    /**
     * 设置 EventChannel Sink
     */
    fun setEventSink(sink: EventChannel.EventSink?) {
        this.eventSink = sink
    }

    /**
     * 检查服务是否运行
     */
    fun isServiceRunning(): Boolean {
        return isTracking.get()
    }
}
