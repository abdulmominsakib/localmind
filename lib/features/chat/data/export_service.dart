import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:localmind/features/chat/data/models/message.dart';
import 'package:localmind/core/models/enums.dart';

class ExportService {
  static Future<String> exportAsMarkdown(
    List<Message> messages, {
    String? title,
  }) async {
    final buffer = StringBuffer();

    if (title != null) {
      buffer.writeln('# $title');
      buffer.writeln();
    }

    buffer.writeln(
      '*Exported from LocalMind — ${DateTime.now().toIso8601String()}*',
    );
    buffer.writeln();
    buffer.writeln('---');
    buffer.writeln();

    for (final message in messages) {
      switch (message.role) {
        case MessageRole.user:
          buffer.writeln('## 👤 User');
        case MessageRole.assistant:
          buffer.writeln('## 🤖 Assistant');
        case MessageRole.system:
          buffer.writeln('## ⚙️ System');
        case MessageRole.tool:
          buffer.writeln('## 🔧 Tool');
      }
      buffer.writeln();
      buffer.writeln(message.content);
      buffer.writeln();
      buffer.writeln('*${message.createdAt.toIso8601String()}*');
      buffer.writeln();
      buffer.writeln('---');
      buffer.writeln();
    }

    return buffer.toString();
  }

  static Future<File> exportAndSaveMarkdown(
    List<Message> messages, {
    String? title,
    String? filename,
  }) async {
    final content = await exportAsMarkdown(messages, title: title);
    final dir = await getApplicationDocumentsDirectory();
    final name =
        filename ?? 'localmind_export_${DateTime.now().millisecondsSinceEpoch}';
    final file = File('${dir.path}/$name.md');
    return file.writeAsString(content);
  }

  static String exportAsText(List<Message> messages, {String? title}) {
    final buffer = StringBuffer();

    if (title != null) {
      buffer.writeln(title);
      buffer.writeln('=' * title.length);
      buffer.writeln();
    }

    for (final message in messages) {
      final roleLabel = switch (message.role) {
        MessageRole.user => 'USER',
        MessageRole.assistant => 'ASSISTANT',
        MessageRole.system => 'SYSTEM',
        MessageRole.tool => 'TOOL',
      };
      buffer.writeln('[$roleLabel]');
      buffer.writeln(message.content);
      buffer.writeln();
    }

    return buffer.toString();
  }
}
