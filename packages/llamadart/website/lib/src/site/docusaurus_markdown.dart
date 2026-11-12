import 'package:jaspr_content/jaspr_content.dart';

/// Rewrites the Docusaurus-specific Markdown in the docs, outside code
/// fences, into plain Markdown and site components:
///
/// - `:::type Title` … `:::` admonitions become `<Admonition>` elements.
/// - Relative links, with or without a `.md` suffix, become absolute URLs
///   resolved against the page URL, as Docusaurus resolves them.
/// - A leading `# Heading` becomes the page title.
/// - MDX `import … from '@site/…'` lines are dropped; the imported
///   components are registered in Dart.
class DocusaurusMarkdown implements TemplateEngine {
  const DocusaurusMarkdown();

  @override
  Future<void> render(Page page, List<Page> pages) async {
    final (content, title) = convert(page.content, page.url);
    page.apply(
      content: content,
      data: {
        if (title != null) 'page': {'title': title},
      },
    );
  }

  static final _fence = RegExp(r'^\s*(```|~~~)');
  static final _admonitionOpen = RegExp(
    r'^:::(note|tip|info|warning|caution|danger)\s*(.*)$',
  );
  static final _mdxImport = RegExp(r"^import \w+ from '@site/[^']*';\s*$");
  static final _relativeLink = RegExp(
    r'\]\((\.{1,2}/[^)\s#]*?)(\.mdx?)?(#[^)\s]*)?\)',
  );

  /// Returns the converted Markdown and the title taken from a leading H1.
  static (String, String?) convert(String markdown, String pageUrl) {
    final base = Uri.parse('https://site$pageUrl');
    final out = StringBuffer();
    String? fence;
    String? title;
    var seenContent = false;
    for (final line in markdown.split('\n')) {
      final fenceMatch = _fence.firstMatch(line);
      if (fenceMatch != null) {
        final marker = fenceMatch[1]!;
        if (fence == null) {
          fence = marker;
        } else if (fence == marker) {
          fence = null;
        }
        seenContent = true;
        out.writeln(line);
        continue;
      }
      if (fence != null) {
        out.writeln(line);
        continue;
      }
      if (!seenContent && line.startsWith('# ')) {
        title = line.substring(2).trim();
        seenContent = true;
        continue;
      }
      if (_mdxImport.hasMatch(line)) continue;
      final open = _admonitionOpen.firstMatch(line);
      if (open != null) {
        final heading = open[2]!.trim();
        out.writeln(
          '<Admonition type="${open[1]}"'
          '${heading.isEmpty ? '' : ' title="${_escapeAttribute(heading)}"'}>\n',
        );
        seenContent = true;
        continue;
      }
      if (line.trim() == ':::') {
        out.writeln('\n</Admonition>');
        continue;
      }
      if (line.trim().isNotEmpty) seenContent = true;
      out.writeln(
        line.replaceAllMapped(_relativeLink, (m) {
          final path = base.resolve(m[1]!).path;
          return '](${path.length > 1 && path.endsWith('/') ? path.substring(0, path.length - 1) : path}${m[3] ?? ''})';
        }),
      );
    }
    return (out.toString(), title);
  }

  static String _escapeAttribute(String value) =>
      value.replaceAll('&', '&amp;').replaceAll('"', '&quot;');
}
