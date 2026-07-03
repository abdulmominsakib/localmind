import 'dart:async';

import 'package:flutter/material.dart';
import 'package:localmind/core/theme/colors.dart';
import 'package:localmind/l10n/app_localizations.dart';
import 'recent_conversation_item.dart';

class EmptyState extends StatefulWidget {
  const EmptyState({
    super.key,
    required this.onQuickPrompt,
    required this.quickPrompts,
    required this.recentConversations,
    required this.onSeeAll,
    required this.selectedModel,
    required this.onModelTap,
    this.selectedPersonas = const [],
    required this.onPersonaTap,
  });

  final void Function(String) onQuickPrompt;
  final List<String> quickPrompts;
  final List<dynamic> recentConversations;
  final VoidCallback onSeeAll;
  final dynamic selectedModel;
  final VoidCallback onModelTap;
  final List<dynamic> selectedPersonas;
  final VoidCallback onPersonaTap;

  @override
  State<EmptyState> createState() => _EmptyStateState();
}

class _EmptyStateState extends State<EmptyState>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late List<Animation<double>> _fadeAnimations;
  late List<Animation<Offset>> _slideAnimations;
  Timer? _welcomeTimer;
  int _welcomeIndex = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _fadeAnimations = List.generate(widget.quickPrompts.length, (index) {
      return Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: _controller,
          curve: Interval(
            (index * 0.1).clamp(0.0, 0.7),
            (0.3 + index * 0.1).clamp(0.2, 1.0),
            curve: Curves.easeOut,
          ),
        ),
      );
    });

    _slideAnimations = List.generate(widget.quickPrompts.length, (index) {
      return Tween<Offset>(
        begin: const Offset(0.0, 0.3),
        end: Offset.zero,
      ).animate(
        CurvedAnimation(
          parent: _controller,
          curve: Interval(
            (index * 0.1).clamp(0.0, 0.7),
            (0.3 + index * 0.1).clamp(0.2, 1.0),
            curve: Curves.easeOutCubic,
          ),
        ),
      );
    });

    _controller.forward();
    _welcomeTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      setState(() => _welcomeIndex = (_welcomeIndex + 1) % 4);
    });
  }

  @override
  void dispose() {
    _welcomeTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  List<String> _welcomeMessages(AppLocalizations l10n) => [
        l10n.welcome_message_1,
        l10n.welcome_message_2,
        l10n.welcome_message_3,
        l10n.welcome_message_4,
      ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 8, 32, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            height: 72,
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                layoutBuilder: (current, previous) => Stack(
                  alignment: Alignment.center,
                  children: [...previous, if (current != null) current],
                ),
                child: Text(
                  _welcomeMessages(l10n)[_welcomeIndex],
                  key: ValueKey(_welcomeIndex),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _buildModelAndPersonaSelectors(isDark, theme, l10n),
          const SizedBox(height: 24),
          _buildQuickPrompts(isDark),
          if (widget.recentConversations.isNotEmpty) ...[
            const SizedBox(height: 28),
            _buildRecentSection(isDark, l10n),
          ],
        ],
      ),
    );
  }

  Widget _buildModelAndPersonaSelectors(
    bool isDark,
    ThemeData theme,
    AppLocalizations l10n,
  ) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - value)),
            child: child,
          ),
        );
      },
      child: Column(
        children: [
          GestureDetector(
            onTap: widget.onModelTap,
            child: _buildSelectorCard(
              isDark: isDark,
              theme: theme,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.settings_suggest,
                      size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      widget.selectedModel?.displayName ?? l10n.select_model,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.expand_more, size: 16, color: Colors.grey),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: widget.onPersonaTap,
            child: _buildSelectorCard(
              isDark: isDark,
              theme: theme,
              child: Row(
                mainAxisSize: widget.selectedPersonas.isEmpty
                    ? MainAxisSize.min
                    : MainAxisSize.max,
                children: [
                  if (widget.selectedPersonas.isNotEmpty) ...[
                    Flexible(
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: widget.selectedPersonas.map((persona) {
                          return Text(
                            '${persona.emoji} ${persona.name}',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : Colors.black,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          );
                        }).toList(),
                      ),
                    ),
                  ] else ...[
                    Icon(Icons.smart_toy_outlined,
                        size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        l10n.select_persona,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  const SizedBox(width: 4),
                  const Icon(Icons.expand_more, size: 16, color: Colors.grey),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectorCard({
    required bool isDark,
    required ThemeData theme,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkBackground : AppColors.lightSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
        ),
      ),
      child: child,
    );
  }

  Widget _buildQuickPrompts(bool isDark) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: widget.quickPrompts.asMap().entries.map((entry) {
        final index = entry.key;
        final prompt = entry.value;
        final fadeAnimation = index < _fadeAnimations.length
            ? _fadeAnimations[index]
            : const AlwaysStoppedAnimation(1.0);
        final slideAnimation = index < _slideAnimations.length
            ? _slideAnimations[index]
            : const AlwaysStoppedAnimation(Offset.zero);

        return AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return FadeTransition(
              opacity: fadeAnimation,
              child: SlideTransition(
                position: slideAnimation,
                child: child,
              ),
            );
          },
          child: ActionChip(
            label: Text(prompt),
            onPressed: () => widget.onQuickPrompt(prompt),
            backgroundColor:
                isDark ? AppColors.darkSurfaceCard : AppColors.lightSurface,
            side: BorderSide(
              color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildRecentSection(bool isDark, AppLocalizations l10n) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              l10n.recent_chats,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color:
                    isDark ? AppColors.darkMutedText : AppColors.lightMutedText,
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: widget.onSeeAll,
              child: Text(
                l10n.see_all,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: isDark ? AppColors.darkAccent : AppColors.lightAccent,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...List.generate(widget.recentConversations.take(5).length, (index) {
          final conv = widget.recentConversations.take(5).toList()[index];
          return TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: Duration(milliseconds: 400 + (index * 50)),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) {
              return Opacity(
                opacity: value,
                child: Transform.translate(
                  offset: Offset(0, 10 * (1 - value)),
                  child: child,
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: RecentConversationItem(conversation: conv),
            ),
          );
        }),
      ],
    );
  }
}
