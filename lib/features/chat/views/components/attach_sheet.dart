import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import 'package:localmind/core/theme/colors.dart';
import 'package:localmind/features/chat/providers/chat_reasoning_providers.dart';
import 'package:localmind/features/models/data/models/model_info.dart';
import 'package:localmind/l10n/app_localizations.dart';

enum AttachAction { documents, images, savedMessage }

/// Shows the composer's + sheet: sources to attach from, then the options
/// that used to crowd the input bar — thinking effort for reasoning models
/// and, when enabled in settings, sending as the assistant.
///
/// Returns the source the user picked, or `null` if they only changed an
/// option or dismissed the sheet. Thinking changes apply immediately through
/// [chatReasoningConfigProvider]; [onSendAsAssistantChanged] reports the
/// role toggle, which is shown only when [sendAsAssistant] is non-null.
Future<AttachAction?> showAttachSheet(
  BuildContext context, {
  ModelInfo? model,
  bool? sendAsAssistant,
  ValueChanged<bool>? onSendAsAssistantChanged,
}) {
  return showModalBottomSheet<AttachAction>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    isScrollControlled: true,
    showDragHandle: false,
    useSafeArea: true,
    builder: (_) => AttachSheet(
      model: model,
      sendAsAssistant: sendAsAssistant,
      onSendAsAssistantChanged: onSendAsAssistantChanged,
    ),
  );
}

class AttachSheet extends StatefulWidget {
  const AttachSheet({
    super.key,
    this.model,
    this.sendAsAssistant,
    this.onSendAsAssistantChanged,
  });

  final ModelInfo? model;
  final bool? sendAsAssistant;
  final ValueChanged<bool>? onSendAsAssistantChanged;

  @override
  State<AttachSheet> createState() => _AttachSheetState();
}

class _AttachSheetState extends State<AttachSheet> {
  late bool? _sendAsAssistant = widget.sendAsAssistant;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final showThinking = widget.model?.supportsReasoning ?? false;
    final showRole = _sendAsAssistant != null;
    void pick(AttachAction action) => Navigator.of(context).pop(action);
    // The card floats; keep it just clear of the home indicator rather than
    // padding a whole safe area inside it.
    final bottomGap = (MediaQuery.viewPaddingOf(context).bottom - 20).clamp(
      10.0,
      double.infinity,
    );

