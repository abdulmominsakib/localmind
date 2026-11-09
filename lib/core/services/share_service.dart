import 'dart:io';
import 'dart:ui';

import 'package:share_plus/share_plus.dart';

class ShareService {
  ShareService._();

  static Future<void> shareFiles(List<String> paths, {Rect? origin}) async {
    final files = [
      for (final path in paths)
        if (await File(path).exists()) XFile(path),
    ];
    if (files.isEmpty) return;
    await SharePlus.instance.share(
      ShareParams(files: files, sharePositionOrigin: origin),
    );
  }

  static Future<void> shareText(String text, {String? subject}) async {
    if (text.trim().isEmpty) return;
    await SharePlus.instance.share(
      ShareParams(
        text: text,
        subject: subject,
        // Avoid download/mail fallbacks that can trap the user in-app on Android.
        downloadFallbackEnabled: false,
        mailToFallbackEnabled: false,
      ),
    );
  }
}
