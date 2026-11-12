
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

// Conditional imports for web support
import 'src/clipboard_web_stub.dart'
    if (dart.library.js) 'src/clipboard_web.dart';

/// Custom exception for clipboard operations
class ClipboardException implements Exception {
  final String message;
  final String? code;

  ClipboardException(this.message, [this.code]);

  @override
  String toString() =>
      'ClipboardException: $message${code != null ? ' (Code: $code)' : ''}';
}

/// Enhanced data class for clipboard content
class EnhancedClipboardData {
  final String? text;
  final String? html;
  final Uint8List? imageBytes;
  final List<String>? filePaths;
  final Map<String, dynamic>? customData;
  final DateTime? timestamp;

  EnhancedClipboardData({
    this.text,
    this.html,
    this.imageBytes,
    this.filePaths,
    this.customData,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Factory constructor from platform channel map
  factory EnhancedClipboardData.fromMap(Map<dynamic, dynamic> map) {
    Uint8List? imageBytes;
    if (map['imageBytes'] != null) {
      final List<dynamic> bytes = map['imageBytes'] as List<dynamic>;
      imageBytes = Uint8List.fromList(bytes.cast<int>());
    }

    List<String>? filePaths;
    if (map['filePaths'] != null) {
      filePaths = List<String>.from(map['filePaths'] as List);
    }

    return EnhancedClipboardData(
      text: map['text'] as String?,
      html: map['html'] as String?,
      imageBytes: imageBytes,
      filePaths: filePaths,
      customData: map['customData'] as Map<String, dynamic>?,
      timestamp: map['timestamp'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int)
          : null,
    );
  }

  /// Convert to map for platform channel
  Map<String, dynamic> toMap() {
    return {
      'text': text,
      'html': html,
      'imageBytes': imageBytes?.toList(),
      'filePaths': filePaths,
      'customData': customData,
      'timestamp': timestamp?.millisecondsSinceEpoch,
    };
  }

  bool get isEmpty =>
      text?.isEmpty != false &&
      html?.isEmpty != false &&
      imageBytes?.isEmpty != false &&
      filePaths?.isEmpty != false;

  bool get hasText => text?.isNotEmpty == true;
  bool get hasHtml => html?.isNotEmpty == true;
  bool get hasImage => imageBytes?.isNotEmpty == true;
  bool get hasFiles => filePaths?.isNotEmpty == true;
}

/// Content type enumeration
enum ClipboardContentType { text, html, image, files, mixed, empty, unknown }

/// A Flutter Clipboard Plugin with enhanced functionality.
class FlutterClipboard {
  static final MethodChannel _channel =
      MethodChannel('net.cubiclab.clipboard/methods');
  static final EventChannel _eventChannel =
      EventChannel('net.cubiclab.clipboard/events');

  static final Set<Function(EnhancedClipboardData)> _listeners = {};
  static StreamSubscription<dynamic>? _clipboardChangeSubscription;
  static EnhancedClipboardData? _lastData;
  static bool _isMonitoring = false;

  // Private constructor to prevent instantiation
  FlutterClipboard._();

  /// Copy text to clipboard
  /// Returns void
  static Future<void> copy(String text) async {
    if (text.isEmpty) {
      throw ClipboardException('Text cannot be empty', 'EMPTY_TEXT');
    }
    try {
      // Use platform channel for better cross-platform support
      final result = await _channel.invokeMethod<bool>('copy', {'text': text});
      if (result != true) {
        throw ClipboardException('Copy operation failed', 'COPY_ERROR');
      }
      final data = EnhancedClipboardData(text: text);
      _lastData = data;
      _notifyListeners(data);
    } on PlatformException catch (e) {
      throw ClipboardException(
          'Failed to copy text: ${e.message}', 'COPY_ERROR');
    } catch (e) {
      // Fallback to Flutter's Clipboard API
      try {
        await Clipboard.setData(ClipboardData(text: text));
        final data = EnhancedClipboardData(text: text);
        _lastData = data;
        _notifyListeners(data);
      } catch (fallbackError) {
        throw ClipboardException('Failed to copy text: $e', 'COPY_ERROR');
      }
    }
  }

  /// Copy rich text to clipboard with HTML support
  static Future<void> copyRichText({required String text, String? html}) async {
    if (text.isEmpty && html?.isEmpty != false) {
      throw ClipboardException(
        'Either text or html must be provided',
        'EMPTY_CONTENT',
      );
    }

    // Web platform support
    if (kIsWeb) {
      try {
        await copyRichTextWebImpl(text, html);
        final data = EnhancedClipboardData(text: text, html: html);
        _lastData = data;
        _notifyListeners(data);
        return;
      } catch (e) {
        throw ClipboardException(
          'Failed to copy rich text on web: $e',
          'COPY_RICH_ERROR',
        );
      }
    }

    // Native platform support
    try {
      final result = await _channel.invokeMethod<bool>('copyRichText', {
        'text': text,
        'html': html,
      });
      if (result != true) {
        throw ClipboardException(
            'Copy rich text operation failed', 'COPY_RICH_ERROR');
      }
      final data = EnhancedClipboardData(text: text, html: html);
      _lastData = data;
      _notifyListeners(data);
    } on PlatformException catch (e) {
      throw ClipboardException(
        'Failed to copy rich text: ${e.message}',
        'COPY_RICH_ERROR',
      );
    } catch (e) {
      // Fallback to Flutter's Clipboard API
      try {
        await Clipboard.setData(
          ClipboardData(text: text.isNotEmpty ? text : html ?? ''),
        );
        final data = EnhancedClipboardData(text: text, html: html);
        _lastData = data;
        _notifyListeners(data);
      } catch (fallbackError) {
        throw ClipboardException(
          'Failed to copy rich text: $e',
          'COPY_RICH_ERROR',
        );
      }
    }
  }

  /// Copy multiple formats simultaneously
  static Future<void> copyMultiple(Map<String, dynamic> formats) async {
    if (formats.isEmpty) {
      throw ClipboardException(
        'At least one format must be provided',
        'EMPTY_FORMATS',
      );
    }

    try {
      // Convert image bytes to list if present
      Map<String, dynamic> convertedFormats =
          Map<String, dynamic>.from(formats);
      if (formats['image/png'] is Uint8List) {
        convertedFormats['image/png'] =
            (formats['image/png'] as Uint8List).toList();
      }

      final result = await _channel.invokeMethod<bool>(
        'copyMultiple',
        {'formats': convertedFormats},
      );
      if (result != true) {
        throw ClipboardException(
            'Copy multiple formats operation failed', 'COPY_MULTIPLE_ERROR');
      }

      final text = formats['text/plain']?.toString();
      final html = formats['text/html']?.toString();
      Uint8List? imageBytes;
      if (formats['image/png'] is Uint8List) {
        imageBytes = formats['image/png'] as Uint8List;
      } else if (formats['image/png'] is List<int>) {
        imageBytes = Uint8List.fromList(formats['image/png'] as List<int>);
      }

      final data = EnhancedClipboardData(
        text: text,
        html: html,
        imageBytes: imageBytes,
        customData: formats,
      );
      _lastData = data;
      _notifyListeners(data);
    } on PlatformException catch (e) {
      throw ClipboardException(
        'Failed to copy multiple formats: ${e.message}',
        'COPY_MULTIPLE_ERROR',
      );
    } catch (e) {
      // Fallback: copy text only
      try {
        final text = formats['text/plain']?.toString() ?? '';
        await Clipboard.setData(ClipboardData(text: text));
        final data = EnhancedClipboardData(text: text, customData: formats);
        _lastData = data;
        _notifyListeners(data);
      } catch (fallbackError) {
        throw ClipboardException(
          'Failed to copy multiple formats: $e',
          'COPY_MULTIPLE_ERROR',
        );
      }
    }
  }

  /// Copy image to clipboard
  /// [imageBytes] should be PNG format bytes
  static Future<void> copyImage(Uint8List imageBytes) async {
    if (imageBytes.isEmpty) {
      throw ClipboardException('Image bytes cannot be empty', 'EMPTY_IMAGE');
    }

    // Web platform support
    if (kIsWeb) {
      try {
        await _copyImageWeb(imageBytes);
        final data = EnhancedClipboardData(imageBytes: imageBytes);
        _lastData = data;
        _notifyListeners(data);
        return;
      } catch (e) {
        throw ClipboardException(
          'Failed to copy image on web: $e',
          'COPY_IMAGE_ERROR',
        );
      }
    }

    // Native platform support
    try {
      final result = await _channel.invokeMethod<bool>(
        'copyImage',
        {'imageBytes': imageBytes.toList()},
      );
      if (result != true) {
        throw ClipboardException(
            'Copy image operation failed', 'COPY_IMAGE_ERROR');
      }
      final data = EnhancedClipboardData(imageBytes: imageBytes);
      _lastData = data;
      _notifyListeners(data);
    } on PlatformException catch (e) {
      throw ClipboardException(
        'Failed to copy image: ${e.message}',
        'COPY_IMAGE_ERROR',
      );
    } catch (e) {
      throw ClipboardException('Failed to copy image: $e', 'COPY_IMAGE_ERROR');
    }
  }

  /// Web-specific image copy implementation
  static Future<void> _copyImageWeb(Uint8List imageBytes) async {
    // Use conditional import for web - function is imported from web stub/web implementation
    return copyImageWebImpl(imageBytes);
  }

  /// Copy with success/error callbacks
  static Future<void> copyWithCallback({
    required String text,
    void Function()? onSuccess,
    Function(String error)? onError,
  }) async {
    try {
      await copy(text);
      onSuccess?.call();
    } catch (e) {
      final error = e is ClipboardException ? e.message : e.toString();
      onError?.call(error);
      rethrow;
    }
  }

  /// Paste text from clipboard
  static Future<String> paste() async {
    // Web platform support
    if (kIsWeb) {
      try {
        return await pasteTextWebImpl();
      } catch (e) {
        // Fallback to Flutter's Clipboard API on web
        try {
          final data = await Clipboard.getData('text/plain');
          return data?.text?.toString() ?? "";
        } catch (fallbackError) {
          throw ClipboardException(
              'Failed to paste text on web: $e', 'PASTE_ERROR');
        }
      }
    }

    // Native platform support
    try {
      final result =
          await _channel.invokeMethod<Map<dynamic, dynamic>>('paste');
      if (result != null && result['text'] != null) {
        return result['text'] as String;
      }
      // Fallback to Flutter's Clipboard API
      final data = await Clipboard.getData('text/plain');
      return data?.text?.toString() ?? "";
    } on PlatformException catch (e) {
      // Fallback to Flutter's Clipboard API
      try {
        final data = await Clipboard.getData('text/plain');
        return data?.text?.toString() ?? "";
      } catch (fallbackError) {
        throw ClipboardException(
            'Failed to paste text: ${e.message}', 'PASTE_ERROR');
      }
    } catch (e) {
      throw ClipboardException('Failed to paste text: $e', 'PASTE_ERROR');
    }
  }

  /// Paste rich text from clipboard
  static Future<EnhancedClipboardData> pasteRichText() async {
    // Web platform support
    if (kIsWeb) {
      try {
        final result = await pasteRichTextWebImpl();
        // Convert Map to EnhancedClipboardData
        final data =
            EnhancedClipboardData.fromMap(result as Map<dynamic, dynamic>);
        _lastData = data;
        return data;
      } catch (e) {
        // Fallback to Flutter's Clipboard API on web
        try {
          final data = await Clipboard.getData('text/plain');
          final htmlData = await Clipboard.getData('text/html');
          final clipboardData = EnhancedClipboardData(
            text: data?.text,
            html: htmlData?.text,
          );
          _lastData = clipboardData;
          return clipboardData;
        } catch (fallbackError) {
          throw ClipboardException(
            'Failed to paste rich text on web: $e',
            'PASTE_RICH_ERROR',
          );
        }
      }
    }

    // Native platform support
    try {
      final result =
          await _channel.invokeMethod<Map<dynamic, dynamic>>('pasteRichText');
      if (result != null) {
        final data = EnhancedClipboardData.fromMap(result);
        _lastData = data;
        return data;
      }
      // Fallback to Flutter's Clipboard API
      final data = await Clipboard.getData('text/plain');
      final htmlData = await Clipboard.getData('text/html');
      final clipboardData = EnhancedClipboardData(
        text: data?.text,
        html: htmlData?.text,
      );
      _lastData = clipboardData;
      return clipboardData;
    } on PlatformException catch (e) {
      // Fallback to Flutter's Clipboard API
      try {
        final data = await Clipboard.getData('text/plain');
        final htmlData = await Clipboard.getData('text/html');
        final clipboardData = EnhancedClipboardData(
          text: data?.text,
          html: htmlData?.text,
        );
        _lastData = clipboardData;
        return clipboardData;
      } catch (fallbackError) {
        throw ClipboardException(
          'Failed to paste rich text: ${e.message}',
          'PASTE_RICH_ERROR',
        );
      }
    } catch (e) {
      throw ClipboardException(
        'Failed to paste rich text: $e',
        'PASTE_RICH_ERROR',
      );
    }
  }

  /// Paste image from clipboard
  /// Returns the image bytes if available, null otherwise
  static Future<Uint8List?> pasteImage() async {
    // Web platform support
    if (kIsWeb) {
      try {
        return await _pasteImageWeb();
      } catch (e) {
        // Return null on web errors (clipboard might not have image)
        return null;
      }
    }

    // Native platform support
    try {
      final result =
          await _channel.invokeMethod<Map<dynamic, dynamic>>('pasteImage');
      if (result != null && result['imageBytes'] != null) {
        final bytes = result['imageBytes'] as List<dynamic>;
        return Uint8List.fromList(bytes.cast<int>());
      }
      return null;
    } on PlatformException {
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Web-specific image paste implementation
  static Future<Uint8List?> _pasteImageWeb() async {
    // Use conditional import for web - function is imported from web stub/web implementation
    return pasteImageWebImpl();
  }

  /// Get clipboard content type
  /// Note: This method no longer accesses the clipboard automatically to avoid permission prompts.
  /// Call paste() or pasteRichText() first to access clipboard content.
  static Future<ClipboardContentType> getContentType() async {
    try {
      final result = await _channel.invokeMethod<String>('getContentType');
      if (result != null && result != 'unknown') {
        switch (result) {
          case 'text':
            return ClipboardContentType.text;
          case 'html':
            return ClipboardContentType.html;
          case 'image':
            return ClipboardContentType.image;
          case 'files':
            return ClipboardContentType.files;
          case 'mixed':
            return ClipboardContentType.mixed;
          case 'empty':
            return ClipboardContentType.empty;
          default:
            return ClipboardContentType.unknown;
        }
      }
      // Return unknown to avoid accessing clipboard automatically
      return ClipboardContentType.unknown;
    } catch (e) {
      return ClipboardContentType.unknown;
    }
  }

  /// Check if clipboard has content
  /// Note: This method no longer accesses the clipboard automatically to avoid permission prompts.
  /// Call paste() or pasteRichText() first to access clipboard content.
  static Future<bool> hasData() async {
    try {
      final result = await _channel.invokeMethod<bool>('hasData');
      if (result != null) {
        return result;
      }
      // Return false to avoid accessing clipboard automatically
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Check if clipboard is empty
  static Future<bool> isEmpty() async {
    return !(await hasData());
  }

  /// Clear clipboard
  static Future<void> clear() async {
    try {
      final result = await _channel.invokeMethod<bool>('clear');
      if (result != true) {
        throw ClipboardException('Clear operation failed', 'CLEAR_ERROR');
      }
      _lastData = EnhancedClipboardData();
      _notifyListeners(_lastData!);
    } on PlatformException catch (e) {
      // Fallback
      try {
        await Clipboard.setData(const ClipboardData(text: ''));
        _lastData = EnhancedClipboardData();
        _notifyListeners(_lastData!);
      } catch (fallbackError) {
        throw ClipboardException(
            'Failed to clear clipboard: ${e.message}', 'CLEAR_ERROR');
      }
    } catch (e) {
      throw ClipboardException('Failed to clear clipboard: $e', 'CLEAR_ERROR');
    }
  }

  /// Get clipboard data size (approximate)
  /// Note: This method no longer accesses the clipboard automatically to avoid permission prompts.
  /// Call paste() or pasteRichText() first to access clipboard content.
  static Future<int> getDataSize() async {
    try {
      final result = await _channel.invokeMethod<int>('getDataSize');
      if (result != null) {
        return result;
      }
      // Return 0 to avoid accessing clipboard automatically
      return 0;
    } catch (e) {
      return 0;
    }
  }

  /// Validate input before copying
  static bool isValidInput(String text) {
    return text.isNotEmpty && text.trim().isNotEmpty;
  }

  /// Add clipboard change listener
  /// Returns a function to remove the listener
  static Function() addListener(Function(EnhancedClipboardData) listener) {
    _listeners.add(listener);
    // Return a cleanup function
    return () => removeListener(listener);
  }

  /// Remove clipboard change listener
  static void removeListener(Function(EnhancedClipboardData) listener) {
    _listeners.remove(listener);
  }

  /// Remove all listeners
  static void removeAllListeners() {
    _listeners.clear();
  }

  /// Start monitoring clipboard changes using native notifications
  static Future<void> startMonitoring({
    Duration interval = const Duration(milliseconds: 500),
  }) async {
    if (_isMonitoring) {
      return;
    }

    try {
      // Try to use native clipboard change notifications
      _clipboardChangeSubscription =
          _eventChannel.receiveBroadcastStream().listen(
        (dynamic event) {
          try {
            if (event is Map) {
              final data = EnhancedClipboardData.fromMap(event);
              if (_lastData?.text != data.text ||
                  _lastData?.html != data.html ||
                  _lastData?.imageBytes != data.imageBytes) {
                _lastData = data;
                _notifyListeners(data);
              }
            }
          } catch (e) {
            // Ignore parsing errors
          }
        },
        onError: (error) {
          // If native monitoring fails, fall back to polling
          _startPollingMonitoring(interval);
        },
      );

      // Start native monitoring on platform
      await _channel.invokeMethod<bool>('startMonitoring');
      _isMonitoring = true;
    } catch (e) {
      // Fallback to polling if native monitoring is not available
      _startPollingMonitoring(interval);
    }
  }

  /// Internal method for polling-based monitoring (fallback)
  static Timer? _monitoringTimer;
  static void _startPollingMonitoring(Duration interval) {
    _monitoringTimer?.cancel();
    _monitoringTimer = Timer.periodic(interval, (timer) async {
      try {
        final currentData = await pasteRichText();
        if (_lastData?.text != currentData.text ||
            _lastData?.html != currentData.html ||
            _lastData?.imageBytes != currentData.imageBytes) {
          _lastData = currentData;
          _notifyListeners(currentData);
        }
      } catch (e) {
        // Ignore monitoring errors
      }
    });
    _isMonitoring = true;
  }

  /// Stop monitoring clipboard changes
  static Future<void> stopMonitoring() async {
    _isMonitoring = false;
    _monitoringTimer?.cancel();
    _monitoringTimer = null;
    await _clipboardChangeSubscription?.cancel();
    _clipboardChangeSubscription = null;
    try {
      await _channel.invokeMethod<bool>('stopMonitoring');
    } catch (e) {
      // Ignore errors when stopping
    }
  }

  /// Get debug information
  static Future<Map<String, dynamic>> getDebugInfo() async {
    try {
      final hasData = await FlutterClipboard.hasData();
      final contentType = await FlutterClipboard.getContentType();
      final dataSize = await FlutterClipboard.getDataSize();

      return {
        'hasData': hasData,
        'contentType': contentType.toString(),
        'dataSize': dataSize,
        'listenersCount': _listeners.length,
        'isMonitoring': _isMonitoring,
        'lastData': _lastData?.text,
        'hasNativeMonitoring': _clipboardChangeSubscription != null,
      };
    } catch (e) {
      return {
        'error': e.toString(),
        'listenersCount': _listeners.length,
        'isMonitoring': _isMonitoring,
      };
    }
  }

  /// Set mock data for testing
  static Future<void> setMockData(String text) async {
    _lastData = EnhancedClipboardData(text: text);
    _notifyListeners(_lastData!);
  }

  // Legacy methods for backward compatibility
  /// controlC receives a string text and saves to Clipboard
  /// returns boolean value
  static Future<bool> controlC(String text) async {
    try {
      await copy(text);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// controlV retrieves the data from clipboard.
  /// same as paste
  /// But returns dynamic data
  static Future<dynamic> controlV() async {
    try {
      return await pasteRichText();
    } catch (e) {
      return null;
    }
  }

  // Private helper methods
  static void _notifyListeners(EnhancedClipboardData data) {
    final listeners = List<Function(EnhancedClipboardData)>.from(_listeners);
    for (final listener in listeners) {
      try {
        listener(data);
      } catch (e) {
        // Ignore listener errors but log in debug mode
        if (kDebugMode) {
          print('Clipboard listener error: $e');
        }
      }
    }
  }
}
