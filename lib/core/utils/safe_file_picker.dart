// ignore_for_file: deprecated_member_use
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../l10n/app_localizations.dart';
import '../logger/app_logger.dart';

/// Safe wrapper around [FilePicker] and [ImagePicker] platform operations.
///
/// Prevents unhandled [PlatformException]s (e.g. `explorer_not_found` on Android)
/// from crashing the app when no default file manager or gallery is available.
class SafeFilePicker {
  SafeFilePicker._();

  /// Determines whether an error is caused by a missing/disabled file manager activity.
  static bool isExplorerNotFoundError(Object error) {
    if (error is PlatformException) {
      if (error.code == 'explorer_not_found') return true;
      final msg = error.message?.toLowerCase() ?? '';
      if (msg.contains('explorer') ||
          msg.contains('activity to handle the request') ||
          msg.contains('no activity found to handle intent') ||
          msg.contains('file explorer installed')) {
        return true;
      }
    }
    final str = error.toString().toLowerCase();
    return str.contains('explorer_not_found') ||
        str.contains('can\'t find a valid activity') ||
        str.contains('file explorer installed');
  }

  /// Extracts a localized, user-friendly error message from [error].
  static String getErrorMessage(
    Object error,
    AppLocalizations l10n, {
    String? fallbackMessage,
  }) {
    if (isExplorerNotFoundError(error)) {
      return l10n.file_explorer_not_found;
    }
    if (error is PlatformException) {
      if (error.message != null && error.message!.trim().isNotEmpty) {
        return error.message!.trim();
      }
    }
    if (error is FileSystemException) {
      return error.message.isNotEmpty ? error.message : error.toString();
    }
    final message = error
        .toString()
        .replaceFirst(RegExp(r'^([A-Za-z0-9_]+Exception|Exception):\s*'), '')
        .trim();
    if (message.isNotEmpty) {
      return message;
    }
    return fallbackMessage ?? error.toString();
  }

  /// Safely picks files using [FilePicker.platform.pickFiles].
  ///
  /// Catches [PlatformException] and other errors, logs them, and optionally
  /// displays a user-friendly [SnackBar] if [context] is provided.
  static Future<FilePickerResult?> pickFiles({
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    String? dialogTitle,
    String? initialDirectory,
    dynamic lockParentWindow,
    Function(FilePickerStatus)? onFileLoading,
    BuildContext? context,
    void Function(String message)? onError,
  }) async {
    try {
      return await FilePicker.pickFiles(
        type: type,
        allowedExtensions: allowedExtensions,
        allowMultiple: allowMultiple,
        withData: withData,
        withReadStream: withReadStream,
        dialogTitle: dialogTitle,
        initialDirectory: initialDirectory,
        lockParentWindow: lockParentWindow,
        onFileLoading: onFileLoading,
      );
    } catch (e, st) {
      Log.warning('SafeFilePicker.pickFiles failed: $e\n$st');
      if (context != null && context.mounted) {
        final l10n = AppLocalizations.of(context);
        if (l10n != null) {
          final msg = getErrorMessage(e, l10n);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg)),
          );
        }
      } else if (onError != null) {
        onError(e.toString());
      }
      return null;
    }
  }

  /// Safely opens a save file dialog using [FilePicker.saveFile].
  static Future<String?> saveFile({
    String? dialogTitle,
    required String fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    dynamic lockParentWindow,
    BuildContext? context,
    void Function(String message)? onError,
  }) async {
    try {
      return await FilePicker.saveFile(
        dialogTitle: dialogTitle,
        fileName: fileName,
        initialDirectory: initialDirectory,
        type: type,
        allowedExtensions: allowedExtensions,
        bytes: bytes ?? Uint8List(0),
        lockParentWindow: lockParentWindow,
      );
    } catch (e, st) {
      Log.warning('SafeFilePicker.saveFile failed: $e\n$st');
      if (context != null && context.mounted) {
        final l10n = AppLocalizations.of(context);
        if (l10n != null) {
          final msg = getErrorMessage(e, l10n);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg)),
          );
        }
      } else if (onError != null) {
        onError(e.toString());
      }
      return null;
    }
  }

  /// Safely gets a directory path using [FilePicker.getDirectoryPath].
  static Future<String?> getDirectoryPath({
    String? dialogTitle,
    String? initialDirectory,
    dynamic lockParentWindow,
    BuildContext? context,
    void Function(String message)? onError,
  }) async {
    try {
      return await FilePicker.getDirectoryPath(
        dialogTitle: dialogTitle,
        initialDirectory: initialDirectory,
        lockParentWindow: lockParentWindow,
      );
    } catch (e, st) {
      Log.warning('SafeFilePicker.getDirectoryPath failed: $e\n$st');
      if (context != null && context.mounted) {
        final l10n = AppLocalizations.of(context);
        if (l10n != null) {
          final msg = getErrorMessage(e, l10n);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg)),
          );
        }
      } else if (onError != null) {
        onError(e.toString());
      }
      return null;
    }
  }

  /// Safely picks multiple images using [ImagePicker.pickMultiImage].
  static Future<List<XFile>> pickMultiImage({
    int? imageQuality,
    double? maxWidth,
    double? maxHeight,
    bool requestFullMetadata = true,
    BuildContext? context,
    void Function(String message)? onError,
  }) async {
    try {
      final picker = ImagePicker();
      return await picker.pickMultiImage(
        imageQuality: imageQuality,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        requestFullMetadata: requestFullMetadata,
      );
    } catch (e, st) {
      Log.warning('SafeFilePicker.pickMultiImage failed: $e\n$st');
      if (context != null && context.mounted) {
        final l10n = AppLocalizations.of(context);
        if (l10n != null) {
          final msg = getErrorMessage(e, l10n);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg)),
          );
        }
      } else if (onError != null) {
        onError(e.toString());
      }
      return const [];
    }
  }

  /// Safely picks a single image using [ImagePicker.pickImage].
  static Future<XFile?> pickImage({
    required ImageSource source,
    int? imageQuality,
    double? maxWidth,
    double? maxHeight,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
    BuildContext? context,
    void Function(String message)? onError,
  }) async {
    try {
      final picker = ImagePicker();
      return await picker.pickImage(
        source: source,
        imageQuality: imageQuality,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        preferredCameraDevice: preferredCameraDevice,
        requestFullMetadata: requestFullMetadata,
      );
    } catch (e, st) {
      Log.warning('SafeFilePicker.pickImage failed: $e\n$st');
      if (context != null && context.mounted) {
        final l10n = AppLocalizations.of(context);
        if (l10n != null) {
          final msg = getErrorMessage(e, l10n);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg)),
          );
        }
      } else if (onError != null) {
        onError(e.toString());
      }
      return null;
    }
  }
}
