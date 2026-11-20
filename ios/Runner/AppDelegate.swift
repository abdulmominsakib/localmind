import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)

        UNUserNotificationCenter.current().delegate = self

        let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)

        guard let controller = window?.rootViewController as? FlutterViewController else {
            return result
        }

        let channel = FlutterMethodChannel(name: "localmind/chat_background", binaryMessenger: controller.binaryMessenger)
        channel.setMethodCallHandler({
            (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
            switch call.method {
            case "startForeground":
                self.startBackgroundTask()
                result(nil)
            case "stopForeground":
                self.stopBackgroundTask()
                result(nil)
            default:
                result(FlutterMethodNotImplemented)
            }
        })

        return result
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
