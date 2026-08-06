import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/features/chat/providers/chat_reasoning_providers.dart';
import 'package:localmind/features/models/data/models/model_info.dart';
import 'package:localmind/core/models/enums.dart';

void main() {
  group('effortsForModel', () {
    test('falls back to low/medium/high when efforts are unknown', () {
      expect(effortsForModel(null), [ReasoningEffort.low, ReasoningEffort.medium, ReasoningEffort.high]);
      expect(effortsForModel(const []), [ReasoningEffort.low, ReasoningEffort.medium, ReasoningEffort.high]);
    });

    test('filters and orders advertised efforts lightest to heaviest', () {
      expect(
        effortsForModel(const ['max', 'high', 'low']),
        [ReasoningEffort.low, ReasoningEffort.high, ReasoningEffort.max],
      );
      expect(
        effortsForModel(const ['xhigh', 'high', 'medium', 'low', 'minimal']),
        [
          ReasoningEffort.minimal,
          ReasoningEffort.low,
          ReasoningEffort.medium,
          ReasoningEffort.high,
          ReasoningEffort.xhigh,
        ],
      );
    });

    test('falls back when no advertised effort maps to the enum', () {
      expect(
        effortsForModel(const ['bogus']),
        [ReasoningEffort.low, ReasoningEffort.medium, ReasoningEffort.high],
      );
    });
  });

  group('resolveEffortForModel', () {
    ModelInfo modelWithEfforts(List<String> efforts, {String? defaultEffort}) {
      return ModelInfo(
        id: 'm',
        name: 'M',
        serverType: ServerType.openRouter,
        serverId: 's',
        supportedReasoningEfforts: efforts,
        defaultReasoningEffort: defaultEffort,
      );
    }

    test('returns current unchanged when no efforts are advertised', () {
      expect(resolveEffortForModel(null, ReasoningEffort.low), ReasoningEffort.low);
      expect(
        resolveEffortForModel(modelWithEfforts(const []), ReasoningEffort.high),
        ReasoningEffort.high,
      );
    });

    test('keeps current when it is supported', () {
      final model = modelWithEfforts(const ['max', 'high', 'low'], defaultEffort: 'high');
      expect(resolveEffortForModel(model, ReasoningEffort.high), ReasoningEffort.high);
    });

    test('snaps to the advertised default when current is unsupported', () {
      final model = modelWithEfforts(const ['high'], defaultEffort: 'high');
      expect(resolveEffortForModel(model, ReasoningEffort.low), ReasoningEffort.high);
    });

    test('picks the heaviest supported effort when no default is advertised', () {
      final model = modelWithEfforts(const ['high', 'max']);
      expect(resolveEffortForModel(model, ReasoningEffort.low), ReasoningEffort.max);
    });
  });

  group('ReasoningEffort.fromApiValue', () {
    test('maps known values', () {
      expect(ReasoningEffort.fromApiValue('minimal'), ReasoningEffort.minimal);
      expect(ReasoningEffort.fromApiValue('max'), ReasoningEffort.max);
      expect(ReasoningEffort.fromApiValue('xhigh'), ReasoningEffort.xhigh);
    });

    test('falls back to medium for unknown values', () {
      expect(ReasoningEffort.fromApiValue('bogus'), ReasoningEffort.medium);
    });
  });
}
