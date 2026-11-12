import Cocoa
import FlutterMacOS

public class ClipboardPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    private var eventSink: FlutterEventSink?
    private var clipboardChangeObserver: NSObjectProtocol?
    private var monitoringTimer: Timer?
    private var lastChangeCount: Int = 0
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let methodChannel = FlutterMethodChannel(
            name: "net.cubiclab.clipboard/methods",
            binaryMessenger: registrar.messenger
        )
        let eventChannel = FlutterEventChannel(
            name: "net.cubiclab.clipboard/events",
            binaryMessenger: registrar.messenger
        )
        
        let instance = ClipboardPlugin()
        registrar.addMethodCallDelegate(instance, channel: methodChannel)
        eventChannel.setStreamHandler(instance)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let pasteboard = NSPasteboard.general
        
        switch call.method {
        case "copy":
            guard let args = call.arguments as? [String: Any],
                  let text = args["text"] as? String else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "Text is required", details: nil))
                return
            }
            if text.isEmpty {
                result(FlutterError(code: "EMPTY_TEXT", message: "Text cannot be empty", details: nil))
                return
            }
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            result(true)
            
        case "copyRichText":
            guard let args = call.arguments as? [String: Any] else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "Invalid arguments", details: nil))
                return
            }
            let text = args["text"] as? String ?? ""
            let html = args["html"] as? String
            
            if text.isEmpty && (html == nil || html!.isEmpty) {
                result(FlutterError(code: "EMPTY_CONTENT", message: "Either text or html must be provided", details: nil))
                return
            }
            
            pasteboard.clearContents()
            if let html = html, !html.isEmpty {
                pasteboard.setString(html, forType: .html)
                if !text.isEmpty {
                    pasteboard.setString(text, forType: .string)
                }
            } else {
                pasteboard.setString(text, forType: .string)
            }
            result(true)
            
        case "copyMultiple":
            guard let args = call.arguments as? [String: Any],
                  let formats = args["formats"] as? [String: Any] else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "Invalid arguments", details: nil))
                return
            }
            if formats.isEmpty {
                result(FlutterError(code: "EMPTY_FORMATS", message: "At least one format must be provided", details: nil))
                return
            }
            
            pasteboard.clearContents()
            
            // Handle image first (highest priority)
            if let imageBytes = formats["image/png"] as? [Int], !imageBytes.isEmpty {
                let data = Data(imageBytes.map { UInt8($0 & 0xFF) })
                if let image = NSImage(data: data) {
                    pasteboard.writeObjects([image])
                    if let text = formats["text/plain"] as? String, !text.isEmpty {
                        pasteboard.setString(text, forType: .string)
                    }
                    result(true)
                    return
                }
            }
            
            // Fallback to HTML or text
            if let text = formats["text/plain"] as? String {
                pasteboard.setString(text, forType: .string)
            }
            if let html = formats["text/html"] as? String {
                pasteboard.setString(html, forType: .html)
            }
            result(true)
            
        case "copyImage":
            guard let args = call.arguments as? [String: Any],
                  let imageBytes = args["imageBytes"] as? [Int] else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "Image bytes are required", details: nil))
                return
            }
            if imageBytes.isEmpty {
                result(FlutterError(code: "EMPTY_IMAGE", message: "Image bytes cannot be empty", details: nil))
                return
            }
            let data = Data(imageBytes.map { UInt8($0 & 0xFF) })
            guard let image = NSImage(data: data) else {
                result(FlutterError(code: "INVALID_IMAGE", message: "Failed to decode image", details: nil))
                return
            }
            pasteboard.clearContents()
            pasteboard.writeObjects([image])
            result(true)
            
        case "paste":
            let text = pasteboard.string(forType: .string) ?? ""
            result(["text": text])
            
        case "pasteRichText":
            let text = pasteboard.string(forType: .string) ?? ""
            let html = pasteboard.string(forType: .html)
            let imageBytes = getImageBytesFromClipboard()
            result([
                "text": text,
                "html": (html ?? NSNull()) as Any,
                "imageBytes": (imageBytes ?? NSNull()) as Any,
                "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
            ])
            
        case "pasteImage":
            let imageBytes = getImageBytesFromClipboard()
            if let bytes = imageBytes {
                result(["imageBytes": bytes])
            } else {
                result(["imageBytes": NSNull()])
            }
            
        case "getContentType":
            // Don't access clipboard automatically
            result("unknown")
            
        case "hasData":
            // Don't access clipboard automatically
            result(false)
            
        case "clear":
            pasteboard.clearContents()
            result(true)
            
        case "getDataSize":
            // Don't access clipboard automatically
            result(0)
            
        case "startMonitoring":
            startMonitoring()
            result(true)
            
        case "stopMonitoring":
            stopMonitoring()
            result(true)
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func startMonitoring() {
        if monitoringTimer != nil {
            return
        }
        
        let pasteboard = NSPasteboard.general
        lastChangeCount = pasteboard.changeCount
        
        // macOS doesn't have native clipboard change notifications
        // Use a timer-based polling approach
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkClipboardChange()
        }
    }
    
    private func stopMonitoring() {
        monitoringTimer?.invalidate()
        monitoringTimer = nil
        if let observer = clipboardChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            clipboardChangeObserver = nil
        }
    }
    
    private func checkClipboardChange() {
        let pasteboard = NSPasteboard.general
        let currentChangeCount = pasteboard.changeCount
        
        // Only notify if clipboard actually changed
        if currentChangeCount != lastChangeCount {
            lastChangeCount = currentChangeCount
            
            let text = pasteboard.string(forType: .string) ?? ""
            let html = pasteboard.string(forType: .html)
            
            eventSink?([
                "text": text,
                "html": (html ?? NSNull()) as Any,
                "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
            ])
        }
    }
    
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        startMonitoring()
        return nil
    }
    
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        stopMonitoring()
        return nil
    }
    
    private func getImageBytesFromClipboard() -> [Int]? {
        let pasteboard = NSPasteboard.general
        
        // Check if clipboard has image data
        guard pasteboard.canReadObject(forClasses: [NSImage.self], options: nil) else {
            return nil
        }
        
        guard let image = pasteboard.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage else {
            return nil
        }
        
        // Convert NSImage to PNG data
        guard let tiffData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
            return nil
        }
        
        return Array(pngData.map { Int($0) })
    }
    
    deinit {
        stopMonitoring()
    }
}

