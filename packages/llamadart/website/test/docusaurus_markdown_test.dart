import 'package:llamadart_website/src/site/docusaurus_markdown.dart';
import 'package:test/test.dart';

String convert(
  String markdown, [
  String url = '/docs/next/guides/tool-calling',
]) => DocusaurusMarkdown.convert(markdown, url).$1;

void main() {
  test('turns admonitions into Admonition elements', () {
    expect(
      convert(':::warning Experimental "web" runtime\nBody.\n:::\n'),
      '<Admonition type="warning" title="Experimental &quot;web&quot; runtime">'
      '\n\nBody.\n\n</Admonition>\n\n',
    );
    expect(
      convert(':::tip\nBody.\n:::'),
      startsWith('<Admonition type="tip">'),
    );
  });

  test('resolves relative links against the page URL', () {
    expect(
      convert('[a](./quickstart) [b](../platforms/support-matrix#web)'),
      '[a](/docs/next/guides/quickstart) '
      '[b](/docs/next/platforms/support-matrix#web)\n',
    );
    expect(
      convert('[tts](../guides/text-to-speech.md#known-limits)'),
      '[tts](/docs/next/guides/text-to-speech#known-limits)\n',
    );
    expect(
      convert('[x](https://example.com/a.md) [y](#local) [z](/docs/intro)'),
      '[x](https://example.com/a.md) [y](#local) [z](/docs/intro)\n',
    );
  });

  test('leaves fenced code untouched', () {
    const fenced =
        '```md\n:::warning\n[a](./b.md)\n# Not a title\n```\n'
        '~~~\nimport X from \'@site/x\';\n~~~\n';
    expect(convert(fenced), '$fenced\n');
  });

  test('takes a leading H1 as the title and drops MDX imports', () {
    final (content, title) = DocusaurusMarkdown.convert(
      "\n# Release workflow\n\nimport Diagram from '@site/src/Diagram';\n\n"
          '<Diagram />\n\n# Later heading\n',
      '/docs/maintainers/release-workflow',
    );
    expect(title, 'Release workflow');
    expect(content, isNot(contains('import Diagram')));
    expect(content, contains('# Later heading'));
  });
}
