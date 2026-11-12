import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:jaspr_content/jaspr_content.dart';

import '../components/chrome.dart';
import 'site_layout.dart';

/// `layout: redirect` sends visitors to the frontmatter `to:` URL.
class RedirectLayout extends SiteLayout {
  const RedirectLayout();

  @override
  Pattern get name => 'redirect';

  @override
  String? canonicalPath(Page page) => null;

  @override
  bool indexable(Page page) => false;

  String _target(Page page) => page.data.page['to'] as String;

  @override
  Iterable<Component> buildHead(Page page) sync* {
    yield* super.buildHead(page);
    yield meta(
      attributes: {
        'http-equiv': 'refresh',
        'content': '0;url=${_target(page)}',
      },
    );
  }

  @override
  Component buildBody(Page page, Component child) {
    final target = _target(page);
    return main_(classes: 'redirect', [
      p([
        Component.text('Redirecting to '),
        a(href: target, [Component.text(target)]),
      ]),
    ]);
  }
}

/// `layout: not-found`, served by the static host for unknown paths.
class NotFoundLayout extends SiteLayout {
  const NotFoundLayout();

  @override
  Pattern get name => 'not-found';

  @override
  String? canonicalPath(Page page) => null;

  @override
  bool indexable(Page page) => false;

  @override
  Component buildBody(Page page, Component child) {
    return div(classes: 'site', [
      const SiteHeader(),
      main_(id: 'content', classes: 'not-found', [
        h1([Component.text('Page not found')]),
        p([
          Component.text(
            'This page does not exist. Search the docs, or start '
            'from the ',
          ),
          a(href: '/docs/intro', [Component.text('introduction')]),
          Component.text('.'),
        ]),
      ]),
      const SiteFooter(),
      const SearchDialog(),
    ]);
  }
}
