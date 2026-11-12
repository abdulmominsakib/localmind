import 'dart:convert';
import 'dart:io';

import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:jaspr_content/jaspr_content.dart';

import '../site/site_model.dart';

const _siteDescription =
    'Run LLMs on-device in Flutter and Dart apps: one API for GGUF '
    '(llama.cpp) and LiteRT-LM models on Android, iOS, macOS, Linux, '
    'Windows, and web.';
const _keywords =
    'llamadart, on-device LLM, Flutter LLM, Dart LLM, llama.cpp, LiteRT-LM, '
    'GGUF, local inference, offline AI, private AI';
const _socialCard = '$siteUrl/img/social-card.png';

/// Sets the theme before first paint. `theme` is the key Docusaurus used, so
/// returning visitors keep their choice.
const _themeScript = '''
(function () {
  try {
    var stored = localStorage.getItem('theme');
    var dark = stored ? stored === 'dark' : matchMedia('(prefers-color-scheme: dark)').matches;
    document.documentElement.setAttribute('data-theme', dark ? 'dark' : 'light');
  } catch (e) {}
})();''';

/// Head and document shell shared by every page. There is no `<base>`
/// element, so relative URLs resolve against the page itself.
abstract class SiteLayout implements PageLayout {
  const SiteLayout();

  Component buildBody(Page page, Component child);

  @override
  Component buildLayout(Page page, Component child) => Document(
    lang: 'en',
    base: null,
    head: buildHead(page).toList(),
    body: buildBody(page, child),
  );

  /// Canonical path of the page, or null when it has none.
  String? canonicalPath(Page page) => page.url;

  /// Whether search engines may index the page.
  bool indexable(Page page) => true;

  Iterable<Component> buildHead(Page page) sync* {
    final data = page.data.page;
    final title = switch (data['title']) {
      final String t when page.url != '/' => '$t | llamadart',
      final String t => t,
      _ => 'llamadart',
    };
    final description = data['description'] as String? ?? _siteDescription;

    yield Component.element(tag: 'title', children: [Component.text(title)]);
    yield meta(name: 'description', content: description);
    yield meta(name: 'keywords', content: _keywords);
    if (!indexable(page)) {
      yield meta(name: 'robots', content: 'noindex, nofollow');
    }
    if (canonicalPath(page) case final path?) {
      yield link(rel: 'canonical', href: '$siteUrl$path');
      yield meta(
        attributes: {'property': 'og:url', 'content': '$siteUrl$path'},
      );
    }
    yield meta(attributes: {'property': 'og:type', 'content': 'website'});
    yield meta(attributes: {'property': 'og:title', 'content': title});
    yield meta(
      attributes: {'property': 'og:description', 'content': description},
    );
    yield meta(attributes: {'property': 'og:image', 'content': _socialCard});
    yield meta(name: 'twitter:card', content: 'summary_large_image');
    yield meta(name: 'twitter:image', content: _socialCard);
    yield link(rel: 'icon', type: 'image/svg+xml', href: '/img/logo.svg');
    yield script(content: _themeScript);
    yield link(rel: 'preconnect', href: 'https://fonts.googleapis.com');
    yield link(
      rel: 'preconnect',
      href: 'https://fonts.gstatic.com',
      attributes: {'crossorigin': ''},
    );
    yield link(
      rel: 'stylesheet',
      href:
          'https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700'
          '&family=JetBrains+Mono:wght@400;500&display=swap',
    );
    yield link(rel: 'stylesheet', href: '/styles.css');
    yield script(src: '/site.js', attributes: {'defer': ''});
    yield script(
      attributes: {'type': 'application/ld+json'},
      content: jsonEncode(_structuredData),
    );
    yield* _analytics();
  }

  /// GA4, when the deploy provides `DOCS_GA_MEASUREMENT_ID`.
  Iterable<Component> _analytics() sync* {
    final id = Platform.environment['DOCS_GA_MEASUREMENT_ID']?.trim() ?? '';
    if (id.isEmpty) return;
    yield script(
      src:
          'https://www.googletagmanager.com/gtag/js?id=${Uri.encodeComponent(id)}',
      attributes: {'async': ''},
    );
    yield script(
      content:
          'window.dataLayer=window.dataLayer||[];'
          'function gtag(){dataLayer.push(arguments);}'
          "gtag('js',new Date());"
          'gtag("config",${jsonEncode(id)},{anonymize_ip:true});',
    );
  }
}

const _structuredData = {
  '@context': 'https://schema.org',
  '@graph': [
    {
      '@type': 'Organization',
      '@id': '$siteUrl/#organization',
      'name': 'llamadart contributors',
      'url': siteUrl,
      'logo': '$siteUrl/img/logo.svg',
      'sameAs': [githubUrl, pubUrl],
    },
    {
      '@type': 'WebSite',
      '@id': '$siteUrl/#website',
      'name': 'llamadart documentation',
      'url': siteUrl,
      'description': _siteDescription,
      'image': _socialCard,
      'publisher': {'@id': '$siteUrl/#organization'},
      'potentialAction': {
        '@type': 'ReadAction',
        'target': '$siteUrl/docs/intro',
      },
    },
  ],
};
