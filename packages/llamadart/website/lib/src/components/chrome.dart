import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';

import '../site/sidebar.dart';
import '../site/site_model.dart';

Component _kbd(String key) =>
    Component.element(tag: 'kbd', children: [Component.text(key)]);

/// Top bar on every page. [version] and [docId] are null outside the docs.
class SiteHeader extends StatelessComponent {
  const SiteHeader({this.version, this.docId, this.section});

  final DocVersion? version;
  final String? docId;

  /// Active top-level section: `docs`, `examples` or `maintainers`.
  final String? section;

  @override
  Component build(BuildContext context) {
    final prefix = version?.urlPrefix ?? 'docs';
    Component navLink(String key, String label, String href) => a(
      href: href,
      classes: section == key ? 'nav-link active' : 'nav-link',
      attributes: {if (section == key) 'aria-current': 'true'},
      [Component.text(label)],
    );
    return header(classes: 'site-header', [
      div(classes: 'header-inner', [
        if (version != null)
          button(
            classes: 'sidebar-toggle',
            attributes: {'type': 'button', 'aria-label': 'Open navigation'},
            [RawText(_menuIcon)],
          ),
        a(href: '/', classes: 'brand', [
          img(src: '/img/logo.svg', alt: '', width: 28, height: 28),
          span([Component.text('llamadart')]),
        ]),
        nav(
          classes: 'primary-nav',
          attributes: {'aria-label': 'Primary'},
          [
            navLink('docs', 'Docs', '/$prefix/intro'),
            navLink('examples', 'Examples', '/$prefix/examples/overview'),
            a(href: apiUrl, classes: 'nav-link', [Component.text('API')]),
            navLink(
              'maintainers',
              'Contributing',
              '/$prefix/maintainers/docs-site',
            ),
          ],
        ),
        div(classes: 'header-actions', [
          button(
            classes: 'search-button',
            attributes: {
              'type': 'button',
              'data-search-open': '',
              'aria-label': 'Search',
            },
            [
              RawText(_searchIcon),
              span(classes: 'search-label', [Component.text('Search')]),
              _kbd('/'),
            ],
          ),
          if (version != null) VersionMenu(current: version!, docId: docId),
          a(href: pubUrl, classes: 'icon-link text-link', [
            Component.text('pub.dev'),
          ]),
          a(
            href: githubUrl,
            classes: 'icon-link',
            attributes: {'aria-label': 'GitHub repository'},
            [RawText(_githubIcon)],
          ),
          button(
            classes: 'theme-toggle',
            attributes: {'type': 'button', 'aria-label': 'Toggle dark mode'},
            [RawText(_moonIcon), RawText(_sunIcon)],
          ),
        ]),
      ]),
    ]);
  }
}

/// Switches to the same doc in another version, or to its introduction when
/// that version lacks the doc.
class VersionMenu extends StatelessComponent {
  const VersionMenu({required this.current, this.docId});

  final DocVersion current;
  final String? docId;

  @override
  Component build(BuildContext context) {
    String target(DocVersion v) =>
        v.docUrl(docId != null && v.docs.containsKey(docId) ? docId! : 'intro');
    return details(classes: 'version-menu', [
      summary(
        attributes: {'aria-label': 'Docs version'},
        [Component.text(current.label)],
      ),
      ul([
        for (final v in SiteModel.instance.versions)
          li([
            a(href: target(v), classes: v == current ? 'active' : null, [
              Component.text(
                v.kind == VersionKind.next ? 'Next (unreleased)' : v.label,
              ),
              if (v.kind == VersionKind.latest)
                span(classes: 'badge', [Component.text('latest')]),
            ]),
          ]),
      ]),
    ]);
  }
}

class DocsSidebar extends StatelessComponent {
  const DocsSidebar({
    required this.version,
    required this.entries,
    required this.currentUrl,
  });

  final DocVersion version;
  final List<SidebarEntry> entries;
  final String currentUrl;

  @override
  Component build(BuildContext context) {
    final prefix = version.urlPrefix;
    return nav(
      classes: 'sidebar',
      attributes: {'aria-label': 'Docs'},
      [
        button(
          classes: 'sidebar-close',
          attributes: {'type': 'button', 'aria-label': 'Close navigation'},
          [Component.text('×')],
        ),
        ul(classes: 'sidebar-list drawer-nav', [
          li([
            a(href: '/$prefix/intro', [Component.text('Docs')]),
          ]),
          li([
            a(href: '/$prefix/examples/overview', [Component.text('Examples')]),
          ]),
          li([
            a(href: apiUrl, [Component.text('API reference')]),
          ]),
          li([
            a(href: '/$prefix/maintainers/docs-site', [
              Component.text('Contributing'),
            ]),
          ]),
          li([
            a(href: githubUrl, [Component.text('GitHub')]),
          ]),
        ]),
        ..._items(entries, 0),
      ],
    );
  }

