import 'package:flutter/services.dart';

class QuickLaunchService {
  static const _channel = MethodChannel('com.localmind/shortcuts');

  static Future<void> setupShortcuts() async {
    try {
      await _channel.invokeMethod('setupShortcuts', {
        'shortcuts': [
          {
            'id': 'new_chat',
            'title': 'New Chat',
            'description': 'Start a new conversation',
            'icon': 'ic_chat',
          },
        ],
      });
    } on PlatformException {
      // Not supported on this platform, ignore
    }
  }

  static Future<void> handleShortcut(String shortcutId) async {
    // This is called from native side via method channel
    // Implementation depends on routing setup
  }
}
