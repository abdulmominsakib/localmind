import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/features/on_device/data/models/on_device_model.dart';
import 'package:localmind/features/on_device/providers/on_device_providers.dart';

void main() {
  group('BuiltIn AI OnDeviceModel definitions', () {
    test('geminiNanoBuiltIn has correct metadata', () {
      const model = OnDeviceModel.geminiNanoBuiltIn;
      expect(model.id, 'gemini-nano');
      expect(model.name, 'Gemini Nano (System AI)');
      expect(model.isBuiltIn, isTrue);
      expect(model.format, OnDeviceModelFormat.builtIn);
      expect(model.runtime, OnDeviceModelRuntime.gemma);
      expect(model.fileSizeBytes, 0);
      expect(model.fileSizeFormatted, 'Built-in');
      expect(model.fileName, 'gemini-nano');
      expect(model.supportsVision, isTrue);
      expect(model.supportsFunctionCalling, isTrue);
    });

    test('appleFoundationModelsBuiltIn has correct metadata', () {
      const model = OnDeviceModel.appleFoundationModelsBuiltIn;
      expect(model.id, 'apple-foundation-models');
      expect(model.name, 'Apple Foundation Models');
      expect(model.isBuiltIn, isTrue);
      expect(model.format, OnDeviceModelFormat.builtIn);
      expect(model.runtime, OnDeviceModelRuntime.gemma);
      expect(model.fileSizeBytes, 0);
      expect(model.fileSizeFormatted, 'Built-in');
      expect(model.fileName, 'apple-foundation-models');
      expect(model.supportsFunctionCalling, isTrue);
    });

    test('allCuratedModels includes built-in models at the start', () {
      final all = OnDeviceModel.allCuratedModels;
      expect(all, contains(OnDeviceModel.geminiNanoBuiltIn));
      expect(all, contains(OnDeviceModel.appleFoundationModelsBuiltIn));
      expect(all.first, OnDeviceModel.geminiNanoBuiltIn);
      expect(all[1], OnDeviceModel.appleFoundationModelsBuiltIn);
    });

    test('availableCuratedBuiltInModels filters by platform', () {
      final androidModels = availableCuratedBuiltInModels(
        isAndroid: true,
        isIOS: false,
        isMacOS: false,
        isWeb: false,
      );
      expect(androidModels, [OnDeviceModel.geminiNanoBuiltIn]);

      final iosModels = availableCuratedBuiltInModels(
        isAndroid: false,
        isIOS: true,
        isMacOS: false,
        isWeb: false,
      );
      expect(iosModels, [OnDeviceModel.appleFoundationModelsBuiltIn]);

      final macosModels = availableCuratedBuiltInModels(
        isAndroid: false,
        isIOS: false,
        isMacOS: true,
        isWeb: false,
      );
      expect(macosModels, [OnDeviceModel.appleFoundationModelsBuiltIn]);

      final webModels = availableCuratedBuiltInModels(
        isAndroid: false,
        isIOS: false,
        isMacOS: false,
        isWeb: true,
      );
      expect(webModels, [OnDeviceModel.geminiNanoBuiltIn]);
    });
  });
}
