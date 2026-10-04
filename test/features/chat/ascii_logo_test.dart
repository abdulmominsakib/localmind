import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/features/chat/utils/ascii_logo.dart';
import 'package:localmind/features/chat/utils/ascii_logo_data.dart';
import 'package:localmind/features/chat/utils/new_chat_presence.dart';

void main() {
  group('asciiLogoFrame', () {
    for (final logo in AsciiLogo.values) {
      test('${logo.name} keeps a fixed grid on every tick', () {
        for (final tick in [null, 0, 5, 15, 16, 40, 200, 1000]) {
          final frame = asciiLogoFrame(logo, tick);
          for (final layer in [frame.base, frame.highlight]) {
            expect(layer, hasLength(asciiLogoRows));
            expect(
              layer.every((row) => row.length == asciiLogoColumns),
              isTrue,
              reason: '${logo.name} at tick $tick',
            );
          }
        }
      });
    }

    test('the still frame is the mask with nothing highlighted', () {
      for (final logo in AsciiLogo.values) {
        final frame = asciiLogoFrame(logo, null);
        expect(frame.base, asciiLogoMask(logo));
        expect(frame.highlight.join().trim(), isEmpty);
      }
    });

    test('the reveal scrambles the logo, then settles on it', () {
      final mask = asciiLogoMask(AsciiLogo.ollama);
      expect(asciiLogoFrame(AsciiLogo.ollama, 0).base, isNot(mask));
      // Tick 3 of the loop is past the blink, so the llama is at rest.
      expect(
        asciiLogoFrame(AsciiLogo.ollama, asciiLogoIntroTicks + 3).base,
        mask,
      );
    });

    test('the reveal only touches inked cells', () {
      final mask = asciiLogoMask(AsciiLogo.openRouter);
      final frame = asciiLogoFrame(AsciiLogo.openRouter, 2);
      for (var r = 0; r < asciiLogoRows; r++) {
        for (var c = 0; c < asciiLogoColumns; c++) {
          if (mask[r][c] == ' ') expect(frame.base[r][c], ' ');
        }
      }
    });

    test('the llama blinks', () {
      final blink = asciiLogoFrame(AsciiLogo.ollama, asciiLogoIntroTicks);
      for (final (r, c, glyph) in ollamaBlink) {
        expect(blink.base[r][c], glyph);
      }
      expect(blink.base, isNot(asciiLogoMask(AsciiLogo.ollama)));
    });

    test('every animation stays inside the grid', () {
      for (final (r, c, _) in ollamaBlink) {
        expect(r < asciiLogoRows && c < asciiLogoColumns, isTrue);
      }
      for (final (r, c) in [...requestyCursor, ...serverLights]) {
        expect(r < asciiLogoRows && c < asciiLogoColumns, isTrue);
      }
      expect(lmStudioBarOfRow, hasLength(asciiLogoRows));
    });

    test('the Requesty cursor blinks', () {
      final on = asciiLogoFrame(AsciiLogo.requesty, asciiLogoIntroTicks);
      final off = asciiLogoFrame(AsciiLogo.requesty, asciiLogoIntroTicks + 6);
      expect(on.base, asciiLogoMask(AsciiLogo.requesty));
      expect(off.base, isNot(on.base));
    });
  });

  group('NewChatPresence', () {
    test('Ollama Cloud is cloud, not local', () {
      final presence = NewChatPresence.forServerType(ServerType.ollamaCloud);
      expect(presence.reach, NewChatReach.cloud);
      expect(presence.logo, AsciiLogo.ollama);
    });

    test('maps each server type to where messages go', () {
      final reach = {
        for (final type in ServerType.values)
          type: NewChatPresence.forServerType(type).reach,
      };
      expect(reach, {
        ServerType.lmStudio: NewChatReach.selfHosted,
        ServerType.openAICompatible: NewChatReach.endpoint,
        ServerType.ollama: NewChatReach.selfHosted,
        ServerType.ollamaCloud: NewChatReach.cloud,
        ServerType.openRouter: NewChatReach.cloud,
        ServerType.onDevice: NewChatReach.onDevice,
        ServerType.requesty: NewChatReach.cloud,
      });
      expect(NewChatPresence.forServerType(null).reach, NewChatReach.none);
    });
  });
}
