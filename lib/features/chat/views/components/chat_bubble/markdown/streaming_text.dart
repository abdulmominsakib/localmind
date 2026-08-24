import 'package:flutter/material.dart';

class StreamingTextContent extends StatelessWidget {
  const StreamingTextContent({
    super.key,
    required this.content,
    required this.isDark,
  });

  final String content;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Text(
      content,
      style: TextStyle(
        color: isDark ? Colors.white : Colors.black,
        fontSize: 15,
        height: 1.5,
      ),
    );
  }
}
