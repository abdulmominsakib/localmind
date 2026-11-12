import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:jaspr_content/jaspr_content.dart';

import '../highlight/highlighter.dart';

/// Renders fenced code: Mermaid source for the client-side renderer, and
/// every other block highlighted at build time.
class FencedCode extends CustomComponent {
  FencedCode() : super.base();

  @override
  Component? create(Node node, NodesBuilder builder) {
    if (node case ElementNode(
      tag: 'pre',
      children: [ElementNode(tag: 'code', :final children, :final attributes)],
    )) {
      final className = attributes['class'] ?? '';
      final language = className.startsWith('language-')
          ? className.substring('language-'.length)
          : null;
      final source = (children ?? const []).map((c) => c.innerText).join();
      if (language == 'mermaid') {
        return pre(classes: 'mermaid', [Component.text(source.trimRight())]);
      }
      return CodeFrame(source: source, language: language);
    }
    return null;
  }
}

class CodeFrame extends StatelessComponent {
  const CodeFrame({required this.source, this.language, this.title});

  final String source;
  final String? language;
  final String? title;

  @override
  Component build(BuildContext context) {
    final code = source.endsWith('\n')
        ? source.substring(0, source.length - 1)
        : source;
    return div(
      classes: 'code-frame',
      attributes: {'data-lang': ?language},
      [
        if (title != null) div(classes: 'code-title', [Component.text(title!)]),
        button(
          classes: 'copy-code',
          attributes: {'type': 'button', 'aria-label': 'Copy code'},
          [Component.text('Copy')],
        ),
        AsyncBuilder(
          builder: (context) async => pre([
            Component.element(
              tag: 'code',
              children: [
                for (final token in await highlight(code, language))
                  if (token.kind case final kind?)
                    span(classes: 'tok-$kind', [Component.text(token.text)])
                  else
                    Component.text(token.text),
              ],
            ),
          ]),
        ),
      ],
    );
  }
}

/// `<Admonition type="warning" title="…">`, produced from `:::` blocks.
class Admonition extends CustomComponentBase {
  const Admonition();

  @override
  Pattern get pattern => 'Admonition';

  static const _defaultTitles = {
    'note': 'Note',
    'tip': 'Tip',
    'info': 'Info',
    'warning': 'Warning',
    'caution': 'Caution',
    'danger': 'Danger',
  };

  @override
  Component apply(
    String name,
    Map<String, String> attributes,
    Component? child,
  ) {
    final type = attributes['type'] ?? 'note';
    return div(classes: 'admonition admonition-$type', [
      p(classes: 'admonition-title', [
        Component.text(attributes['title'] ?? _defaultTitles[type] ?? type),
      ]),
      div(classes: 'admonition-body', [?child]),
    ]);
  }
}

/// `<ArchitectureDiagram />` in `guides/architecture.md`.
class ArchitectureDiagram extends CustomComponentBase {
  const ArchitectureDiagram();

  @override
  Pattern get pattern => 'ArchitectureDiagram';

  @override
  Component apply(
    String name,
    Map<String, String> attributes,
    Component? child,
  ) {
    Component node(String title, [String? sub, String classes = 'arch-node']) =>
        div(classes: classes, [
          span(classes: 'arch-title', [Component.text(title)]),
          if (sub != null) span(classes: 'arch-sub', [Component.text(sub)]),
        ]);
    Component arrow([String? label]) => div(classes: 'arch-arrow', [
      if (label != null) span([Component.text(label)]),
      span(attributes: {'aria-hidden': 'true'}, [Component.text('↓')]),
    ]);
    Component layer(String title, List<Component> children) =>
        div(classes: 'arch-layer', [
          p(classes: 'arch-layer-title', [Component.text(title)]),
          ...children,
        ]);

    return div(
      classes: 'arch',
      attributes: {
        'role': 'img',
        'aria-label': 'llamadart architecture layers',
      },
      [
        layer('Dart & Flutter application layer', [
          node('Flutter UI', 'Application state'),
          arrow('State streams'),
          node('LlamaEngine', 'Dart core API', 'arch-node accent'),
          arrow('Async tasks'),
          node('Worker isolate', 'Off the UI isolate'),
        ]),
        arrow('Native calls'),
        node('Dart FFI bridge', null, 'arch-node bridge'),
        arrow('C API'),
        layer('Native llama.cpp & GGML layer', [
          node('libllama C API', 'load, tokenize, sample'),
          arrow(),
          node('llama.cpp core', 'Inference engine', 'arch-node accent'),
          arrow(),
          node('GGML math backend', 'Tensor operations'),
        ]),
        arrow('Vectorized compute'),
        layer('Hardware compute', [
          div(classes: 'arch-row', [
            node('CPU intrinsics', 'NEON, AVX'),
            node('GPU acceleration', 'Metal / Vulkan / CUDA'),
          ]),
        ]),
      ],
    );
  }
}
