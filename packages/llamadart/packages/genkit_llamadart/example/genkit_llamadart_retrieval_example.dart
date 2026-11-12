import 'dart:convert';
import 'dart:io';

import 'package:genkit/genkit.dart';

import 'retrieval/local_retrieval.dart';
import 'support/chat_model.dart';

Future<void> main(List<String> args) async {
  final prepared = await prepareExampleChat('retrieval');
  final ai = prepared.createGenkit();
  try {
    final documents = <DocumentData>[
      for (final id in ['returns', 'shipping', 'support'])
        DocumentData(
          content: [
            TextPart(
              text: await File('example/retrieval/$id.txt').readAsString(),
            ),
          ],
          metadata: {'id': id},
        ),
    ];
    final answer = defineLocalRetrievalFlow(ai, documents);
    print(
      jsonEncode(
        await answer(
          args.isEmpty ? 'What is the return window?' : args.join(' '),
        ),
      ),
    );
  } finally {
    try {
      await prepared.dispose();
    } finally {
      await ai.shutdown();
    }
  }
}
