package com.kenny.trace_path

import android.app.ActivityManager
import android.content.ComponentName
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
        
        // 默认值
        const val DEFAULT_INTERVAL = 30
        const val DEFAULT_POWER_SAVING = false
    }

    private var eventChannel: EventChannel? = null
    private var methodChannel: MethodChannel? = null
    private var eventSink: EventChannel.EventSink? = null
    private var serviceIntent: Intent? = null

    /**
     * 注册插件到 FlutterEngine
     */
    fun registerWith(flutterEngine: FlutterEngine) {
        // 设置 EventChannel
        eventChannel = EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            EVENT_CHANNEL_NAME
        )
        eventChannel?.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                Log.d(TAG, "EventChannel onListen")
                eventSink = events
                
                // 将 sink 传递给服务
                LocationPluginBinder.setEventSink(events)
            }

            override fun onCancel(arguments: Any?) {
                Log.d(TAG, "EventChannel onCancel")
                eventSink = null
                LocationPluginBinder.setEventSink(null)
            }
        })

        // 设置 MethodChannel
        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            METHOD_CHANNEL_NAME
        )
        methodChannel?.setMethodCallHandler { call, result ->
            handleMethodCall(call, result)
        }

        Log.d(TAG, "LocationPlugin registered")
    }

    /**
     * 处理 MethodChannel 调用
     */
    private fun handleMethodCall(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        Log.d(TAG, "handleMethodCall: method=${call.method}, args=${call.arguments}")

        when (call.method) {
            "startLocationService" -> {
                val interval = call.argument<Int>("interval") ?: DEFAULT_INTERVAL
                val powerSaving = call.argument<Boolean>("powerSaving") ?: DEFAULT_POWER_SAVING
                startLocationService(interval, powerSaving, result)
            }
            
            "stopLocationService" -> {
                stopLocationService(result)
            }
            
            "updateLocationConfig" -> {
                val interval = call.argument<Int>("interval") ?: DEFAULT_INTERVAL
                val powerSaving = call.argument<Boolean>("powerSaving") ?: DEFAULT_POWER_SAVING
                updateLocationConfig(interval, powerSaving, result)
            }
            
            "isLocationServiceRunning" -> {
                result.success(isLocationServiceRunning())
            }
            
            // 以下是兼容旧版 Flutter 代码的方法名
            "start" -> {
                val interval = call.argument<Int>("interval") ?: DEFAULT_INTERVAL
                val powerSaving = call.argument<Boolean>("powerSaving") ?: DEFAULT_POWER_SAVING
                startLocationService(interval, powerSaving, result)
            }
            
            "stop" -> {
                stopLocationService(result)
            }
            
            "updateConfig" -> {
                val interval = call.argument<Int>("interval") ?: DEFAULT_INTERVAL
                val powerSaving = call.argument<Boolean>("powerSaving") ?: DEFAULT_POWER_SAVING
                updateLocationConfig(interval, powerSaving, result)
            }
            
            "isRunning" -> {
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
    private fun startLocationService(interval: Int, powerSaving: Boolean, result: MethodChannel.Result) {
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
    private fun stopLocationService(result: MethodChannel.Result) {
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
    private fun updateLocationConfig(interval: Int, powerSaving: Boolean, result: MethodChannel.Result) {
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
    private fun isLocationServiceRunning(): Boolean {
        try {
            val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            for (service in am.getRunningServices(Integer.MAX_VALUE)) {
                if ("com.kenny.trace_path.LocationForegroundService" == service.service.className) {
                    Log.d(TAG, "isLocationServiceRunning: true")
                    return true
                }
            }
            Log.d(TAG, "isLocationServiceRunning: false")
            return false
        } catch (e: Exception) {
            Log.e(TAG, "isLocationServiceRunning error", e)
            return false
        }
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
