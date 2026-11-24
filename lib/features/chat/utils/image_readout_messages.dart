import '../../../core/models/enums.dart';
import '../data/image_reader.dart';
import '../data/models/message.dart';
import 'attachment_helpers.dart';

/// For a model that can't take images: replaces each image attachment on
/// user messages with what [reader] could read from it, as a text block in
/// the message. Images that can't be read are dropped so the request still
/// goes through. Saved messages are untouched; only the request copy
/// changes.
Future<List<Message>> replaceImagesWithReadouts(
  List<Message> messages,
  ImageReader reader,
) async {
  final result = <Message>[];
  for (final message in messages) {
    final paths = message.attachmentPaths ?? const <String>[];
    if (message.role != MessageRole.user ||
        !paths.any(AttachmentHelpers.isImagePath)) {
      result.add(message);
      continue;
    }

    var content = message.content;
    final kept = <String>[];
    for (final path in paths) {
      if (!AttachmentHelpers.isImagePath(path)) {
        kept.add(path);
        continue;
      }
      final readout = await reader.read(path);
      content = AttachmentHelpers.appendTextAttachment(
        content,
        AttachmentHelpers.fileNameOf(path),
        readout?.toPromptText() ?? ImageReadout.unreadablePromptText,
      );
    }
    result.add(message.copyWith(content: content, attachmentPaths: kept));
  }
  return result;
}