  Iterable<Component> _items(List<SidebarEntry> items, int depth) sync* {
    final links = <Component>[];
    for (final item in items) {
      if (item is SidebarCategory) {
        if (links.isNotEmpty) {
          yield ul(classes: 'sidebar-list', [...links]);
          links.clear();
        }
        yield div(classes: depth == 0 ? 'sidebar-group' : 'sidebar-subgroup', [
          p(classes: 'sidebar-heading', [Component.text(item.label)]),
          ..._items(item.items, depth + 1),
        ]);
      } else if (_link(item) case final link?) {
        links.add(link);
      }
    }
    if (links.isNotEmpty) yield ul(classes: 'sidebar-list', links);
  }

  Component? _link(SidebarEntry item) {
    switch (item) {
      case SidebarDoc(:final id, :final label):
        final meta = version.docs[id];
        if (meta == null) return null;
        final href = version.docUrl(id);
        final active = href == currentUrl;
        return li([
          a(
            href: href,
            classes: active ? 'active' : null,
            attributes: {if (active) 'aria-current': 'page'},
            [Component.text(label ?? meta.navLabel)],
          ),
        ]);
      case SidebarHref(:final label, :final href):
        return li([
          a(href: href, [Component.text(label)]),
        ]);
      case SidebarCategory():
        return null;
    }
  }
}

class SiteFooter extends StatelessComponent {
  const SiteFooter();

  @override
  Component build(BuildContext context) {
    Component column(String title, List<(String, String)> links) =>
        div(classes: 'footer-col', [
          p(classes: 'footer-title', [Component.text(title)]),
          ul([
            for (final (label, href) in links)
              li([
                a(href: href, [Component.text(label)]),
              ]),
          ]),
        ]);
    return footer(classes: 'site-footer', [
      div(classes: 'footer-inner', [
        div(classes: 'footer-brand', [
          a(href: '/', classes: 'brand', [
            img(src: '/img/logo.svg', alt: '', width: 24, height: 24),
            span([Component.text('llamadart')]),
          ]),
          p([Component.text('Local LLM inference for Dart and Flutter.')]),
        ]),
        column('Docs', [
          ('Introduction', '/docs/intro'),
          ('Quickstart', '/docs/getting-started/quickstart'),
          ('Support matrix', '/docs/platforms/support-matrix'),
          ('API reference', apiUrl),
        ]),
        column('Community', [
          ('GitHub', githubUrl),
          ('Issues', '$githubUrl/issues'),
          ('pub.dev', pubUrl),
          ('License', '$githubUrl/blob/main/LICENSE'),
        ]),
        column('Contributing', [
          ('Maintainer overview', '/docs/maintainers/docs-site'),
          ('Runtime ownership', '/docs/maintainers/runtime-ownership'),
          ('Release workflow', '/docs/maintainers/release-workflow'),
        ]),
      ]),
      div(classes: 'footer-legal', [
        Component.text(
          'Copyright © ${DateTime.now().year} llamadart contributors.',
        ),
      ]),
    ]);
  }
}

class SearchDialog extends StatelessComponent {
  const SearchDialog();

  @override
  Component build(BuildContext context) {
    return Component.element(
      tag: 'dialog',
      id: 'search-dialog',
      attributes: {'aria-label': 'Search documentation'},
      children: [
        div(classes: 'search-panel', [
          div(id: 'search', []),
          p(classes: 'search-hint', [
            Component.text('Searches the latest release. '),
            _kbd('Esc'),
            Component.text(' to close.'),
          ]),
        ]),
      ],
    );
  }
}

const _menuIcon =
    '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><path d="M4 6h16M4 12h16M4 18h16"/></svg>';
const _searchIcon =
    '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/></svg>';
const _moonIcon =
    '<svg class="icon-moon" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8Z"/></svg>';
const _sunIcon =
    '<svg class="icon-sun" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/></svg>';
const _githubIcon =
    '<svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M12 .5a12 12 0 0 0-3.8 23.4c.6.1.8-.3.8-.6v-2c-3.3.7-4-1.6-4-1.6-.6-1.4-1.4-1.8-1.4-1.8-1-.7.1-.7.1-.7 1.2.1 1.8 1.2 1.8 1.2 1 1.8 2.8 1.3 3.5 1 .1-.8.4-1.3.7-1.6-2.7-.3-5.5-1.3-5.5-6 0-1.2.5-2.3 1.2-3.1-.1-.4-.5-1.6.1-3.2 0 0 1-.3 3.3 1.2a11.5 11.5 0 0 1 6 0C17.3 4.7 18.3 5 18.3 5c.7 1.6.2 2.8.1 3.2.8.8 1.2 1.9 1.2 3.1 0 4.6-2.8 5.6-5.5 6 .4.3.8 1 .8 2.2v3.3c0 .3.2.7.8.6A12 12 0 0 0 12 .5Z"/></svg>';
