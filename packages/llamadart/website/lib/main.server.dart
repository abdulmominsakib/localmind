/// Pre-renders the llamadart documentation site.
library;

import 'package:jaspr/server.dart';
import 'package:jaspr_content/jaspr_content.dart';
import 'package:jaspr_content/theme.dart';

import 'main.server.options.dart';
import 'src/components/content_components.dart';
import 'src/layouts/docs_layout.dart';
import 'src/layouts/home_layout.dart';
import 'src/layouts/page_layouts.dart';
import 'src/site/docusaurus_markdown.dart';
import 'src/site/site_model.dart';
import 'src/site/versioned_loader.dart';

void main() {
  Jaspr.initializeApp(options: defaultServerOptions);

  final config = PageConfig(
    templateEngine: const DocusaurusMarkdown(),
    parsers: [MarkdownParser()],
    extensions: [HeadingAnchorsExtension(), TableOfContentsExtension()],
    components: [FencedCode(), const Admonition(), const ArchitectureDiagram()],
    layouts: const [
      DocsPageLayout(),
      HomeLayout(),
      RedirectLayout(),
      NotFoundLayout(),
    ],
    theme: ContentTheme.none(),
  );

  runApp(
    ContentApp.custom(
      loaders: [
        FilesystemLoader('content'),
        for (final version in SiteModel.instance.versions)
          VersionedDocsLoader(version),
      ],
      configResolver: (_) => config,
    ),
  );
}
