import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/features/models/data/models/model_info.dart';
import 'package:localmind/features/models/providers/model_picker_providers.dart';
import 'package:localmind/features/models/utils/model_sort_utils.dart';

ModelInfo _model(String id, String name) => ModelInfo(
  id: id,
  name: name,
  serverType: ServerType.standardCompute,
  serverId: 'standard-compute-1',
);

void main() {
  final models = [
    _model('anthropic/claude-sonnet-5.5', 'Claude Sonnet 5.5'),
    _model('z-ai/glm-5.3', 'GLM 5.3'),
    _model('StandardCompute', 'Standard Compute'),
    _model('deepseek/deepseek-v4-flash', 'DeepSeek V4 Flash'),
  ];

  List<String> ids(List<ModelInfo> sorted) =>
      sorted.map((model) => model.id).toList();

  test('default picker order lists the router first without favorites', () {
    final sorted = sortPickerModels(
      models,
      ModelSortOption.favorites,
      isFavorite: (_) => false,
    );

    expect(ids(sorted), [
      'StandardCompute',
      'anthropic/claude-sonnet-5.5',
      'deepseek/deepseek-v4-flash',
      'z-ai/glm-5.3',
    ]);
  });

  test('favorites stay ahead of the router in the default order', () {
    final sorted = sortPickerModels(
      models,
      ModelSortOption.favorites,
      isFavorite: (model) => model.id == 'z-ai/glm-5.3',
    );

    expect(ids(sorted).take(2), ['z-ai/glm-5.3', 'StandardCompute']);
  });

  test('the router id from another provider gets no priority', () {
    final other = ModelInfo(
      id: 'StandardCompute',
      name: 'Standard Compute',
      serverType: ServerType.openAICompatible,
      serverId: 'custom-1',
    );

    expect(isRouterModel(other), isFalse);
  });

  test('name sort keeps plain alphabetical order', () {
    final sorted = sortPickerModels(
      models,
      ModelSortOption.nameAsc,
      isFavorite: (_) => false,
    );

    expect(ids(sorted).last, 'StandardCompute');
  });
}
