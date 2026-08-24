import 'package:hugeicons/hugeicons.dart';
import 'package:flutter/material.dart';
import 'package:localmind/core/theme/colors.dart';
import 'package:localmind/features/chat/data/tools/tool_event.dart';
import 'package:localmind/features/chat/data/tools/tool_definition.dart';
import 'package:localmind/features/chat/data/models/grouped_tool_call.dart';
import 'package:localmind/l10n/app_localizations.dart';
import 'tool_inline_badge.dart';

class ToolRowWidget extends StatefulWidget {
  const ToolRowWidget({
    super.key,
    required this.call,
    required this.isDark,
    required this.formatArgs,
  });

  final GroupedToolCall call;
  final bool isDark;
  final String Function(Map<String, dynamic>) formatArgs;

  @override
  State<ToolRowWidget> createState() => _ToolRowWidgetState();
}

class _ToolRowWidgetState extends State<ToolRowWidget> {
  late bool _isExpanded;

  @override
  void initState() {
    super.initState();
    _isExpanded =
        widget.call.status == ToolEventStatus.running ||
        widget.call.status == ToolEventStatus.failed ||
        widget.call.status == ToolEventStatus.requested ||
        widget.call.status == ToolEventStatus.approved;
  }

  @override
  void didUpdateWidget(ToolRowWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.call.status != widget.call.status) {
      if (widget.call.status == ToolEventStatus.running ||
          widget.call.status == ToolEventStatus.failed ||
          widget.call.status == ToolEventStatus.requested ||
          widget.call.status == ToolEventStatus.approved) {
        setState(() {
          _isExpanded = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final call = widget.call;
    final isDark = widget.isDark;
    final isMcpTool = call.providerType == ToolProviderType.mcp;

    final iconColor = switch (call.status) {
      ToolEventStatus.completed => const Color(0xFF22C55E),
      ToolEventStatus.failed ||
      ToolEventStatus.rejected => const Color(0xFFEF4444),
      ToolEventStatus.running => AppColors.darkAccent,
      ToolEventStatus.requested ||
      ToolEventStatus.approved => const Color(0xFFF59E0B),
    };

    final statusLabel = switch (call.status) {
      ToolEventStatus.requested => l10n.tool_status_requested,
      ToolEventStatus.approved => l10n.tool_status_approved,
      ToolEventStatus.rejected => l10n.tool_status_rejected,
      ToolEventStatus.running => l10n.tool_status_running,
      ToolEventStatus.completed => l10n.tool_status_done,
      ToolEventStatus.failed => l10n.tool_status_failed,
    };

    final showCodeBlock =
        (call.arguments != null && call.arguments!.isNotEmpty) ||
        (call.result != null && call.result!.isNotEmpty) ||
        (call.error != null && call.error!.isNotEmpty);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: showCodeBlock
                ? () => setState(() => _isExpanded = !_isExpanded)
                : null,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (call.status == ToolEventStatus.running)
                    _AnimatedRunningIcon(color: iconColor)
                  else
                    HugeIcon(
                      icon: switch (call.status) {
                        ToolEventStatus.requested =>
                          HugeIcons.strokeRoundedClock01,
                        ToolEventStatus.approved =>
                          HugeIcons.strokeRoundedCheckmarkCircle01,
                        ToolEventStatus.rejected =>
                          HugeIcons.strokeRoundedUnavailable,
                        ToolEventStatus.running =>
                          HugeIcons.strokeRoundedRefresh,
                        ToolEventStatus.completed =>
                          HugeIcons.strokeRoundedCheckmarkCircle01,
                        ToolEventStatus.failed =>
                          HugeIcons.strokeRoundedAlertCircle,
                      },
                      size: 14,
                      color: iconColor,
                    ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            call.toolName,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black87,
                              fontFamily: 'monospace',
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (isMcpTool) ...[
                          InlineToolBadge(
                            label: 'MCP',
                            backgroundColor: Colors.purple.withValues(
                              alpha: isDark ? 0.2 : 0.1,
                            ),
                            textColor: isDark
                                ? const Color(0xFFC084FC)
                                : const Color(0xFF7E22CE),
                          ),
                        ] else if (call.providerType ==
                            ToolProviderType.lmStudioServer) ...[
                          InlineToolBadge(
                            label: 'LM Studio',
                            backgroundColor: Colors.orange.withValues(
                              alpha: isDark ? 0.2 : 0.1,
                            ),
                            textColor: isDark
                                ? const Color(0xFFF97316)
                                : const Color(0xFFC2410C),
                          ),
                        ] else ...[
                          InlineToolBadge(
                            label: l10n.local_label,
                            backgroundColor: Colors.blue.withValues(
                              alpha: isDark ? 0.2 : 0.1,
                            ),
                            textColor: isDark
                                ? const Color(0xFF60A5FA)
                                : const Color(0xFF1D4ED8),
                          ),
                        ],
                        const SizedBox(width: 6),
                        InlineToolBadge(
                          label: statusLabel,
                          backgroundColor: iconColor.withValues(
                            alpha: isDark ? 0.15 : 0.1,
                          ),
                          textColor: iconColor,
                        ),
                      ],
                    ),
                  ),
                  if (call.durationMs != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      '${call.durationMs}ms',
                      style: TextStyle(
                        fontSize: 10,
                        color: isDark
                            ? AppColors.darkMutedText
                            : AppColors.lightMutedText,
                      ),
                    ),
                  ],
                  if (showCodeBlock) ...[
                    const SizedBox(width: 6),
                    HugeIcon(
                      icon: _isExpanded
                          ? HugeIcons.strokeRoundedArrowUp01
                          : HugeIcons.strokeRoundedArrowDown01,
                      size: 16,
                      color: isDark
                          ? AppColors.darkMutedText
                          : AppColors.lightMutedText,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (showCodeBlock && _isExpanded)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 22),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF0F172A)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF1E293B)
                        : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (call.arguments != null &&
                        call.arguments!.isNotEmpty) ...[
                      Text(
                        'Arguments:',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: isDark
                              ? const Color(0xFF38BDF8)
                              : const Color(0xFF0284C7),
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.formatArgs(call.arguments!),
                        style: TextStyle(
                          fontSize: 10.5,
                          color: isDark
                              ? const Color(0xFFCBD5E1)
                              : const Color(0xFF475569),
                          fontFamily: 'monospace',
                          height: 1.3,
                        ),
                      ),
                    ],
                    if (call.result != null && call.result!.isNotEmpty) ...[
                      if (call.arguments != null && call.arguments!.isNotEmpty)
                        const SizedBox(height: 8),
                      Text(
                        'Output:',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: isDark
                              ? const Color(0xFF4ADE80)
                              : const Color(0xFF16A34A),
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        call.result!,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: isDark
                              ? const Color(0xFFF8FAFC)
                              : const Color(0xFF0F172A),
                          fontFamily: 'monospace',
                          height: 1.3,
                        ),
                      ),
                    ],
                    if (call.error != null && call.error!.isNotEmpty) ...[
                      if (call.arguments != null && call.arguments!.isNotEmpty)
                        const SizedBox(height: 8),
                      Text(
                        'Error:',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: isDark
                              ? const Color(0xFFF87171)
                              : const Color(0xFFDC2626),
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        call.error!,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: isDark
                              ? const Color(0xFFFCA5A5)
                              : const Color(0xFF991B1B),
                          fontFamily: 'monospace',
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AnimatedRunningIcon extends StatefulWidget {
  const _AnimatedRunningIcon({required this.color});
  final Color color;

  @override
  State<_AnimatedRunningIcon> createState() => _AnimatedRunningIconState();
}

class _AnimatedRunningIconState extends State<_AnimatedRunningIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _controller,
      child: HugeIcon(
        icon: HugeIcons.strokeRoundedRefresh,
        size: 14,
        color: widget.color,
      ),
    );
  }
}
