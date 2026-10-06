import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/core/providers/storage_providers.dart';
import 'package:localmind/features/models/data/model_vision_overrides.dart';
import 'package:localmind/features/models/data/models/model_info.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late ProviderContainer container;
  late ModelInfo plainModel;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    plainModel = ModelInfo(
      id: 'GLM-5.3-Flash-NVFP4',
      name: 'GLM 5.3 Flash',
      serverType: ServerType.openAICompatible,
      serverId: 'rig-vllm',
      supportsVision: false,
    );
    container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
  });

  tearDown(() {
    container.dispose();
  });

  test('a fresh install starts with no overrides', () {
    expect(container.read(modelVisionOverridesProvider), isEmpty);
  });

  test('setVision stores the override reactively and persistently', () async {
    await container
        .read(modelVisionOverridesProvider.notifier)
        .setVision('rig-vllm', plainModel.id, true);

    final key = ModelVisionOverridesNotifier.key('rig-vllm', plainModel.id);
    expect(container.read(modelVisionOverridesProvider)[key], isTrue);

    // Persisted: a fresh provider build (restart) reads it back.
    final fresh = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
      ],
    );
    addTearDown(fresh.dispose);
    expect(fresh.read(modelVisionOverridesProvider)[key], isTrue);

    // Clearing removes it and persists the removal.
    await container
        .read(modelVisionOverridesProvider.notifier)
        .setVision('rig-vllm', plainModel.id, null);
    expect(container.read(modelVisionOverridesProvider), isEmpty);
    expect(prefs.getString('modelVisionOverrides'), '{}');
  });

  test('applyVisionOverride merges server-declared and forced vision', () {
    final overrides = {
      ModelVisionOverridesNotifier.key('rig-vllm', plainModel.id): true,
    };

    final upgraded = applyVisionOverride(plainModel, overrides);
    expect(upgraded.supportsVision, isTrue);

    // The override must not mutate the input model.
    expect(plainModel.supportsVision, isFalse);

    // An override matching the server-reported value changes nothing.
    final declared = applyVisionOverride(
      plainModel.copyWith(supportsVision: true),
      overrides,
    );
    expect(declared.supportsVision, isTrue);

    // No override is the identity.
    expect(applyVisionOverride(plainModel, const {}), same(plainModel));
  });

  test('applyVisionOverride can force vision OFF for heuristic models', () {
    final overrides = {
      ModelVisionOverridesNotifier.key('rig-vllm', 'gemma3-4b'): false,
    };
    final downgraded = applyVisionOverride(
      plainModel.copyWith(id: 'gemma3-4b', supportsVision: true),
      overrides,
    );
    expect(downgraded.supportsVision, isFalse);
  });
}
