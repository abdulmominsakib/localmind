import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:jaspr_content/jaspr_content.dart';

import '../components/chrome.dart';
import '../site/sidebar.dart';
import '../site/site_model.dart';
import 'site_layout.dart';

class DocsPageLayout extends SiteLayout {
  const DocsPageLayout();

  @override
  Pattern get name => 'docs';

  (DocVersion, String) _resolve(Page page) =>
      SiteModel.instance.resolve(page.url) ??
      (throw StateError('No docs version serves ${page.url}'));

  @override
  bool indexable(Page page) {
    final (version, id) = _resolve(page);
    return version.indexable && !version.docs[id]!.unlisted;
  }

  @override
  Component buildBody(Page page, Component child) {
    final (version, id) = _resolve(page);
    final meta = version.docs[id]!;
    final maintainerDocs = flattenSidebar(
      version.sidebars['maintainersSidebar'] ?? const [],
    );
    final isMaintainerDoc =
        maintainerDocs.any((d) => d.$1 == id) || id.startsWith('maintainers/');
    final sidebar =
        (maintainerDocs.any((d) => d.$1 == id)
            ? version.sidebars['maintainersSidebar']
            : version.sidebars['docsSidebar']) ??
        const <SidebarEntry>[];
    final order = flattenSidebar(sidebar);
    final index = order.indexWhere((d) => d.$1 == id);
    final category = index >= 0 ? order[index].$2 : null;
    final title = page.data.page['title'] as String? ?? meta.title;
    final toc = page.data['toc'];

    return div(
      classes: 'site',
      attributes: {'data-has-sidebar': ''},
      [
        a(href: '#content', classes: 'skip-link', [
          Component.text('Skip to content'),
        ]),
        SiteHeader(
          version: version,
          docId: id,
          section: isMaintainerDoc
              ? 'maintainers'
              : id.startsWith('examples/')
              ? 'examples'
              : 'docs',
        ),
        div(classes: 'docs-shell', [
          div(classes: 'sidebar-barrier', []),
          aside(classes: 'sidebar-container', [
            DocsSidebar(
              version: version,
              entries: sidebar,
              currentUrl: page.url,
            ),
          ]),
          main_(id: 'content', classes: 'docs-main', [
            article(
              classes: 'doc',
              attributes: {if (indexable(page)) 'data-pagefind-body': ''},
              [
                ?_banner(version, id),
                if (category != null)
                  p(classes: 'breadcrumb', [Component.text(category)]),
                h1(
                  attributes: {'data-pagefind-meta': 'title'},
                  [Component.text(title)],
                ),
                if (meta.description case final description?)
                  p(classes: 'doc-lead', [Component.text(description)]),
                if (toc is TableOfContents && toc.entries.isNotEmpty)
                  details(classes: 'mobile-toc', [
                    summary([Component.text('On this page')]),
                    toc.build(),
                  ]),
                child,
                div(classes: 'doc-meta', [
                  a(
                    href:
                        '$githubUrl/edit/main/website/${version.directory}/$id.md',
                    [Component.text('Edit this page')],
                  ),
                ]),
                if (index >= 0) _pager(version, order, index),
              ],
            ),
            aside(classes: 'toc', [
              if (toc is TableOfContents && toc.entries.isNotEmpty)
                div(classes: 'toc-inner', [
                  p(classes: 'toc-title', [Component.text('On this page')]),
                  toc.build(),
                ]),
            ]),
          ]),
        ]),
        const SiteFooter(),
        const SearchDialog(),
      ],
    );
  }

  Component? _banner(DocVersion version, String id) {
    final latest = SiteModel.instance.latest;
    final href = latest.docUrl(latest.docs.containsKey(id) ? id : 'intro');
    return switch (version.kind) {
      VersionKind.latest => null,
      VersionKind.next => div(classes: 'version-banner', [
        Component.text('Unreleased documentation for the next version. '),
        a(href: href, [
          Component.text('Read ${latest.label}, the latest release'),
        ]),
      ]),
      VersionKind.archived => div(classes: 'version-banner archived', [
        Component.text(
          'Documentation for ${version.label}, an older release. ',
        ),
        a(href: href, [
          Component.text('Read ${latest.label}, the latest release'),
        ]),
      ]),
    };
  }

  Component _pager(
    DocVersion version,
    List<(String, String?)> order,
    int index,
  ) {
    Component cell(int i, String label, String classes) {
      if (i < 0 || i >= order.length) return div([]);
      final id = order[i].$1;
      return a(href: version.docUrl(id), classes: 'pager-link $classes', [
        span(classes: 'pager-label', [Component.text(label)]),
        span(classes: 'pager-title', [
          Component.text(version.docs[id]?.navLabel ?? id),
        ]),
      ]);
    }

    return nav(
      classes: 'pager',
      attributes: {'aria-label': 'Pagination'},
      [cell(index - 1, 'Previous', 'prev'), cell(index + 1, 'Next', 'next')],
    );
  }
}
