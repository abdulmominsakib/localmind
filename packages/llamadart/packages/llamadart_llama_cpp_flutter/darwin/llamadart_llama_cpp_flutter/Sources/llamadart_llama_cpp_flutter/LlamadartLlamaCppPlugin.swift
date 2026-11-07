#if os(iOS)
import Flutter
import UIKit
import llama
#elseif os(macOS)
import FlutterMacOS
import Cocoa
import llama
#endif

public class LlamadartLlamaCppPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {}
}
