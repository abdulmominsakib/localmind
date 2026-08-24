import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/features/os_widget/data/models/os_widget_models.dart';
import 'package:localmind/features/os_widget/data/os_widget_service.dart';

void main() {
  group('OsWidgetInvocation', () {
    test('parses chat action with prompt', () {
      final uri = Uri.parse('localmind://widget?action=chat&prompt=Hello%20AI');
      final invocation = OsWidgetInvocation.fromUri(uri);

      expect(invocation.action, OsWidgetAction.chat);
      expect(invocation.prompt, 'Hello AI');
      expect(invocation.uri, uri);
    });

    test('parses text query parameter as prompt fallback', () {
      final uri = Uri.parse(
        'localmind://widget?action=chat&text=Explain%20quantum',
      );
      final invocation = OsWidgetInvocation.fromUri(uri);

      expect(invocation.action, OsWidgetAction.chat);
      expect(invocation.prompt, 'Explain quantum');
    });

    test('parses new_chat action', () {
      final uri = Uri.parse('localmind://widget?action=new_chat');
      final invocation = OsWidgetInvocation.fromUri(uri);

      expect(invocation.action, OsWidgetAction.newChat);
      expect(invocation.prompt, isNull);
    });

    test('parses voice action', () {
      final uri = Uri.parse('localmind://widget?action=voice');
      final invocation = OsWidgetInvocation.fromUri(uri);

      expect(invocation.action, OsWidgetAction.voice);
      expect(invocation.prompt, isNull);
    });

    test('defaults to chat action for unknown or unspecified action', () {
      final uri = Uri.parse('localmind://widget');
      final invocation = OsWidgetInvocation.fromUri(uri);

      expect(invocation.action, OsWidgetAction.chat);
      expect(invocation.prompt, isNull);
    });
  });

  group('OsWidgetService', () {
    test('dispatches invocations through stream', () async {
      final service = OsWidgetService(isSupportedOverride: true);
      final emitted = <OsWidgetInvocation>[];
      final sub = service.invocations.listen(emitted.add);

      final inv1 = OsWidgetInvocation(
        action: OsWidgetAction.chat,
        prompt: 'Test Prompt',
      );
      final inv2 = OsWidgetInvocation(action: OsWidgetAction.voice);

      service.dispatchInvocation(inv1);
      service.dispatchInvocation(inv2);

      await Future<void>.delayed(Duration.zero);

      expect(emitted.length, 2);
      expect(emitted[0].action, OsWidgetAction.chat);
      expect(emitted[0].prompt, 'Test Prompt');
      expect(emitted[1].action, OsWidgetAction.voice);

      await sub.cancel();
      await service.dispose();
    });
  });
}
