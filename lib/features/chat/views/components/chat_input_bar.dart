import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:haptic_feedback/haptic_feedback.dart';
import 'package:file_picker/file_picker.dart';
import 'package:hugeicons/hugeicons.dart';
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

  final void Function(String message, {List<File>? attachments}) onSend;
  final VoidCallback onStop;
  final void Function(List<File> attachments)? onAttach;
  final bool enabled;
  final bool isStreaming;

  @override
  ConsumerState<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends ConsumerState<ChatInputBar>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
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
    if (text.isEmpty && _attachedFiles.isEmpty) return;

    Haptics.vibrate(HapticsType.medium);
    widget.onSend(text, attachments: List.from(_attachedFiles));
    _controller.clear();
    setState(() {
      _attachedFiles.clear();
    });
  }

  void _handleStop() {
    Haptics.vibrate(HapticsType.light);
    widget.onStop();
  }

  Widget _buildActionButton(bool canSend, bool isDark) {
    // Action button theme from image: circular, high contrast (black in light, white in dark)
    final backgroundColor = isDark ? Colors.white : Colors.black;
    final iconColor = isDark ? Colors.black : Colors.white;

    return GestureDetector(
      onTapDown: canSend ? (_) => _sendButtonAnimController.forward() : null,
      onTapUp: canSend ? (_) => _sendButtonAnimController.reverse() : null,
      onTapCancel: canSend ? () => _sendButtonAnimController.reverse() : null,
      child: ScaleTransition(
        scale: _sendButtonScale,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: backgroundColor.withValues(
              alpha: (canSend || widget.isStreaming) ? 1.0 : 0.2,
            ),
            shape: BoxShape.circle,
          ),
          child: IconButton(
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              transitionBuilder: (child, animation) {
                return ScaleTransition(scale: animation, child: child);
              },
              child: widget.isStreaming
                  ? HugeIcon(
                      icon: HugeIcons.strokeRoundedStop,
                      key: const ValueKey('stop'),
                      color: iconColor,
                      size: 20,
                    )
                  : HugeIcon(
                      icon: HugeIcons.strokeRoundedArrowUp01,
                      key: ValueKey(canSend),
                      color: iconColor,
                      size: 20,
                    ),
            ),
            onPressed: widget.isStreaming
                ? _handleStop
                : (canSend ? _handleSubmit : null),
            tooltip: widget.isStreaming ? 'Stop generation' : 'Send message',
          ),
        ),
      ),
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
        (_controller.text.trim().isNotEmpty || _attachedFiles.isNotEmpty) &&
        !widget.isStreaming;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1C) : Colors.white,
        borderRadius: BorderRadius.circular(40),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: isDark ? const Color(0xFF2E2E2E) : const Color(0xFFE5E5E5),
          width: 1.2,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Attachment Preview Area
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            child: _attachedFiles.isEmpty
                ? const SizedBox.shrink()
                : Container(
                    height: 70,
                    padding: const EdgeInsets.only(
                      left: 12,
                      right: 12,
                      top: 8,
                      bottom: 4,
                    ),
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _attachedFiles.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final file = _attachedFiles[index];
                        return Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isDark
                                      ? const Color(0xFF333333)
                                      : const Color(0xFFE0E0E0),
                                ),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(11),
                                child: Image.file(
                                  file,
                                  width: 48,
                                  height: 48,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                            Positioned(
                              top: -4,
                              right: -4,
                              child: GestureDetector(
                                onTap: () => setState(
                                  () => _attachedFiles.removeAt(index),
                                ),
                                child: Container(
                                  width: 18,
                                  height: 18,
                                  decoration: const BoxDecoration(
                                    color: Colors.black,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.close,
                                    size: 10,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
          ),
          // Input Main Bar
          Row(
            children: [
              // Add Attachment Button
              IconButton(
                icon: HugeIcon(
                  icon: HugeIcons.strokeRoundedPlusSign,
                  color: isDark ? Colors.white70 : Colors.black87,
                  size: 22,
                ),
                onPressed: isConnected ? _handleAttach : null,
                tooltip: 'Attach images',
              ),
              const SizedBox(width: 4),
              // Text Field
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  enabled: widget.enabled,
                  maxLines: 5,
                  minLines: 1,
                  textInputAction: TextInputAction.newline,
                  keyboardType: TextInputType.multiline,
                  onChanged: (text) {
                    setState(() {});
                  },
                  style: TextStyle(
                    fontSize: 15,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Ask anything',
                    hintStyle: TextStyle(
                      color: isDark ? Colors.white38 : Colors.black38,
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Mic Icon (Visual only as per image)
              // HugeIcon(
              //   icon: HugeIcons.strokeRoundedMic01,
              //   color: isDark ? Colors.white38 : Colors.black38,
              //   size: 22,
              // ),
              // const SizedBox(width: 8),
              // Action Button (Send/Stop)
              _buildActionButton(canSend, isDark),
            ],
          ),
        ],
      ),
    );
  }
}
