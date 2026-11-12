#if os(iOS)
import Flutter
import UIKit
import LiteRtLm
import CLiteRTLM
#elseif os(macOS)
import FlutterMacOS
import Cocoa
#endif

public class LlamadartLiteRtLmPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {}
}
