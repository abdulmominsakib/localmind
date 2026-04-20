import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:syntax_highlight/syntax_highlight.dart';

const _languages = [
  'css',
  'dart',
  'go',
  'html',
  'java',
  'javascript',
  'json',
  'kotlin',
  'python',
  'rust',
  'sql',
  'swift',
  'typescript',
  'yaml',
];

final highlighterThemesProvider = FutureProvider<HighlighterThemes>((ref) {
  return HighlighterThemes.load();
});

class HighlighterThemes {
  final HighlighterTheme light;
  final HighlighterTheme dark;

  HighlighterThemes({required this.light, required this.dark});

  static Future<HighlighterThemes> load() async {
    final light = await HighlighterTheme.loadLightTheme();
    final dark = await HighlighterTheme.loadDarkTheme();
    return HighlighterThemes(light: light, dark: dark);
  }
}

Future<void> initializeHighlighter() async {
  await Highlighter.initialize(_languages);
}
