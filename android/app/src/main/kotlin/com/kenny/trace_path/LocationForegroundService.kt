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
import java.io.File
import java.io.FileWriter
import java.io.IOException
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
        const val ACTION_NOTIFY_SINK_READY = "com.kenny.trace_path.NOTIFY_SINK_READY"
        
        // 默认值
        const val DEFAULT_INTERVAL_SECONDS = 30
        const val DEFAULT_POWER_SAVING = false
        
        // EventChannel
        const val EVENT_CHANNEL_NAME = "com.kenny.trace_path/location_events"
        
        // 静态追踪状态标志（进程内共享，比 ActivityManager 更可靠）
        private val _isTrackingStatic = AtomicBoolean(false)
        
        fun isServiceTracking(): Boolean = _isTrackingStatic.get()
    }

    // 通知渠道
    private val CHANNEL_ID = "location_service_channel"
    private val NOTIFICATION_ID = 888

    // 状态
    private var lastLocation: Location? = null
    private var intervalSeconds = DEFAULT_INTERVAL_SECONDS
    private var powerSaving = DEFAULT_POWER_SAVING
    private var locationThread: Thread? = null
    
    // FusedLocationProvider
    private lateinit var fusedLocationClient: FusedLocationProviderClient
    private var locationCallback: LocationCallback? = null
    
    // EventChannel
    private var eventSink: EventChannel.EventSink? = null
    
    // 日期格式
    private val timeFormat = SimpleDateFormat("HH:mm:ss", Locale.getDefault())

    // 本地轨迹文件（Kotlin 侧兜底记录，Flutter 被杀后仍继续）
    private val dateFormatFile = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault())
    private var trackFile: File? = null

    private val binder = LocalBinder()

    inner class LocalBinder : Binder() {
        fun getService(): LocationForegroundService = this@LocationForegroundService
    }

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "onCreate")
        fusedLocationClient = LocationServices.getFusedLocationProviderClient(this)
        createNotificationChannel()
        initTrackFile()
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
            ACTION_NOTIFY_SINK_READY -> {
                // Flutter EventChannel 重连了
                // 如果服务被系统杀过(isTracking=false)，需要重新启动追踪
                val sink = eventSink ?: LocationPluginBinder.getEventSink()
                Log.d(TAG, "ACTION_NOTIFY_SINK_READY: isTracking=${_isTrackingStatic.get()}, lastLocation=${lastLocation != null}, sink=${sink != null}")
                if (sink == null) {
                    Log.w(TAG, "ACTION_NOTIFY_SINK_READY: sink is null, cannot send")
                } else if (_isTrackingStatic.get() && locationThread?.isAlive == true) {
                    // 正常情况：服务还在跑，线程还活着，立即发一次当前位置
                    lastLocation?.let { sendLocationToFlutter(it) }
                } else {
                    // 服务被系统杀过重建了(isTracking=false)，自动重新启动追踪
                    Log.d(TAG, "ACTION_NOTIFY_SINK_READY: service was killed, auto-restarting tracking")
                    _isTrackingStatic.set(false)
                    locationThread?.interrupt()
                    locationThread = null
                    startTracking()
                }
            }
        }

        return START_STICKY
    }

    /**
     * 开始定位追踪
     */
    private fun startTracking() {
        // 如果正在追踪且线程还活着，则忽略重复启动
        if (_isTrackingStatic.get() && locationThread?.isAlive == true) {
            Log.w(TAG, "Already tracking, ignore")
            return
        }

        // 线程已死但标志位未清理（例如 Flutter 进程被杀死后重启），强制重置状态
        _isTrackingStatic.set(false)
        locationThread?.interrupt()
        locationThread = null

        _isTrackingStatic.set(true)
        startForeground(NOTIFICATION_ID, buildNotification())
        
        // 在独立线程中运行定位循环
        locationThread = Thread {
            Log.d(TAG, "Location loop started")
            while (_isTrackingStatic.get()) {
                val location = requestSingleLocation()
                if (location != null) {
                    lastLocation = location
                    // 发送位置到 Flutter
                    sendLocationToFlutter(location)
                    // 更新通知栏
                    updateNotification()
                }
                
                if (_isTrackingStatic.get()) {
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
        _isTrackingStatic.set(false)
        
        locationThread?.interrupt()
        locationThread = null
        
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    /**
     * 请求单次定位
     * 优先使用精准模式（GPS），超时后自动降级到网络定位（Wi-Fi/基站）
     */
    private fun requestSingleLocation(): Location? {
        Log.d(TAG, "requestSingleLocation: start")

        // 优先精准模式（GPS）
        val location = requestSingleLocationWithPriority(
            if (powerSaving) Priority.PRIORITY_BALANCED_POWER_ACCURACY
            else Priority.PRIORITY_HIGH_ACCURACY,
            45
        )

        if (location != null) {
            Log.d(TAG, "requestSingleLocation: GPS success lat=${location.latitude}, lng=${location.longitude}, accuracy=${location.accuracy}m")
            return location
        }

        // GPS 超时，降级到网络定位（Wi-Fi/基站，不依赖 GPS 信号）
        Log.w(TAG, "requestSingleLocation: GPS timeout, falling back to network positioning")
        val networkLocation = requestSingleLocationWithPriority(
            Priority.PRIORITY_BALANCED_POWER_ACCURACY,
            30
        )

        if (networkLocation != null) {
            Log.d(TAG, "requestSingleLocation: network success lat=${networkLocation.latitude}, lng=${networkLocation.longitude}, accuracy=${networkLocation.accuracy}m")
        } else {
            Log.w(TAG, "requestSingleLocation: all methods failed")
        }

        return networkLocation
    }

    /**
     * 使用指定优先级请求单次定位
     * @param priority 定位优先级
     * @param timeoutSeconds 超时秒数
     */
    private fun requestSingleLocationWithPriority(priority: Int, timeoutSeconds: Long): Location? {
        try {
            val builder = LocationRequest.Builder(priority, 0)
                .setMaxUpdates(1)
                .setWaitForAccurateLocation(false) // false:不等待精确位置。true:等待精确位置 

            var resultLocation: Location? = null
            val latch = java.util.concurrent.CountDownLatch(1)

            val singleCallback = object : LocationCallback() {
                override fun onLocationResult(result: LocationResult) {
                    resultLocation = result.lastLocation
                    try {
                        fusedLocationClient.removeLocationUpdates(this)
                    } catch (e: Exception) {
                        // ignore
                    }
                    latch.countDown()
                }
            }

            fusedLocationClient.requestLocationUpdates(
                builder.build(),
                singleCallback,
                Looper.getMainLooper()
            )

            // 等待
            val waited = latch.await(timeoutSeconds, java.util.concurrent.TimeUnit.SECONDS)
            if (!waited) {
                Log.w(TAG, "requestSingleLocationWithPriority($priority): timeout after ${timeoutSeconds}s")
                try {
                    fusedLocationClient.removeLocationUpdates(singleCallback)
                } catch (e: Exception) {
                    // ignore
                }
            }

            return resultLocation

        } catch (e: SecurityException) {
            Log.e(TAG, "SecurityException in requestSingleLocationWithPriority", e)
            return null
        } catch (e: Exception) {
            Log.e(TAG, "Exception in requestSingleLocationWithPriority", e)
            return null
        }
    }

    /**
     * 发送位置到 Flutter
     */
    private fun sendLocationToFlutter(location: Location) {
        // 优先使用直接设置的 eventSink，否则使用 LocationPluginBinder
        val sink = eventSink ?: LocationPluginBinder.getEventSink()
        if (sink == null) {
            Log.w(TAG, "sendLocationToFlutter: sink is null, event dropped! lat=${location.latitude}, lng=${location.longitude}")
            return
        }
        Log.d(TAG, "sendLocationToFlutter: sink available, sending lat=${location.latitude}, lng=${location.longitude}")
        
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

        // Kotlin 侧兜底记录（Flutter 被杀后仍继续记录）
        saveLocationToFile(location)
    }

    /**
     * 初始化轨迹文件（按天分文件，CSV 格式）
     */
    private fun initTrackFile() {
        try {
            val trackDir = File(filesDir, "location_tracks")
            if (!trackDir.exists()) trackDir.mkdirs()
            val dateStr = dateFormatFile.format(Date())
            trackFile = File(trackDir, "track_$dateStr.csv")

            // 如果文件不存在，写入 CSV 表头
            if (!trackFile!!.exists()) {
                FileWriter(trackFile, true).use { writer ->
                    writer.append("timestamp,latitude,longitude,accuracy,altitude,speed\n")
                }
            }
            Log.d(TAG, "Track file initialized: ${trackFile!!.absolutePath}")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to init track file", e)
        }
    }

    /**
     * 保存位置到本地文件（Kotlin 侧兜底记录，Flutter 被杀后仍继续）
     * 格式：timestamp,latitude,longitude,accuracy,altitude,speed
     */
    private fun saveLocationToFile(location: Location) {
        try {
            if (trackFile == null) {
                initTrackFile()
            }

            val timestamp = location.time
            val latitude = location.latitude
            val longitude = location.longitude
            val accuracy = location.accuracy.toDouble()
            val altitude = if (location.hasAltitude()) location.altitude else 0.0
            val speed = if (location.hasSpeed()) location.speed.toDouble() else 0.0

            val line = "$timestamp,$latitude,$longitude,$accuracy,$altitude,$speed\n"

            FileWriter(trackFile, true).use { writer ->
                writer.append(line)
            }
            Log.d(TAG, "Location saved to file: lat=$latitude, lng=$longitude")
        } catch (e: IOException) {
            Log.e(TAG, "Failed to save location to file", e)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to save location to file", e)
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
        val status = if (_isTrackingStatic.get()) "运行中" else "已停止"
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
        if (manager == null) {
            Log.w(TAG, "updateNotification: NotificationManager is null!")
            return
        }
        Log.d(TAG, "updateNotification: lastLocation=${lastLocation?.latitude},${lastLocation?.longitude}")
        manager.notify(NOTIFICATION_ID, buildNotification())
    }

    override fun onDestroy() {
        Log.d(TAG, "onDestroy")
        _isTrackingStatic.set(false)
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
        return _isTrackingStatic.get()
    }
}
