#if os(iOS)
import Flutter
import UIKit
import stable_diffusion
#elseif os(macOS)
import FlutterMacOS
import Cocoa
import stable_diffusion
#endif

public class LlamadartStableDiffusionPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {}
}
