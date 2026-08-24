import 'package:hugeicons/hugeicons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:localmind/l10n/app_localizations.dart';
import '../../providers/conversation_providers.dart';

class ConversationSearchBar extends ConsumerStatefulWidget {
  const ConversationSearchBar({super.key});

  @override
  ConsumerState<ConversationSearchBar> createState() =>
      _ConversationSearchBarState();
}

class _ConversationSearchBarState extends ConsumerState<ConversationSearchBar> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  int _lastFocusRequest = 0;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _requestSearchFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(focusHistorySearchProvider, (previous, next) {
      if (next != _lastFocusRequest) {
        _lastFocusRequest = next;
        _requestSearchFocus();
      }
    });

    final pendingFocus = ref.watch(focusHistorySearchProvider);
    if (pendingFocus != _lastFocusRequest) {
      _lastFocusRequest = pendingFocus;
      _requestSearchFocus();
    }

    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final searchContents = ref.watch(searchMessageContentsProvider);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE5E5E5),
        ),
      ),
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        onChanged: (value) {
          ref.read(conversationSearchProvider.notifier).setSearchQuery(value);
          setState(() {});
        },
        style: TextStyle(
          fontSize: 14,
          color: isDark ? Colors.white : Colors.black,
        ),
        decoration: InputDecoration(
          hintText: l10n.search_hint,
          hintStyle: TextStyle(
            fontSize: 14,
            color: isDark ? const Color(0xFF666666) : const Color(0xFF999999),
          ),
          prefixIcon: Center(
            widthFactor: 1.0,
            heightFactor: 1.0,
            child: HugeIcon(
              icon: HugeIcons.strokeRoundedSearch01,
              size: 20,
              color: isDark ? const Color(0xFF666666) : const Color(0xFF999999),
            ),
          ),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: HugeIcon(
                  icon: searchContents
                      ? HugeIcons.strokeRoundedDocumentCode
                      : HugeIcons.strokeRoundedDocumentCode,
                  size: 20,
                  color: searchContents
                      ? theme.colorScheme.primary
                      : (isDark
                            ? const Color(0xFF666666)
                            : const Color(0xFF999999)),
                ),
                tooltip: l10n.search_message_contents,
                onPressed: () =>
                    ref.read(searchMessageContentsProvider.notifier).toggle(),
              ),
              if (_controller.text.isNotEmpty)
                IconButton(
                  icon: HugeIcon(
                    icon: HugeIcons.strokeRoundedCancel01,
                    size: 18,
                    color: isDark
                        ? const Color(0xFF666666)
                        : const Color(0xFF999999),
                  ),
                  onPressed: () {
                    _controller.clear();
                    ref.read(conversationSearchProvider.notifier).clearSearch();
                    setState(() {});
                  },
                ),
            ],
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
      ),
    );
  }
}
