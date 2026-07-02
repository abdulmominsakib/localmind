import 'package:flutter/material.dart';
import 'package:localmind/features/chat/data/chat_api_error.dart';

class ChatErrorDisplay extends StatelessWidget {
  const ChatErrorDisplay({
    super.key,
    required this.errorMessage,
  });

  final String errorMessage;

  @override
  Widget build(BuildContext context) {
    final parsed = ChatApiError.tryParse(errorMessage);
    if (parsed == null) {
      return Text(
        errorMessage,
        style: TextStyle(
          color: Colors.red[400],
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      );
    }

    final metaParts = <String>[];
    if (parsed.type != null && parsed.type!.isNotEmpty) {
      metaParts.add('type: ${parsed.type}');
    }
    if (parsed.code != null && parsed.code!.isNotEmpty) {
      metaParts.add('code: ${parsed.code}');
    }
    if (parsed.param != null && parsed.param!.isNotEmpty) {
      metaParts.add('param: ${parsed.param}');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          parsed.message,
          style: TextStyle(
            color: Colors.red[400],
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        if (metaParts.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              metaParts.join(' · '),
              style: TextStyle(
                color: Colors.red[300]?.withValues(alpha: 0.75),
                fontSize: 10,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
      ],
    );
  }
}
