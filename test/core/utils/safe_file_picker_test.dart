import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/utils/safe_file_picker.dart';
import 'package:localmind/l10n/app_localizations_en.dart';

void main() {
  final l10n = AppLocalizationsEn();

  group('SafeFilePicker.isExplorerNotFoundError', () {
    test('identifies PlatformException with explorer_not_found code', () {
      final error = PlatformException(
        code: 'explorer_not_found',
        message:
            "Can't find a valid activity to handle the request. Make sure you have a file explorer installed.",
      );
      expect(SafeFilePicker.isExplorerNotFoundError(error), isTrue);
    });

    test('identifies PlatformException with activity not found message', () {
      final error = PlatformException(
        code: 'error',
        message: "Can't find a valid activity to handle the request.",
      );
      expect(SafeFilePicker.isExplorerNotFoundError(error), isTrue);
    });

    test('identifies generic string containing explorer_not_found', () {
      final error = Exception('PlatformException(explorer_not_found, ...)');
      expect(SafeFilePicker.isExplorerNotFoundError(error), isTrue);
    });

    test('returns false for unrelated errors', () {
      final error = PlatformException(
        code: 'permission_denied',
        message: 'Permission was denied by the user',
      );
      expect(SafeFilePicker.isExplorerNotFoundError(error), isFalse);

      final socketError = const SocketException('Connection reset');
      expect(SafeFilePicker.isExplorerNotFoundError(socketError), isFalse);
    });
  });

  group('SafeFilePicker.getErrorMessage', () {
    test('returns localized file_explorer_not_found for explorer errors', () {
      final error = PlatformException(
        code: 'explorer_not_found',
        message: "Can't find a valid activity to handle the request.",
      );
      expect(
        SafeFilePicker.getErrorMessage(error, l10n),
        l10n.file_explorer_not_found,
      );
    });

    test('returns clean platform exception message for other codes', () {
      final error = PlatformException(
        code: 'read_error',
        message: 'Unable to read file content',
      );
      expect(
        SafeFilePicker.getErrorMessage(error, l10n),
        'Unable to read file content',
      );
    });

    test('returns clean message for FileSystemException', () {
      final error = const FileSystemException('File is corrupted');
      expect(
        SafeFilePicker.getErrorMessage(error, l10n),
        'File is corrupted',
      );
    });

    test('strips Exception prefix for standard exceptions', () {
      final error = Exception('Failed to parse backup');
      expect(
        SafeFilePicker.getErrorMessage(error, l10n),
        'Failed to parse backup',
      );
    });
  });

  group('SafeFilePicker method channel error catching', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    test('pickFiles catches PlatformException and returns null', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('miguelruivo.flutter.plugins.filepicker'),
        (MethodCall methodCall) async {
          throw PlatformException(
            code: 'explorer_not_found',
            message: "Can't find a valid activity to handle the request.",
          );
        },
      );

      final result = await SafeFilePicker.pickFiles();
      expect(result, isNull);
    });

    test('saveFile catches PlatformException and returns null', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('miguelruivo.flutter.plugins.filepicker'),
        (MethodCall methodCall) async {
          throw PlatformException(
            code: 'explorer_not_found',
            message: "Can't find a valid activity to handle the request.",
          );
        },
      );

      final result = await SafeFilePicker.saveFile(
        dialogTitle: 'Save File',
        fileName: 'test.json',
      );
      expect(result, isNull);
    });

    test('getDirectoryPath catches PlatformException and returns null', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('miguelruivo.flutter.plugins.filepicker'),
        (MethodCall methodCall) async {
          throw PlatformException(
            code: 'explorer_not_found',
            message: "Can't find a valid activity to handle the request.",
          );
        },
      );

      final result = await SafeFilePicker.getDirectoryPath();
      expect(result, isNull);
    });

    test('pickFiles returns result when platform succeeds', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('miguelruivo.flutter.plugins.filepicker'),
        (MethodCall methodCall) async {
          return [
            {
              'path': '/path/to/file.txt',
              'name': 'file.txt',
              'size': 123,
              'bytes': null,
              'identifier': null,
            }
          ];
        },
      );

      final result = await SafeFilePicker.pickFiles();
      expect(result, isNotNull);
      expect(result!.files.first.name, 'file.txt');
    });
  });
}

