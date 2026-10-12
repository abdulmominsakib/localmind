import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

/// Orange inline notice used in the chat MCP settings.
class McpWarningNotice extends StatelessWidget {
  const McpWarningNotice({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const HugeIcon(
            icon: HugeIcons.strokeRoundedAlertCircle,
            color: Colors.orange,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 13, color: Colors.orange),
            ),
          ),
        ],
      ),
    );
  }
}
