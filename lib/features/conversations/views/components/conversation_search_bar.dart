import 'package:hugeicons/hugeicons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:localmind/core/theme/colors.dart';
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? AppColors.darkMutedText : AppColors.lightMutedText;
    final searchContents = ref.watch(searchMessageContentsProvider);

    // "Search inside messages" lives in the screen's menu; the hint says
    // which mode is on instead of an unexplained icon in the field.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: TextField(
        key: const ValueKey('history_search'),
        controller: _controller,
        focusNode: _focusNode,
        onChanged: (value) {
          ref.read(conversationSearchProvider.notifier).setSearchQuery(value);
          setState(() {});
        },
        style: TextStyle(
          fontSize: 15,
          color: isDark
              ? AppColors.darkPrimaryText
              : AppColors.lightPrimaryText,
        ),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: isDark
              ? AppColors.darkSurfaceInput
              : AppColors.lightSurface,
          hintText: searchContents
              ? l10n.search_message_contents
              : l10n.search_hint,
          hintStyle: TextStyle(fontSize: 15, color: muted),
          prefixIcon: Padding(
            padding: const EdgeInsetsDirectional.only(start: 14, end: 10),
            child: HugeIcon(
              icon: HugeIcons.strokeRoundedSearch01,
              size: 18,
              color: muted,
            ),
          ),
          prefixIconConstraints: const BoxConstraints(),
          suffixIcon: _controller.text.isEmpty
              ? null
              : IconButton(
                  icon: HugeIcon(
                    icon: HugeIcons.strokeRoundedCancelCircle,
                    size: 18,
                    color: muted,
                  ),
                  tooltip: MaterialLocalizations.of(context).clearButtonTooltip,
                  onPressed: () {
                    _controller.clear();
                    ref.read(conversationSearchProvider.notifier).clearSearch();
                    setState(() {});
                  },
                ),
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: muted),
          ),
        ),
      ),
    );
  }
}
