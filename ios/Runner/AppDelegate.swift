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

        let osChannel = FlutterMethodChannel(name: "localmind/os_downloads", binaryMessenger: controller.binaryMessenger)
        OsBackgroundDownloadManager.shared.register(channel: osChannel)

        return result
    }

    override func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) -> Bool {
        // Keep the session identifier stable with the manager's config.
        OsBackgroundDownloadManager.shared.handleBackgroundEvents(
            identifier: identifier,
            completionHandler: completionHandler)
        return true
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
