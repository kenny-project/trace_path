package com.kenny.trace_path

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * 定位服务 MethodChannel 处理器
 *
 * 处理来自 Flutter 的服务控制命令：
 * - startLocationService: 启动服务
 * - stopLocationService: 停止服务
 * - updateLocationConfig: 更新配置
 * - isLocationServiceRunning: 查询状态
 */
class LocationPlugin(private val context: Context) {

    companion object {
        private const val TAG = "LocationPlugin"

        const val METHOD_CHANNEL_NAME = "com.kenny.trace_path/location_service"
        const val EVENT_CHANNEL_NAME = "com.kenny.trace_path/location_events"

        const val DEFAULT_INTERVAL = 30
        const val DEFAULT_POWER_SAVING = false
    }

    private var eventChannel: EventChannel? = null
    private var methodChannel: MethodChannel? = null
    private var eventSink: EventChannel.EventSink? = null
    private var serviceIntent: Intent? = null
    private var streamHandler: EventChannel.StreamHandler? = null

    /**
     * 注册插件到 FlutterEngine
     */
    fun registerWith(flutterEngine: FlutterEngine) {
        streamHandler = object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                Log.d(TAG, "EventChannel onListen: sink=${events != null}")
                eventSink = events
                LocationPluginBinder.setEventSink(events)
            }

            override fun onCancel(arguments: Any?) {
                Log.d(TAG, "EventChannel onCancel: eventSink will be null")
                eventSink = null
                LocationPluginBinder.setEventSink(null)
            }
        }

        eventChannel = EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            EVENT_CHANNEL_NAME
        )
        eventChannel?.setStreamHandler(streamHandler)

        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            METHOD_CHANNEL_NAME
        )
        methodChannel?.setMethodCallHandler { call, result ->
            handleMethodCall(call, result)
        }

        // Flutter 重启后，之前启动的 LocationForegroundService 还在运行
        // 通知服务：EventChannel 已重新连接，立即发送一次当前位置
        notifyServiceEventSinkReady()

        Log.d(TAG, "LocationPlugin registered")
    }

    /**
     * 通知 LocationForegroundService：EventChannel 已就绪
     * 用于 Flutter 重启后恢复位置推送
     */
    private fun notifyServiceEventSinkReady() {
        try {
            val intent = Intent(context, LocationForegroundService::class.java).apply {
                action = LocationForegroundService.ACTION_NOTIFY_SINK_READY
            }
            context.startService(intent)
            Log.d(TAG, "notifyServiceEventSinkReady sent")
        } catch (e: Exception) {
            Log.e(TAG, "notifyServiceEventSinkReady failed", e)
        }
    }

    /**
     * 获取 EventChannel StreamHandler（供 MainActivity 使用）
     */
    fun getEventStreamHandler(): EventChannel.StreamHandler {
        return streamHandler!!
    }

    /**
     * 处理 MethodChannel 调用
     */
    private fun handleMethodCall(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        Log.d(TAG, "handleMethodCall: method=${call.method}, args=${call.arguments}")

        when (call.method) {
            "startLocationService", "start" -> {
                val interval = call.argument<Int>("interval") ?: DEFAULT_INTERVAL
                val powerSaving = call.argument<Boolean>("powerSaving") ?: DEFAULT_POWER_SAVING
                startLocationService(interval, powerSaving, result)
            }

            "stopLocationService", "stop" -> {
                stopLocationService(result)
            }

            "updateLocationConfig", "updateConfig" -> {
                val interval = call.argument<Int>("interval") ?: DEFAULT_INTERVAL
                val powerSaving = call.argument<Boolean>("powerSaving") ?: DEFAULT_POWER_SAVING
                updateLocationConfig(interval, powerSaving, result)
            }

            "isLocationServiceRunning", "isRunning" -> {
                result.success(isLocationServiceRunning())
            }

            else -> {
                result.notImplemented()
            }
        }
    }

    /**
     * 启动定位服务
     */
    fun startLocationService(interval: Int, powerSaving: Boolean, result: MethodChannel.Result) {
        Log.d(TAG, "startLocationService: interval=${interval}s, powerSaving=$powerSaving")

        try {
            serviceIntent = Intent(context, LocationForegroundService::class.java).apply {
                action = LocationForegroundService.ACTION_START
                putExtra("interval", interval)
                putExtra("powerSaving", powerSaving)
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(serviceIntent!!)
            } else {
                context.startService(serviceIntent!!)
            }

            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "startLocationService failed", e)
            result.error("START_FAILED", e.message, null)
        }
    }

    /**
     * 停止定位服务
     */
    fun stopLocationService(result: MethodChannel.Result) {
        Log.d(TAG, "stopLocationService")

        try {
            serviceIntent = Intent(context, LocationForegroundService::class.java).apply {
                action = LocationForegroundService.ACTION_STOP
            }
            context.startService(serviceIntent)
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "stopLocationService failed", e)
            result.error("STOP_FAILED", e.message, null)
        }
    }

    /**
     * 更新配置
     */
    fun updateLocationConfig(interval: Int, powerSaving: Boolean, result: MethodChannel.Result) {
        Log.d(TAG, "updateLocationConfig: interval=${interval}s, powerSaving=$powerSaving")

        try {
            serviceIntent = Intent(context, LocationForegroundService::class.java).apply {
                action = LocationForegroundService.ACTION_UPDATE_CONFIG
                putExtra("interval", interval)
                putExtra("powerSaving", powerSaving)
            }
            context.startService(serviceIntent)
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "updateLocationConfig failed", e)
            result.error("UPDATE_CONFIG_FAILED", e.message, null)
        }
    }

    /**
     * 检查服务是否运行
     */
    fun isLocationServiceRunning(): Boolean {
        // 直接检查 LocationForegroundService 的 companion object 静态追踪状态标志
        // 比 ActivityManager.getRunningServices() 更可靠（后者可能被系统缓存）
        val tracking = LocationForegroundService.isServiceTracking()
        Log.d(TAG, "isLocationServiceRunning: tracking=${tracking}")
        return tracking
    }

    /**
     * 注销插件
     */
    fun dispose() {
        eventChannel?.setStreamHandler(null)
        methodChannel?.setMethodCallHandler(null)
        eventSink = null
        Log.d(TAG, "LocationPlugin disposed")
    }
}

/**
 * 用于在 Plugin 和 Service 之间传递 EventSink
 */
object LocationPluginBinder {
    private var eventSink: EventChannel.EventSink? = null

    fun setEventSink(sink: EventChannel.EventSink?) {
        eventSink = sink
    }

    fun getEventSink(): EventChannel.EventSink? {
        return eventSink
    }
}
