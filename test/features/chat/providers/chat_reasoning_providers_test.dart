import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/features/chat/providers/chat_reasoning_providers.dart';
import 'package:localmind/features/models/data/models/model_info.dart';
import 'package:localmind/core/models/enums.dart';

void main() {
  group('effortsForModel', () {
    test('falls back to low/medium/high when efforts are unknown', () {
      expect(effortsForModel(null), [
        ReasoningEffort.low,
        ReasoningEffort.medium,
        ReasoningEffort.high,
      ]);
      expect(effortsForModel(const []), [
        ReasoningEffort.low,
        ReasoningEffort.medium,
        ReasoningEffort.high,
      ]);
    });

    test('filters and orders advertised efforts lightest to heaviest', () {
      expect(effortsForModel(const ['max', 'high', 'low']), [
        ReasoningEffort.low,
        ReasoningEffort.high,
        ReasoningEffort.max,
      ]);
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
      expect(effortsForModel(const ['bogus']), [
        ReasoningEffort.low,
        ReasoningEffort.medium,
        ReasoningEffort.high,
      ]);
    });

    test('binary on/off models yield a single placeholder', () {
      expect(effortsForModel(const ['off', 'on']), [ReasoningEffort.medium]);
      expect(effortsForModel(const ['ON', 'OFF']), [ReasoningEffort.medium]);
    });

    test('filters off/on out of granular lists', () {
      expect(effortsForModel(const ['off', 'low', 'medium', 'on']), [
        ReasoningEffort.low,
        ReasoningEffort.medium,
      ]);
    });
  });

  group('hasGranularReasoningChoice', () {
    test('true for unknown and granular lists', () {
      expect(hasGranularReasoningChoice(null), isTrue);
      expect(hasGranularReasoningChoice(const []), isTrue);
      expect(
        hasGranularReasoningChoice(const ['low', 'medium', 'high', 'xhigh']),
        isTrue,
      );
    });

    test('false for binary on/off lists', () {
      expect(hasGranularReasoningChoice(const ['off', 'on']), isFalse);
      expect(hasGranularReasoningChoice(const ['on']), isFalse);
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
      expect(
        resolveEffortForModel(null, ReasoningEffort.low),
        ReasoningEffort.low,
      );
      expect(
        resolveEffortForModel(modelWithEfforts(const []), ReasoningEffort.high),
        ReasoningEffort.high,
      );
    });

    test('keeps current when it is supported', () {
      final model = modelWithEfforts(const [
        'max',
        'high',
        'low',
      ], defaultEffort: 'high');
      expect(
        resolveEffortForModel(model, ReasoningEffort.high),
        ReasoningEffort.high,
      );
    });

    test('snaps to the advertised default when current is unsupported', () {
      final model = modelWithEfforts(const ['high'], defaultEffort: 'high');
      expect(
        resolveEffortForModel(model, ReasoningEffort.low),
        ReasoningEffort.high,
      );
    });

    test(
      'picks the heaviest supported effort when no default is advertised',
      () {
        final model = modelWithEfforts(const ['high', 'max']);
        expect(
          resolveEffortForModel(model, ReasoningEffort.low),
          ReasoningEffort.max,
        );
      },
    );

    test('keeps current for binary on/off models', () {
      final model = modelWithEfforts(const ['off', 'on']);
      expect(
        resolveEffortForModel(model, ReasoningEffort.low),
        ReasoningEffort.low,
      );
    });

    test('matches case-insensitively for LM Studio caps', () {
      final model = modelWithEfforts(const ['Low', 'Medium']);
      expect(
        resolveEffortForModel(model, ReasoningEffort.low),
        ReasoningEffort.low,
      );
    });
  });

  group('resolveLmStudioReasoningValue', () {
    test('omits when reasoning is unsupported', () {
      expect(
        resolveLmStudioReasoningValue(
          enabled: null,
          effort: ReasoningEffort.low,
        ),
        isNull,
      );
    });

    test('legacy null caps send effort or off', () {
      expect(
        resolveLmStudioReasoningValue(
          enabled: true,
          effort: ReasoningEffort.medium,
        ),
        'medium',
      );
      expect(
        resolveLmStudioReasoningValue(
          enabled: false,
          effort: ReasoningEffort.low,
        ),
        'off',
      );
    });

    test('omits off when the model does not advertise it (glimmer)', () {
      expect(
        resolveLmStudioReasoningValue(
          enabled: false,
          effort: ReasoningEffort.low,
          allowedOptions: const ['low', 'medium', 'high', 'xhigh'],
          defaultOption: 'medium',
        ),
        isNull,
      );
      expect(
        resolveLmStudioReasoningValue(
          enabled: true,
          effort: ReasoningEffort.medium,
          allowedOptions: const ['low', 'medium', 'high', 'xhigh'],
        ),
        'medium',
      );
    });

    test('binary models send literal on/off', () {
      expect(
        resolveLmStudioReasoningValue(
          enabled: true,
          effort: ReasoningEffort.low,
          allowedOptions: const ['off', 'on'],
          defaultOption: 'on',
        ),
        'on',
      );
      expect(
        resolveLmStudioReasoningValue(
          enabled: false,
          effort: ReasoningEffort.low,
          allowedOptions: const ['off', 'on'],
        ),
        'off',
      );
    });

    test('snaps minimal/max to the LM Studio range', () {
      expect(
        resolveLmStudioReasoningValue(
          enabled: true,
          effort: ReasoningEffort.minimal,
        ),
        'low',
      );
      expect(
        resolveLmStudioReasoningValue(
          enabled: true,
          effort: ReasoningEffort.max,
        ),
        'xhigh',
      );
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
