import 'dart:convert';

import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:jaspr_content/jaspr_content.dart';

import '../components/chrome.dart';
import '../components/content_components.dart';
import '../site/site_model.dart';
import 'site_layout.dart';

/// The homepage code sample. `test/home_sample_test.dart` checks that it
/// analyzes cleanly against the llamadart package in this repository.
const homeSample = '''import 'dart:io';

import 'package:llamadart/llamadart.dart';

Future<void> main() async {
  final engine = await LlamaEngine.load(
    LlamaModel(
      ModelSource.parse(
        'hf://unsloth/SmolLM2-135M-Instruct-GGUF/'
        'SmolLM2-135M-Instruct-Q2_K.gguf',
      ),
    ),
  );

  final chat = ChatSession(engine, systemPrompt: 'You are concise.');
  await for (final chunk in chat.create([
    const LlamaTextContent('What is quantization?'),
  ])) {
    stdout.write(chunk.text);
  }
  await engine.dispose();
}''';

const _homeSchema = {
  '@context': 'https://schema.org',
  '@type': 'SoftwareSourceCode',
  'name': 'llamadart',
  'description':
      'On-device LLM inference for Flutter and Dart: GGUF (llama.cpp) and '
      'LiteRT-LM models on Android, iOS, macOS, Linux, Windows, and web.',
  'codeRepository': githubUrl,
  'license': '$githubUrl/blob/main/LICENSE',
  'programmingLanguage': 'Dart',
  'runtimePlatform': ['Android', 'iOS', 'macOS', 'Linux', 'Windows', 'Web'],
  'image': '$siteUrl/img/social-card.png',
  'url': siteUrl,
  'sameAs': [githubUrl, pubUrl],
};

class HomeLayout extends SiteLayout {
  const HomeLayout();

  @override
  Pattern get name => 'home';

  @override
  Iterable<Component> buildHead(Page page) sync* {
    yield* super.buildHead(page);
    yield script(
      attributes: {'type': 'application/ld+json'},
      content: _jsonLd(_homeSchema),
    );
  }

  @override
  Component buildBody(Page page, Component child) {
    return div(classes: 'site home', [
      a(href: '#content', classes: 'skip-link', [
        Component.text('Skip to content'),
      ]),
      const SiteHeader(),
      main_(id: 'content', [
        section(classes: 'hero', [
          div(classes: 'hero-copy', [
            p(classes: 'eyebrow', [
              Component.text('On-device LLM inference for Flutter and Dart'),
            ]),
            h1([Component.text('Run LLMs on the device, from one Dart API')]),
            p(classes: 'lead', [
              Component.text(
                'llamadart runs GGUF (llama.cpp) and LiteRT-LM models inside '
                'your app on Android, iOS, macOS, Linux, Windows and the web. '
                'Prompts stay on the device, there is no inference server or '
                'API key, and native apps work offline once the model is '
                'downloaded.',
              ),
            ]),
            div(classes: 'install', [
              code([
                span(classes: 'prompt', [Component.text(r'$ ')]),
                Component.text('dart pub add llamadart'),
              ]),
              button(
                classes: 'copy-install',
                attributes: {
                  'type': 'button',
                  'data-copy': 'dart pub add llamadart',
                  'aria-label': 'Copy install command',
                },
                [Component.text('Copy')],
              ),
            ]),
            div(classes: 'hero-actions', [
              a(
                href: '/docs/getting-started/quickstart',
                classes: 'btn btn-primary',
                [Component.text('Get started')],
              ),
              a(href: demoUrl, classes: 'btn btn-secondary', [
                Component.text('Try the web demo'),
              ]),
              a(href: apiUrl, classes: 'btn btn-ghost', [
                Component.text('API reference'),
              ]),
            ]),
          ]),
          div(classes: 'hero-code', [
            div(classes: 'code-tabbar', [
              span(classes: 'dot', []),
              span(classes: 'dot', []),
              span(classes: 'dot', []),
              span(classes: 'code-file', [Component.text('bin/main.dart')]),
            ]),
            const CodeFrame(source: homeSample, language: 'dart'),
          ]),
        ]),
        section(
          classes: 'strip',
          attributes: {'aria-label': 'Supported targets'},
          [
            div(classes: 'strip-group', [
              p(classes: 'strip-label', [Component.text('Platforms')]),
              ul([
                for (final name in _platforms) li([Component.text(name)]),
              ]),
            ]),
            div(classes: 'strip-group', [
              p(classes: 'strip-label', [Component.text('Runtimes')]),
              ul([
                li([Component.text('llama.cpp · GGUF')]),
                li([Component.text('LiteRT-LM · .litertlm')]),
              ]),
            ]),
            a(href: '/docs/platforms/support-matrix', classes: 'strip-link', [
              Component.text('Support matrix →'),
            ]),
          ],
        ),
        section(classes: 'home-section', [
          h2([Component.text('What you can build')]),
          div(classes: 'feature-grid', [
            for (final (title, body, href, tag) in _features)
              a(href: href, classes: 'feature', [
                h3([
                  Component.text(title),
                  if (tag != null) span(classes: 'tag', [Component.text(tag)]),
                ]),
                p([Component.text(body)]),
              ]),
          ]),
        ]),
        section(classes: 'home-section', [
          h2([Component.text('Start here')]),
          div(classes: 'path-grid', [
            for (final (step, title, body, href) in _paths)
              a(href: href, classes: 'path', [
                span(classes: 'path-step', [Component.text(step)]),
                h3([Component.text(title)]),
                p([Component.text(body)]),
              ]),
          ]),
        ]),
      ]),
      const SiteFooter(),
      const SearchDialog(),
    ]);
  }
}

String _jsonLd(Object value) =>
    const JsonEncoder().convert(value).replaceAll('</', r'<\/');

const _platforms = ['Android', 'iOS', 'macOS', 'Linux', 'Windows', 'Web'];

const _features = [
  (
    'Chat and streaming',
    'Stateless completions with LlamaEngine, or multi-turn history with '
        'ChatSession, streamed as chunks.',
    '/docs/guides/generation-and-streaming',
    null,
  ),
  (
    'Tool calling',
    'Let the model call your Dart functions and handle the calls.',
    '/docs/guides/tool-calling',
    null,
  ),
  (
    'Embeddings',
    'Generate local embeddings for retrieval-style workflows.',
    '/docs/guides/embeddings',
    null,
  ),
  (
    'Multimodal',
    "Prompt with images and text, within each platform's limits.",
    '/docs/guides/multimodal',
    null,
  ),
  (
    'Speech to text',
    'Transcribe audio with the typed speech API.',
    '/docs/guides/speech-to-text',
    'experimental',
  ),
  (
    'Text to speech',
    'Generate PCM and WAV audio with Qwen3-TTS on native and WebGPU.',
    '/docs/guides/text-to-speech',
    'experimental',
  ),
  (
    'Image generation',
    'Generate images from text prompts on native platforms with the opt-in '
        'stable-diffusion.cpp runtime.',
    '/docs/guides/image-generation',
    'preview',
  ),
];

const _paths = [
  (
    '1',
    'Install',
    'Add the package and check platform prerequisites.',
    '/docs/getting-started/installation',
  ),
  (
    '2',
    'Quickstart',
    'Load a model and stream your first response.',
    '/docs/getting-started/quickstart',
  ),
  (
    '3',
    'Pick a model',
    'Choose GGUF or LiteRT-LM and a size that fits.',
    '/docs/getting-started/finding-models',
  ),
  (
    '4',
    'Explore examples',
    'Flutter chat app, CLI, OpenAI-compatible server and more.',
    '/docs/examples/overview',
  ),
];
