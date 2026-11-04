@TestOn('vm')
library;

import 'package:llamadart/src/backends/litert_lm/litert_lm_runtime.dart';
import 'package:test/test.dart';

void main() {
  group('LiteRtLmChannelAssembler', () {
    test('wraps a thought run in Gemma 4 channel markers, then content', () {
      final assembler = LiteRtLmChannelAssembler();
      final out = StringBuffer()
        ..write(
          assembler.add('{"role":"assistant","channels":{"thought":"Hel"}}'),
        )
        ..write(
          assembler.add('{"role":"assistant","channels":{"thought":"lo"}}'),
        )
        ..write(
          assembler.add(
            '{"role":"assistant","content":[{"type":"text","text":"42"}]}',
          ),
        )
        ..write(assembler.flush());

      expect(out.toString(), '<|channel>thought\nHello<channel|>42');
    });

    test('wraps thought runs with the configured handler markers', () {
      final assembler = LiteRtLmChannelAssembler(
        thinkingStartTag: '<think>',
        thinkingEndTag: '</think>',
      );
      final out = StringBuffer()
        ..write(
          assembler.add('{"role":"assistant","channels":{"thought":"Hel"}}'),
        )
        ..write(
          assembler.add('{"role":"assistant","channels":{"thought":"lo"}}'),
        )
        ..write(
          assembler.add(
            '{"role":"assistant","content":[{"type":"text","text":"42"}]}',
          ),
        )
        ..write(assembler.flush());

      expect(out.toString(), '<think>Hello</think>42');
    });

    test('passes plain content through untouched', () {
      final assembler = LiteRtLmChannelAssembler();
      final out =
          assembler.add(
            '{"role":"assistant","content":[{"type":"text","text":"7"}]}',
          ) +
          assembler.flush();

      expect(out, '7');
    });

    test('preserves native tool-call JSON as a parser-visible envelope', () {
      final assembler = LiteRtLmChannelAssembler();
      final out =
          assembler.add(
            '{"role":"assistant","tool_calls":[{"name":"get_weather",'
            '"arguments":{"city":"Seoul"}}]}',
          ) +
          assembler.flush();

      expect(
        out,
        '{"tool_calls":[{"name":"get_weather","arguments":{"city":"Seoul"}}]}',
      );
    });

    test('closes an unterminated thought run on flush (token cutoff)', () {
      final assembler = LiteRtLmChannelAssembler();
      final out = StringBuffer()
        ..write(
          assembler.add(
            '{"role":"assistant","channels":{"thought":"partial"}}',
          ),
        )
        ..write(assembler.flush());

      expect(out.toString(), '<|channel>thought\npartial<channel|>');
    });

    test('preserves non-JSON and unrecognized payloads verbatim', () {
      final assembler = LiteRtLmChannelAssembler();
      expect(assembler.add('not json'), 'not json');
      expect(assembler.add('{"role":"assistant"}'), '{"role":"assistant"}');
    });
  });
}
