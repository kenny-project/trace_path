import Flutter
import UIKit
import CoreLocation

class LocationManager: NSObject, CLLocationManagerDelegate {
    static let shared = LocationManager()
    
    private var locationManager: CLLocationManager?
    private var pendingResult: FlutterResult?
    private var isTracking = false
    
    // MethodChannel name
    private let methodChannelName = "com.kenny.trace_path/location_service"
    // EventChannel name
    private let eventChannelName = "com.kenny.trace_path/location_events"
    
    // EventChannel
    private var eventSink: FlutterEventSink?
    
    // 配置
    private var intervalSeconds: Int = 30
    private var powerSaving: Bool = false
    
    override init() {
        super.init()
    }
    
    func register(with registrar: FlutterPluginRegistrar) {
        // MethodChannel
        let methodChannel = FlutterMethodChannel(name: methodChannelName, binaryMessenger: registrar.messenger())
        methodChannel.setMethodCallHandler { [weak self] call, result in
            self?.handleMethodCall(call: call, result: result)
        }
        
        // EventChannel
        let eventChannel = FlutterEventChannel(name: eventChannelName, binaryMessenger: registrar.messenger())
        eventChannel.setStreamHandler(self)
    }
    
    func register(with messenger: FlutterBinaryMessenger) {
        // MethodChannel
        let methodChannel = FlutterMethodChannel(name: methodChannelName, binaryMessenger: messenger)
        methodChannel.setMethodCallHandler { [weak self] call, result in
            self?.handleMethodCall(call: call, result: result)
        }
        
        // EventChannel
        let eventChannel = FlutterEventChannel(name: eventChannelName, binaryMessenger: messenger)
        eventChannel.setStreamHandler(self)
    }
    
    private func handleMethodCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
        print("LocationManager handleMethodCall: \(call.method)")
        
        switch call.method {
        case "getCurrentPosition":
            getCurrentPosition(result: result)
            
        case "startLocationService", "start":
            if let args = call.arguments as? [String: Any] {
                let interval = args["interval"] as? Int ?? 30
                let powerSaving = args["powerSaving"] as? Bool ?? false
                start(interval: interval, powerSaving: powerSaving, result: result)
            } else {
                start(interval: 30, powerSaving: false, result: result)
            }
            
        case "stopLocationService", "stop":
            stop(result: result)
            
        case "updateLocationConfig", "updateConfig":
            if let args = call.arguments as? [String: Any] {
                let interval = args["interval"] as? Int ?? 30
                let powerSaving = args["powerSaving"] as? Bool ?? false
                updateConfig(interval: interval, powerSaving: powerSaving, result: result)
            } else {
                result(FlutterError(code: "INVALID_ARGS", message: "Invalid arguments", details: nil))
            }
            
        case "isLocationServiceRunning", "isRunning":
            result(isTracking)
            
        case "getFilesDir":
            let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            result(paths[0].path)
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    // MARK: - Get Current Position
    private func getCurrentPosition(result: @escaping FlutterResult) {
        initLocationManager()
        locationManager?.requestLocation()
        pendingResult = result
    }
    
    // MARK: - Start Tracking
    private func start(interval: Int, powerSaving: Bool, result: @escaping FlutterResult) {
        initLocationManager()
        
        self.intervalSeconds = interval
        self.powerSaving = powerSaving
        
        locationManager?.allowsBackgroundLocationUpdates = true
        locationManager?.showsBackgroundLocationIndicator = true
        
        // Set desired accuracy based on power saving mode
        if powerSaving {
            locationManager?.desiredAccuracy = kCLLocationAccuracyHundredMeters
            locationManager?.distanceFilter = max(50, interval * 10) // meters
        } else {
            locationManager?.desiredAccuracy = kCLLocationAccuracyBest
            locationManager?.distanceFilter = max(10, interval * 2) // meters
        }
        
        locationManager?.startUpdatingLocation()
        isTracking = true
        print("LocationManager started: interval=\(interval)s, powerSaving=\(powerSaving)")
        result(true)
    }
    
    // MARK: - Stop Tracking
    private func stop(result: @escaping FlutterResult) {
        locationManager?.stopUpdatingLocation()
        locationManager?.allowsBackgroundLocationUpdates = false
        isTracking = false
        print("LocationManager stopped")
        result(true)
    }
    
    // MARK: - Update Config
    private func updateConfig(interval: Int, powerSaving: Bool, result: @escaping FlutterResult) {
        self.intervalSeconds = interval
        self.powerSaving = powerSaving
        
        if powerSaving {
            locationManager?.desiredAccuracy = kCLLocationAccuracyHundredMeters
            locationManager?.distanceFilter = max(50, interval * 10)
        } else {
            locationManager?.desiredAccuracy = kCLLocationAccuracyBest
            locationManager?.distanceFilter = max(10, interval * 2)
        }
        
        print("LocationManager config updated: interval=\(interval)s, powerSaving=\(powerSaving)")
        result(true)
    }
    
    // MARK: - Init Location Manager
    private func initLocationManager() {
        if locationManager == nil {
            locationManager = CLLocationManager()
            locationManager?.delegate = self
            locationManager?.requestAlwaysAuthorization()
        }
    }
    
    // MARK: - CLLocationManagerDelegate
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        // 发送位置到 Flutter (EventChannel)
        if let sink = eventSink {
            let position: [String: Any] = [
                "latitude": location.coordinate.latitude,
                "longitude": location.coordinate.longitude,
                "altitude": location.altitude,
                "speed": max(0, location.speed),
                "accuracy": location.horizontalAccuracy,
                "heading": location.course >= 0 ? location.course : 0,
                "timestamp": Int(location.timestamp.timeIntervalSince1970 * 1000)
            ]
            sink(position)
            print("Location sent to Flutter: lat=\(location.coordinate.latitude), lng=\(location.coordinate.longitude)")
        }
        
        // 处理单次定位请求
        if let result = pendingResult {
            let position: [String: Any] = [
                "latitude": location.coordinate.latitude,
                "longitude": location.coordinate.longitude,
                "altitude": location.altitude,
                "speed": max(0, location.speed),
                "accuracy": location.horizontalAccuracy,
                "heading": location.course >= 0 ? location.course : 0,
                "timestamp": Int(location.timestamp.timeIntervalSince1970 * 1000)
            ]
            result(position)
            pendingResult = nil
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("LocationManager error: \(error.localizedDescription)")
        
        if let result = pendingResult {
            result(FlutterError(code: "LOCATION_ERROR", message: error.localizedDescription, details: nil))
            pendingResult = nil
        }
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            print("Location authorized")
        case .denied, .restricted:
            print("Location denied")
        case .notDetermined:
            print("Location not determined")
        @unknown default:
            break
        }
    }
}

// MARK: - FlutterStreamHandler
extension LocationManager: FlutterStreamHandler {
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        print("LocationManager EventChannel onListen")
        self.eventSink = events
        return nil
    }
    
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        print("LocationManager EventChannel onCancel")
        self.eventSink = nil
        return nil
    }
}
