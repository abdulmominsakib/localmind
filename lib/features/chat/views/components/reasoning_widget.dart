import 'package:hugeicons/hugeicons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:localmind/core/providers/app_providers.dart';
import 'package:localmind/l10n/app_localizations.dart';
import 'package:localmind/core/theme/colors.dart';

class ReasoningWidget extends ConsumerStatefulWidget {
  final String? reasoningContent;
  final bool isStreaming;
  final bool hasMainContent;

  const ReasoningWidget({
    super.key,
    this.reasoningContent,
    this.isStreaming = false,
    this.hasMainContent = true,
  });

  @override
  ConsumerState<ReasoningWidget> createState() => _ReasoningWidgetState();
}

class _ReasoningWidgetState extends ConsumerState<ReasoningWidget>
    with SingleTickerProviderStateMixin {
  late bool _isExpanded;
  bool _hasUserManuallyToggled = false;
  late AnimationController _animationController;
  late Animation<double> _expandAnimation;

  @override
  void initState() {
    super.initState();
    final autoCollapse = ref.read(
      settingsProvider.select((s) => s.autoCollapseThinking),
    );
    _isExpanded = widget.isStreaming || !widget.hasMainContent || !autoCollapse;
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _expandAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.fastOutSlowIn,
    );
    if (_isExpanded) {
      _animationController.value = 1.0;
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(ReasoningWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isStreaming && !oldWidget.isStreaming) {
      if (!_isExpanded) {
        setState(() {
          _isExpanded = true;
          _animationController.forward();
        });
      }
    } else if (!widget.isStreaming && oldWidget.isStreaming) {
      if (!_hasUserManuallyToggled) {
        final autoCollapse = ref.read(
          settingsProvider.select((s) => s.autoCollapseThinking),
        );
        final shouldStayExpanded = !widget.hasMainContent || !autoCollapse;
        if (!shouldStayExpanded && _isExpanded) {
          setState(() {
            _isExpanded = false;
            _animationController.reverse();
          });
        }
      }
    }
  }

  void _toggleExpand() {
    setState(() {
      _hasUserManuallyToggled = true;
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final hasContent = widget.reasoningContent?.isNotEmpty == true;

    if (!hasContent && !widget.isStreaming) {
      return const SizedBox.shrink();
    }

    final reasoningTextColor = Color.lerp(
      isDark ? AppColors.darkPrimaryText : AppColors.lightPrimaryText,
      isDark ? AppColors.darkMutedText : AppColors.lightMutedText,
      0.35,
    )!;

    final reasoningHighlightColor = isDark
        ? AppColors.darkSurface.withValues(alpha: 0.9)
        : const Color(0xFFF4F4F5);

    return Container(
      margin: const EdgeInsets.only(bottom: 12, top: 4),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceInput : AppColors.lightSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row
            InkWell(
              onTap: _toggleExpand,
              borderRadius: BorderRadius.circular(11),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    HugeIcon(
                      icon: HugeIcons.strokeRoundedBrain,
                      size: 18,
                      color: isDark
                          ? AppColors.darkMutedText
                          : AppColors.lightMutedText,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l10n.thinking,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                        color: isDark
                            ? AppColors.darkMutedText
                            : AppColors.lightMutedText,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (widget.isStreaming) ...[
                      SizedBox(
                        width: 10,
                        height: 10,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                    const Spacer(),
                    RotationTransition(
                      turns: Tween(
                        begin: 0.0,
                        end: 0.5,
                      ).animate(_expandAnimation),
                      child: HugeIcon(
                        icon: HugeIcons.strokeRoundedArrowDown01,
                        size: 18,
                        color: isDark
                            ? AppColors.darkMutedText
                            : AppColors.lightMutedText,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Expandable content
            SizeTransition(
              sizeFactor: _expandAnimation,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GptMarkdownTheme(
                      gptThemeData: GptMarkdownThemeData(
                        brightness: isDark ? Brightness.dark : Brightness.light,
                        highlightColor: reasoningHighlightColor,
                        linkColor: theme.colorScheme.primary,
                      ),
                      child: GptMarkdown(
                        widget.reasoningContent ?? '',
                        style: TextStyle(
                          fontSize: 13,
                          color: reasoningTextColor,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