    return Padding(
      padding: .fromLTRB(10, 0, 10, bottomGap),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
          borderRadius: .circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.12),
              blurRadius: 30,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const .fromLTRB(16, 10, 16, 16),
          child: Column(
            mainAxisSize: .min,
            crossAxisAlignment: .stretch,
            children: [
              const SheetGrabber(),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: AttachSourceTile(
                      key: const ValueKey('attach_images'),
                      icon: HugeIcons.strokeRoundedImage01,
                      label: l10n.attach_shortcut_images,
                      onTap: () => pick(AttachAction.images),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: AttachSourceTile(
                      key: const ValueKey('attach_documents'),
                      icon: HugeIcons.strokeRoundedFolder01,
                      label: l10n.attach_shortcut_documents,
                      onTap: () => pick(AttachAction.documents),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: AttachSourceTile(
                      key: const ValueKey('attach_saved'),
                      icon: HugeIcons.strokeRoundedBookmark01,
                      label: l10n.attach_shortcut_saved,
                      onTap: () => pick(AttachAction.savedMessage),
                    ),
                  ),
                ],
              ),
              if (showThinking || showRole) ...[
                const SizedBox(height: 16),
                Divider(
                  height: 1,
                  color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                ),
                const SizedBox(height: 8),
              ],
              if (showThinking) ThinkingOption(model: widget.model!),
              if (showRole)
                SendAsAssistantOption(
                  value: _sendAsAssistant!,
                  onChanged: (value) {
                    setState(() => _sendAsAssistant = value);
                    widget.onSendAsAssistantChanged?.call(value);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class SheetGrabber extends StatelessWidget {
  const SheetGrabber({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? AppColors.darkMutedText : AppColors.lightMutedText;
    return Center(
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: muted.withValues(alpha: 0.35),
          borderRadius: .circular(2),
        ),
      ),
    );
  }
}

/// One large source button: an icon over a short label.
class AttachSourceTile extends StatelessWidget {
  const AttachSourceTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final List<List<dynamic>> icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = isDark ? AppColors.darkPrimaryText : AppColors.lightPrimaryText;

    return Material(
      color: isDark ? AppColors.darkSurfaceInput : const Color(0xFFF2F2F3),
      borderRadius: .circular(20),
      clipBehavior: .antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 88,
          child: Column(
            mainAxisAlignment: .center,
            children: [
              HugeIcon(icon: icon, color: fg, size: 26),
              const SizedBox(height: 8),
              Text(
                label,
                maxLines: 1,
                overflow: .ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// An options row: icon, title and optional subtitle, and a trailing
/// control or a control underneath.
class AttachOptionRow extends StatelessWidget {
  const AttachOptionRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.below,
  });

  final List<List<dynamic>> icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget? below;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = isDark ? AppColors.darkPrimaryText : AppColors.lightPrimaryText;
    final muted = isDark ? AppColors.darkMutedText : AppColors.lightMutedText;

    return Padding(
      padding: const .symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          Row(
            children: [
              HugeIcon(icon: icon, color: fg, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: .start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: fg,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: TextStyle(fontSize: 12.5, color: muted),
                      ),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
          if (below != null) ...[const SizedBox(height: 10), below!],
        ],
      ),
    );
  }
}

/// Thinking for the selected reasoning model: a segmented choice of Off and
/// each effort the model supports, or a switch for on/off-only models.
class ThinkingOption extends ConsumerWidget {
  const ThinkingOption({super.key, required this.model});

  final ModelInfo model;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final config = ref.watch(chatReasoningConfigProvider);
    final notifier = ref.read(chatReasoningConfigProvider.notifier);
    final canDisable = !model.reasoningMandatory;
    final granular = hasGranularReasoningChoice(
      model.supportedReasoningEfforts,
    );
    final on = config.enabled || !canDisable;

    if (!granular) {
      return AttachOptionRow(
        icon: HugeIcons.strokeRoundedBrain,
        title: l10n.thinking_mode_title,
        trailing: Switch.adaptive(
          value: on,
          onChanged: canDisable ? notifier.setEnabled : null,
        ),
      );
    }

    final efforts = effortsForModel(model.supportedReasoningEfforts);
    final options = [
      if (canDisable) (null, l10n.reasoning_effort_off),
      for (final effort in efforts) (effort, _effortLabel(l10n, effort)),
    ];

    return AttachOptionRow(
      icon: HugeIcons.strokeRoundedBrain,
      title: l10n.thinking_mode_title,
      below: SegmentedPills(
        key: const ValueKey('attach_thinking'),
        labels: [for (final (_, label) in options) label],
        selected: options.indexWhere(
          (o) => on ? o.$1 == config.effort : o.$1 == null,
        ),
        onSelected: (index) {
          final effort = options[index].$1;
          if (effort == null) {
            notifier.setEnabled(false);
          } else {
            notifier.setEnabled(true);
            notifier.setEffort(effort);
          }
        },
      ),
    );
  }

  static String _effortLabel(AppLocalizations l10n, ReasoningEffort effort) =>
      switch (effort) {
        ReasoningEffort.minimal => l10n.reasoning_effort_minimal,
        ReasoningEffort.low => l10n.reasoning_effort_low,
        ReasoningEffort.medium => l10n.reasoning_effort_medium,
        ReasoningEffort.high => l10n.reasoning_effort_high,
        ReasoningEffort.xhigh => l10n.reasoning_effort_xhigh,
        ReasoningEffort.max => l10n.reasoning_effort_max,
      };
}

class SendAsAssistantOption extends StatelessWidget {
  const SendAsAssistantOption({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AttachOptionRow(
      icon: HugeIcons.strokeRoundedExchange01,
      title: l10n.attach_send_as_assistant,
      subtitle: l10n.attach_send_as_assistant_desc,
      trailing: Switch.adaptive(
        key: const ValueKey('attach_send_as_assistant'),
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}

/// A row of equal pills in a track, one selected. Scrolls sideways when a
/// model offers more efforts than fit.
class SegmentedPills extends StatelessWidget {
  const SegmentedPills({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelected,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Fill the width when the pills fit; otherwise let them scroll.
        final minPill = 64.0 * labels.length + 8;
        final fits = constraints.maxWidth >= minPill;
        final track = Container(
          padding: const .all(4),
          decoration: BoxDecoration(
            color: isDark
                ? AppColors.darkSurfaceInput
                : const Color(0xFFF2F2F3),
            borderRadius: .circular(999),
          ),
          child: Row(
            mainAxisSize: fits ? .max : .min,
            children: [
              for (var i = 0; i < labels.length; i++)
                if (fits)
                  Expanded(
                    child: SegmentedPill(
                      label: labels[i],
                      selected: i == selected,
                      onTap: () => onSelected(i),
                    ),
                  )
                else
                  SegmentedPill(
                    label: labels[i],
                    selected: i == selected,
                    onTap: () => onSelected(i),
                  ),
            ],
          ),
        );
        return fits
            ? track
            : SingleChildScrollView(scrollDirection: .horizontal, child: track);
      },
    );
  }
}

class SegmentedPill extends StatelessWidget {
  const SegmentedPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = isDark ? AppColors.darkPrimaryText : AppColors.lightPrimaryText;
    final muted = isDark ? AppColors.darkMutedText : AppColors.lightMutedText;

    return Semantics(
      selected: selected,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          height: 36,
          padding: const .symmetric(horizontal: 14),
          alignment: .center,
          decoration: BoxDecoration(
            color: selected
                ? (isDark ? const Color(0xFF4A4A4A) : Colors.white)
                : Colors.transparent,
            borderRadius: .circular(999),
            boxShadow: [
              if (selected && !isDark)
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 6,
                  offset: const Offset(0, 1),
                ),
            ],
          ),
          child: Text(
            label,
            maxLines: 1,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? fg : muted,
            ),
          ),
        ),
      ),
    );
  }
}
