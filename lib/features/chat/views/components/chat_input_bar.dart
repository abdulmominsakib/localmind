import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:haptic_feedback/haptic_feedback.dart';
import 'package:file_picker/file_picker.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/features/servers/providers/server_providers.dart';

class ChatInputBar extends ConsumerStatefulWidget {
  const ChatInputBar({
    super.key,
    required this.onSend,
    required this.onStop,
    this.onAttach,
    this.enabled = true,
    this.isStreaming = false,
  });

  final void Function(String message) onSend;
  final VoidCallback onStop;
  final void Function(List<File> onAttach)? onAttach;
  final bool enabled;
  final bool isStreaming;

  @override
  ConsumerState<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends ConsumerState<ChatInputBar>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _isComposing = false;
  final List<File> _attachedFiles = [];
  late AnimationController _sendButtonAnimController;
  late Animation<double> _sendButtonScale;

  @override
  void initState() {
    super.initState();
    _sendButtonAnimController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _sendButtonScale = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _sendButtonAnimController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _sendButtonAnimController.dispose();
    super.dispose();
  }

  Future<void> _handleAttach() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _attachedFiles.addAll(
          result.files.where((f) => f.path != null).map((f) => File(f.path!)),
        );
      });
      widget.onAttach?.call(_attachedFiles);
    }
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

  Widget _buildSendButton(bool canSend, bool isDark) {
    return GestureDetector(
      onTapDown: canSend ? (_) => _sendButtonAnimController.forward() : null,
      onTapUp: canSend ? (_) => _sendButtonAnimController.reverse() : null,
      onTapCancel: canSend ? () => _sendButtonAnimController.reverse() : null,
      child: ScaleTransition(
        scale: _sendButtonScale,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: canSend
                ? (isDark ? const Color(0xFF3B82F6) : const Color(0xFF2563EB))
                : (isDark ? const Color(0xFF3A3A3A) : const Color(0xFFE5E5E5)),
            shape: BoxShape.circle,
            boxShadow: canSend
                ? [
                    BoxShadow(
                      color:
                          (isDark
                                  ? const Color(0xFF3B82F6)
                                  : const Color(0xFF2563EB))
                              .withValues(alpha: 0.3),
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
          child: IconButton(
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              transitionBuilder: (child, animation) {
                return ScaleTransition(scale: animation, child: child);
              },
              child: Icon(
                Icons.arrow_upward,
                key: ValueKey(canSend),
                color: canSend
                    ? Colors.white
                    : (isDark
                          ? const Color(0xFF666666)
                          : const Color(0xFF999999)),
              ),
            ),
            onPressed: canSend ? _handleSubmit : null,
            tooltip: 'Send message',
          ),
        ),
      ),
    );
  }

  Widget _buildStopButton() {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.8, end: 1.0),
      duration: const Duration(milliseconds: 200),
      curve: Curves.elasticOut,
      builder: (context, scale, child) {
        return Transform.scale(
          scale: scale,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.red[400],
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.red.withValues(alpha: 0.3),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: IconButton(
              icon: const Icon(Icons.stop, color: Colors.white),
              onPressed: _handleStop,
              tooltip: 'Stop generating',
            ),
          ),
        );
      },
    );
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
        !widget.isStreaming;

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
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            child: _attachedFiles.isEmpty
                ? const SizedBox.shrink()
                : Container(
                    height: 60,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _attachedFiles.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 6),
                      itemBuilder: (context, index) {
                        final file = _attachedFiles[index];
                        return TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0.0, end: 1.0),
                          duration: Duration(milliseconds: 200 + (index * 50)),
                          curve: Curves.easeOut,
                          builder: (context, value, child) {
                            return Opacity(
                              opacity: value,
                              child: Transform.scale(
                                scale: 0.8 + (0.2 * value),
                                child: child,
                              ),
                            );
                          },
                          child: Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.file(
                                  file,
                                  width: 52,
                                  height: 52,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Positioned(
                                top: 0,
                                right: 0,
                                child: GestureDetector(
                                  onTap: () => setState(
                                    () => _attachedFiles.removeAt(index),
                                  ),
                                  child: Container(
                                    width: 18,
                                    height: 18,
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.close,
                                      size: 12,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
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
                          ? const Color(0xFF333333)
                          : const Color(0xFFE5E5E5),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      IconButton(
                        icon: Icon(
                          Icons.attach_file,
                          size: 20,
                          color: isDark
                              ? const Color(0xFF888888)
                              : const Color(0xFF666666),
                        ),
                        onPressed: isConnected ? _handleAttach : null,
                        tooltip: 'Attach image',
                      ),
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          enabled: widget.enabled,
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
                              horizontal: 8,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 150),
                        curve: Curves.easeOut,
                        child: AnimatedOpacity(
                          opacity: _isComposing ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 150),
                          child: _isComposing
                              ? Padding(
                                  padding: const EdgeInsets.only(
                                    right: 12,
                                    bottom: 12,
                                  ),
                                  child: TweenAnimationBuilder<double>(
                                    tween: Tween(begin: 0.5, end: 1.0),
                                    duration: const Duration(milliseconds: 150),
                                    builder: (context, scale, child) {
                                      return Transform.scale(
                                        scale: scale,
                                        child: child,
                                      );
                                    },
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
                                )
                              : const SizedBox(width: 0),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, animation) {
                  return ScaleTransition(
                    scale: animation,
                    child: FadeTransition(opacity: animation, child: child),
                  );
                },
                child: widget.isStreaming
                    ? _buildStopButton()
                    : _buildSendButton(canSend, isDark),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
