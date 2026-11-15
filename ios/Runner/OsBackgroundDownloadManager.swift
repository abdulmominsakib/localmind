import Flutter
import UIKit
import os.log

private let log = OSLog(subsystem: "top.headwindx.localmind", category: "OsBackgroundDownloads")

/// Event payload reported back to Dart through the platform channel.
struct OsDownloadEvent {
    let taskId: String
    let receivedBytes: Int?
    let completed: Bool
    let error: String?

    func toMap() -> [String: Any] {
        var map: [String: Any] = ["taskId": taskId, "completed": completed]
        if let receivedBytes = receivedBytes { map["receivedBytes"] = receivedBytes }
        if let error = error { map["error"] = error }
        return map
    }
}

/// OS-executed downloads via a background `URLSession`.
///
/// Ownership split (see openspec change add-os-background-downloads): native
/// moves bytes only; the Dart engine keeps all bookkeeping. Progress and
/// completion are forwarded to Dart; on completion the downloaded file is
/// moved into the partial-file path so the engine's post-transfer
/// validation/publish chain runs unchanged. A completion marker (`<finalPath>
/// .osdone`) is also written so a wake that misses the callback can finalize
/// on init.
final class OsBackgroundDownloadManager: NSObject {
    static let shared = OsBackgroundDownloadManager()

    static let channelName = "localmind/os_downloads"

    private var session: URLSession?
    private var flutterChannel: FlutterMethodChannel?
    private var backgroundSessionCompletionHandler: (() -> Void)?
    private let queue = DispatchQueue(label: "os.downloads.state")

    private struct HandOff {
        let taskId: String
        let url: URL
        let authToken: String?
        let partPath: String
        let finalPath: String
    }

    /// taskId -> hand-off, kept to resolve download tasks back to payloads.
    private var handOffs: [String: HandOff] = [:]

    /// Called by AppDelegate with launchOptions so events delivered while the
    /// app was not running can complete the stored handler.
    func handleLaunch(options: [UIApplication.LaunchOptionsKey: Any]?) {
        // Background URLSession events arrive through
        // application:handleEventsForBackgroundURLSession:; nothing needed at
        // launch beyond keeping the session identifier stable.
    }

    func register(channel: FlutterMethodChannel) {
        flutterChannel = channel
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self = self else {
                result(FlutterError(code: "unavailable", message: "manager deallocated", details: nil))
                return
            }
            switch call.method {
            case "handOff":
                guard let args = call.arguments as? [String: Any],
                      let taskId = args["taskId"] as? String,
                      let urlString = args["url"] as? String,
                      let url = URL(string: urlString),
                      let partPath = args["partPath"] as? String,
                      let finalPath = args["finalPath"] as? String else {
                    result(FlutterError(code: "badargs", message: "missing hand-off fields", details: nil))
                    return
                }
                let authToken = args["authToken"] as? String
                let handOff = HandOff(
                    taskId: taskId, url: url, authToken: authToken,
                    partPath: partPath, finalPath: finalPath)
                self.queue.sync { self.handOffs[taskId] = handOff }
                self.startDownload(handOff)
                result(true)
            case "cancel":
                guard let args = call.arguments as? [String: Any],
                      let taskId = args["taskId"] as? String else {
                    result(FlutterError(code: "badargs", message: "missing taskId", details: nil))
                    return
                }
                self.cancel(taskId: taskId)
                result(nil)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.background(
            withIdentifier: "top.headwindx.localmind.osDownloads")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.waitsForConnectivity = true
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    private func sessionOrMake() -> URLSession {
        if let session = session { return session }
        let s = makeSession()
        session = s
        return s
    }

    private func startDownload(_ handOff: HandOff) {
        let session = sessionOrMake()
        var request = URLRequest(url: handOff.url)
        if let token = handOff.authToken, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let task = session.downloadTask(with: request)
        task.taskDescription = handOff.taskId
        os_log("OS download hand-off %{public}@", log: log, type: .info, handOff.taskId)
        task.resume()
    }

    private func cancel(taskId: String) {
        queue.sync {
            let pending = session?.allTasks ?? []
            for task in pending where task.taskDescription == taskId {
                task.cancel()
            }
            handOffs.removeValue(forKey: taskId)
        }
    }

    private func handOff(for identifier: String) -> HandOff? {
        queue.sync { handOffs.values.first { $0.taskId == identifier } }
    }

    private func send(_ event: OsDownloadEvent) {
        DispatchQueue.main.async { [weak self] in
            self?.flutterChannel?.invokeMethod("onEvent", arguments: event.toMap())
        }
    }

    /// Stores the system completion handler so background events can finish.
    func handleBackgroundEvents(identifier: String, completionHandler: @escaping () -> Void) {
        backgroundSessionCompletionHandler = completionHandler
    }

    /// Finalizes an OS download: moves the delivered file onto the partial
    /// path and writes a marker so a later engine init can finalize even if
    /// this callback was dropped.
    private func finalizeDownload(task: URLSessionDownloadTask, location: URL, handOff: HandOff) {
        let fm = FileManager.default
        try? fm.createDirectory(
            at: URL(fileURLWithPath: (handOff.partPath as NSString).deletingLastPathComponent),
            withIntermediateDirectories: true)
        // Remove any stale partial: the downloaded file is complete.
        try? fm.removeItem(atPath: handOff.partPath)
        do {
            try fm.moveItem(at: location, to: URL(fileURLWithPath: handOff.partPath))
            let size = (try fm.attributesOfItem(atPath: handOff.partPath)[.size] as? Int) ?? 0
            try "\(size)".write(
                toFile: handOff.finalPath + ".osdone", atomically: true, encoding: .utf8)
            os_log("OS download %{public}@ completed (%d bytes)", log: log, type: .info,
                   handOff.taskId, size)
            send(OsDownloadEvent(taskId: handOff.taskId, receivedBytes: size, completed: true, error: nil))
        } catch {
            os_log("OS download move failed: %{public}@", log: log, type: .error, "\(error)")
            send(OsDownloadEvent(taskId: handOff.taskId, receivedBytes: nil, completed: false,
                                 error: "move failed: \(error)"))
        }
        _ = task // silence unused warning in release builds without delegate storage
    }
}

extension OsBackgroundDownloadManager: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard let identifier = downloadTask.taskDescription else { return }
        // Throttle: report every ~4 MB.
        guard totalBytesWritten % (4 * 1024 * 1024) < bytesWritten else { return }
        send(OsDownloadEvent(taskId: identifier, receivedBytes: Int(totalBytesWritten),
                             completed: false, error: nil))
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let identifier = downloadTask.taskDescription,
              let handOff = handOff(for: identifier) else { return }
        finalizeDownload(task: downloadTask, location: location, handOff: handOff)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let downloadTask = task as? URLSessionDownloadTask,
              let identifier = downloadTask.taskDescription else { return }
        guard let error = error else {
            // Completion without error is handled by didFinishDownloadingTo.
            return
        }
        if (error as NSError).code == NSUserCancelledError { return }
        os_log("OS download %{public}@ failed: %{public}@", log: log, type: .error,
               identifier, "\(error)")
        send(OsDownloadEvent(taskId: identifier, receivedBytes: nil, completed: false,
                             error: error.localizedDescription))
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async { [weak self] in
            self?.backgroundSessionCompletionHandler?()
            self?.backgroundSessionCompletionHandler = nil
        }
    }
}
