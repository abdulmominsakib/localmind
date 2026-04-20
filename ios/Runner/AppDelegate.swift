import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
        let channel = FlutterMethodChannel(name: "localmind/chat_background", binaryMessenger: controller.binaryMessenger)

        channel.setMethodCallHandler({
            (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
            switch call.method {
            case "startForeground":
                // On iOS, we start a background task assertion
                self.startBackgroundTask()
                result(nil)
            case "stopForeground":
                // On iOS, we end the background task assertion
                self.stopBackgroundTask()
                result(nil)
            default:
                result(FlutterMethodNotImplemented)
            }
        })

        GeneratedPluginRegistrant.register(with: self)
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    private func startBackgroundTask() {
        stopBackgroundTask()
        backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.stopBackgroundTask()
        }
    }

    private func stopBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }
}
