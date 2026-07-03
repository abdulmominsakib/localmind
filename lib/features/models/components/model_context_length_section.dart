import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:localmind/core/providers/app_providers.dart';
import 'package:localmind/core/theme/colors.dart';
import 'package:localmind/features/conversations/providers/conversation_providers.dart'
    as conv;
import 'package:localmind/l10n/app_localizations.dart';

class ModelContextLengthSection extends ConsumerStatefulWidget {
  const ModelContextLengthSection({super.key, required this.isDark});

  final bool isDark;

  @override
  ConsumerState<ModelContextLengthSection> createState() =>
      _ModelContextLengthSectionState();
}

class _ModelContextLengthSectionState
    extends ConsumerState<ModelContextLengthSection> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  int? _lastValue;
  String? _activeConversationId;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    // Most users dismiss the keyboard by tapping elsewhere rather than
    // pressing a keyboard "done" action, which doesn't fire onSubmitted
    // or onEditingComplete. Save on focus loss too so typed values apply.
    if (!_focusNode.hasFocus) {
      _saveValue(_controller.text, _activeConversationId);
    }
  }

  void _syncController(int value) {
    if (_lastValue == value) return;
    _lastValue = value;
    _controller.text = value.toString();
  }

  void _saveValue(String raw, String? conversationId) {
    final parsed = int.tryParse(raw.trim());
    if (parsed == null || parsed <= 0 || parsed == _lastValue) return;

    if (conversationId == null) {
      ref.read(settingsProvider.notifier).setContextLength(parsed);
    } else {
      ref.read(conv.conversationsProvider.notifier).updateChatParams(
            conversationId,
            contextLength: parsed,
          );
    }
    _lastValue = parsed;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings = ref.watch(settingsProvider);
    final activeConv = ref.watch(conv.activeConversationProvider);
    final contextLength = activeConv?.contextLength ?? settings.contextLength;
    _activeConversationId = activeConv?.id;
    _syncController(contextLength);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.context_length,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: widget.isDark ? Colors.white : Colors.black,
          ),
        ),
        const SizedBox(height: 6),
        ShadInput(
          controller: _controller,
          focusNode: _focusNode,
          keyboardType: TextInputType.number,
          onSubmitted: (value) =>
              _saveValue(value, activeConv?.id),
          onEditingComplete: () =>
              _saveValue(_controller.text, activeConv?.id),
        ),
        const SizedBox(height: 4),
        Text(
          l10n.context_length_desc,
          style: TextStyle(
            fontSize: 11,
            color: widget.isDark
                ? AppColors.darkMutedText
                : AppColors.lightMutedText,
          ),
        ),
      ],
    );
  }
}
