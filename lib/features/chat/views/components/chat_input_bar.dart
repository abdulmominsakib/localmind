import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:haptic_feedback/haptic_feedback.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/features/servers/providers/server_providers.dart';

class ChatInputBar extends ConsumerStatefulWidget {
  const ChatInputBar({
    super.key,
    required this.onSend,
    required this.onStop,
    this.enabled = true,
  });

  final void Function(String message) onSend;
  final VoidCallback onStop;
  final bool enabled;

  @override
  ConsumerState<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends ConsumerState<ChatInputBar> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _isComposing = false;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleSubmit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    Haptics.vibrate(HapticsType.medium);
    widget.onSend(text);
    _controller.clear();
    setState(() => _isComposing = false);
  }

  void _handleStop() {
    Haptics.vibrate(HapticsType.light);
    widget.onStop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final connectionStatus = ref.watch(connectionStatusProvider);
    final isConnected = connectionStatus == ConnectionStatus.connected;

    final canSend =
        widget.enabled &&
        isConnected &&
        _controller.text.trim().isNotEmpty &&
        !_isComposing;

    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0A0A0A) : const Color(0xFFFAFAFA),
        border: Border(
          top: BorderSide(
            color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE5E5E5),
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isConnected)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.wifi_off, size: 16, color: Colors.orange),
                  const SizedBox(width: 8),
                  Text(
                    'Not connected to server',
                    style: TextStyle(fontSize: 13, color: Colors.orange[700]),
                  ),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1F1F1F)
                      : const Color(0xFFFFFFFF),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF3A3A3A)
                        : const Color(0xFFE5E5E5),
                  ),
                ),
                child: IconButton(
                  icon: Icon(
                    Icons.attach_file,
                    size: 20,
                    color: isDark
                        ? const Color(0xFF888888)
                        : const Color(0xFF666666),
                  ),
                  onPressed: null,
                  tooltip: 'Attach file (Coming soon)',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 150),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF1F1F1F)
                        : const Color(0xFFFFFFFF),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: isDark
                          ? const Color(0xFF3A3A3A)
                          : const Color(0xFFE5E5E5),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          enabled: widget.enabled && isConnected,
                          maxLines: null,
                          textInputAction: TextInputAction.newline,
                          keyboardType: TextInputType.multiline,
                          onChanged: (text) {
                            setState(
                              () => _isComposing = text.trim().isNotEmpty,
                            );
                          },
                          onSubmitted: (_) => _handleSubmit(),
                          decoration: InputDecoration(
                            hintText: 'Message LocalMind...',
                            hintStyle: TextStyle(
                              color: isDark
                                  ? const Color(0xFF666666)
                                  : const Color(0xFF999999),
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ),
                      if (_isComposing)
                        Padding(
                          padding: const EdgeInsets.only(right: 4, bottom: 4),
                          child: Text(
                            '${_controller.text.length}',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark
                                  ? const Color(0xFF666666)
                                  : const Color(0xFF999999),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _isComposing
                  ? Container(
                      decoration: BoxDecoration(
                        color: Colors.red[400],
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.stop, color: Colors.white),
                        onPressed: _handleStop,
                        tooltip: 'Stop generating',
                      ),
                    )
                  : Container(
                      decoration: BoxDecoration(
                        color: canSend
                            ? (isDark
                                  ? const Color(0xFF3B82F6)
                                  : const Color(0xFF2563EB))
                            : (isDark
                                  ? const Color(0xFF3A3A3A)
                                  : const Color(0xFFE5E5E5)),
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: Icon(
                          Icons.arrow_upward,
                          color: canSend
                              ? Colors.white
                              : (isDark
                                    ? const Color(0xFF666666)
                                    : const Color(0xFF999999)),
                        ),
                        onPressed: canSend ? _handleSubmit : null,
                        tooltip: 'Send message',
                      ),
                    ),
            ],
          ),
        ],
      ),
    );
  }
}
