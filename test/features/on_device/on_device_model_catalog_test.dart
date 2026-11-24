import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/features/on_device/data/models/on_device_model.dart';

void main() {
  group('OnDeviceModel curated catalog', () {
    test('contains every requested model row with unique ids', () {
      const expectedIds = {
        'gemma4-e2b-instruct',
        'gemma4-e4b-instruct',
        'gemma3n-e2b-instruct',
        'fastvlm-0.5b',
        'phi-4-mini-instruct',
        'deepseek-r1-distill-qwen-1.5b',
        'qwen3-0.6b',
        'qwen2.5-1.5b-instruct',
        'gemma3-1b-it',
        'gemma3-270m-it',
        'functiongemma-270m',
        'smollm2-135m-instruct',
        'translategemma-4b-it',
      };

      final ids = OnDeviceModel.curatedModels.map((model) => model.id).toSet();

      expect(ids, containsAll(expectedIds));
      expect(ids.length, OnDeviceModel.curatedModels.length);
    });

    test('uses concrete downloadable LiteRT-LM bundle urls', () {
      for (final model in OnDeviceModel.curatedModels) {
        expect(model.huggingFaceUrl, startsWith('https://huggingface.co/'));
        expect(
          model.huggingFaceUrl,
          endsWith('.litertlm'),
          reason:
              '${model.id} must stay compatible with flutter_edge_ai_litertlm',
        );
        expect(model.fileName, isNotEmpty);
        expect(model.fileName, isNot(contains('/')));
      }
    });

    test(
      'maps models with specialized chat formats to explicit model types',
      () {
        final byId = {
          for (final model in OnDeviceModel.curatedModels) model.id: model,
        };

        expect(
          byId['gemma4-e2b-instruct']!.flutterGemmaModelType,
          ModelType.gemma4,
        );
        expect(
          byId['gemma4-e4b-instruct']!.flutterGemmaModelType,
          ModelType.gemma4,
        );
        expect(byId['qwen3-0.6b']!.flutterGemmaModelType, ModelType.qwen3);
        expect(
          byId['qwen2.5-1.5b-instruct']!.flutterGemmaModelType,
          ModelType.qwen,
        );
        expect(
          byId['deepseek-r1-distill-qwen-1.5b']!.flutterGemmaModelType,
          ModelType.deepSeek,
        );
        expect(
          byId['phi-4-mini-instruct']!.flutterGemmaModelType,
          ModelType.phi,
        );
        expect(
          byId['functiongemma-270m']!.flutterGemmaModelType,
          ModelType.functionGemma,
        );
      },
    );

    test('marks TranslateGemma as CPU-only', () {
      final translateGemma = OnDeviceModel.curatedModels.singleWhere(
        (model) => model.id == 'translategemma-4b-it',
      );

      expect(translateGemma.isCpuOnly, isTrue);
      expect(translateGemma.backendNote, 'CPU-only');
      expect(translateGemma.languagesLabel, '55 languages');
    });
  });
}
