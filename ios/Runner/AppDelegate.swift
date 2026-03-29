import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Register LocationManager
    if let controller = window?.rootViewController as? FlutterViewController {
      LocationManager.shared.register(with: controller.binaryMessenger)
    } else {
      // Alternative registration for older Flutter versions
      if let registrar = self.registrar(forPlugin: "LocationManager") {
        LocationManager.shared.register(with: registrar)
      }
    }
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    
    // Register LocationManager with the engine
    LocationManager.shared.register(with: engineBridge.pluginRegistry.messenger())
  }
}
