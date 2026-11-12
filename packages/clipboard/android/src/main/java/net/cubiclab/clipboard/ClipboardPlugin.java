package net.cubiclab.clipboard;

import android.content.Context;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodChannel;

/** ClipboardPlugin */
public class ClipboardPlugin implements FlutterPlugin {
  private MethodChannel methodChannel;
  private EventChannel eventChannel;
  private ClipboardChannelHandler handler;

  @Override
  public void onAttachedToEngine(FlutterPluginBinding flutterPluginBinding) {
    Context context = flutterPluginBinding.getApplicationContext();
    handler = new ClipboardChannelHandler(context);
    
    methodChannel = new MethodChannel(
        flutterPluginBinding.getBinaryMessenger(), "net.cubiclab.clipboard/methods");
    methodChannel.setMethodCallHandler(handler);

    eventChannel = new EventChannel(
        flutterPluginBinding.getBinaryMessenger(), "net.cubiclab.clipboard/events");
    eventChannel.setStreamHandler(handler);
  }

  @Override
  public void onDetachedFromEngine(FlutterPluginBinding binding) {
    methodChannel.setMethodCallHandler(null);
    eventChannel.setStreamHandler(null);
    handler = null;
  }
}

