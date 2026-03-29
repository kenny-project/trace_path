import Flutter
import UIKit
import CoreLocation

class LocationManager: NSObject, CLLocationManagerDelegate {
    static let shared = LocationManager()
    
    private var locationManager: CLLocationManager?
    private var pendingResult: FlutterResult?
    private var isTracking = false
    
    // MethodChannel name
    private let channelName = "com.kenny.trace_path/location_service"
    
    override init() {
        super.init()
    }
    
    func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
        channel.setMethodCallHandler { [weak self] call, result in
            self?.handleMethodCall(call: call, result: result)
        }
    }
    
    func register(with messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
        channel.setMethodCallHandler { [weak self] call, result in
            self?.handleMethodCall(call: call, result: result)
        }
    }
    
    private func handleMethodCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getCurrentPosition":
            getCurrentPosition(result: result)
        case "start":
            if let args = call.arguments as? [String: Any] {
                let powerSaving = args["power_saving"] as? Bool ?? false
                let interval = args["interval"] as? Int ?? 5
                start(interval: interval, powerSaving: powerSaving, result: result)
            } else {
                start(interval: 5, powerSaving: false, result: result)
            }
        case "stop":
            stop(result: result)
        case "updateConfig":
            if let args = call.arguments as? [String: Any] {
                let interval = args["interval"] as? Int ?? 5
                let powerSaving = args["power_saving"] as? Bool ?? false
                updateConfig(interval: interval, powerSaving: powerSaving, result: result)
            } else {
                result(FlutterError(code: "INVALID_ARGS", message: "Invalid arguments", details: nil))
            }
        case "isRunning":
            result(isTracking)
        case "getFilesDir":
            // Return iOS documents directory
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
        
        locationManager?.allowsBackgroundLocationUpdates = true
        locationManager?.showsBackgroundLocationIndicator = true
        
        // Set desired accuracy based on power saving mode
        if powerSaving {
            locationManager?.desiredAccuracy = kCLLocationAccuracyHundredMeters
            locationManager?.distanceFilter = 50 // meters
        } else {
            locationManager?.desiredAccuracy = kCLLocationAccuracyBest
            locationManager?.distanceFilter = 10 // meters
        }
        
        // Set update interval
        let updateInterval = TimeInterval(interval)
        locationManager?.allowDeferredLocationUpdates(untilTraveled: CLLocationDistanceMax, timeout: updateInterval)
        
        locationManager?.startUpdatingLocation()
        isTracking = true
        result(true)
    }
    
    // MARK: - Stop Tracking
    private func stop(result: @escaping FlutterResult) {
        locationManager?.stopUpdatingLocation()
        locationManager?.allowsBackgroundLocationUpdates = false
        isTracking = false
        result(true)
    }
    
    // MARK: - Update Config
    private func updateConfig(interval: Int, powerSaving: Bool, result: @escaping FlutterResult) {
        if powerSaving {
            locationManager?.desiredAccuracy = kCLLocationAccuracyHundredMeters
            locationManager?.distanceFilter = 50
        } else {
            locationManager?.desiredAccuracy = kCLLocationAccuracyBest
            locationManager?.distanceFilter = 10
        }
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
        
        if let result = pendingResult {
            let position: [String: Any] = [
                "latitude": location.coordinate.latitude,
                "longitude": location.coordinate.longitude,
                "altitude": location.altitude,
                "speed": location.speed,
                "accuracy": location.horizontalAccuracy,
                "timestamp": location.timestamp.timeIntervalSince1970 * 1000
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
