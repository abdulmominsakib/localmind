import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../../../core/providers/app_providers.dart';
import '../../../conversations/providers/conversation_providers.dart' as conv;

class ChatFilterSheet extends ConsumerWidget {
  const ChatFilterSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final activeConv = ref.watch(conv.activeConversationProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Use per-conversation values if set, otherwise fall back to app defaults
    final temperature = activeConv?.temperature ?? settings.temperature;
    final topP = activeConv?.topP ?? settings.topP;
    final maxTokens = activeConv?.maxTokens ?? settings.maxTokens;
    final contextLength = activeConv?.contextLength ?? settings.contextLength;

    final hasOverrides = activeConv?.temperature != null ||
        activeConv?.topP != null ||
        activeConv?.maxTokens != null ||
        activeConv?.contextLength != null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F1F1F) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF3A3A3A)
                      : const Color(0xFFE5E5E5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                HugeIcon(
                  icon: HugeIcons.strokeRoundedFilterHorizontal,
                  size: 24,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Chat Parameters',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                const Spacer(),
                if (hasOverrides)
                  TextButton.icon(
                    onPressed: () => _resetToDefaults(ref, activeConv?.id),
                    icon: const Icon(Icons.restore, size: 16),
                    label: const Text('Reset'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'These parameters control how the model responds. Tap Reset to use app defaults.',
              style: TextStyle(
                fontSize: 12,
                color: isDark
                    ? const Color(0xFF666666)
                    : const Color(0xFF999999),
              ),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _SliderParam(
                      label: 'Temperature',
                      value: temperature,
                      min: 0.0,
                      max: 2.0,
                      divisions: 20,
                      description:
                          'Controls randomness. Lower = focused, Higher = creative.',
                      onChanged: (v) => _updateParam(
                        ref,
                        activeConv?.id,
                        temperature: v,
                      ),
                      isDark: isDark,
                    ),
                    _SliderParam(
                      label: 'Top P',
                      value: topP,
                      min: 0.0,
                      max: 1.0,
                      divisions: 10,
                      description: 'Nucleus sampling threshold. Lower = more focused.',
                      onChanged: (v) => _updateParam(
                        ref,
                        activeConv?.id,
                        topP: v,
                      ),
                      isDark: isDark,
                    ),
                    _IntParam(
                      label: 'Max Tokens',
                      value: maxTokens,
                      description: 'Maximum response length in tokens.',
                      onChanged: (v) => _updateParam(
                        ref,
                        activeConv?.id,
                        maxTokens: v,
                      ),
                      isDark: isDark,
                    ),
                    _IntParam(
                      label: 'Context Length',
                      value: contextLength,
                      description: 'Conversation history window in tokens.',
                      onChanged: (v) => _updateParam(
                        ref,
                        activeConv?.id,
                        contextLength: v,
                      ),
                      isDark: isDark,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _updateParam(
    WidgetRef ref,
    String? conversationId, {
    double? temperature,
    double? topP,
    int? maxTokens,
    int? contextLength,
  }) {
    if (conversationId == null) {
      // No active conversation — update app-level defaults instead
      final notifier = ref.read(settingsProvider.notifier);
      if (temperature != null) notifier.setTemperature(temperature);
      if (topP != null) notifier.setTopP(topP);
      if (maxTokens != null) notifier.setMaxTokens(maxTokens);
      if (contextLength != null) notifier.setContextLength(contextLength);
      return;
    }

    ref.read(conv.conversationsProvider.notifier).updateChatParams(
      conversationId,
      temperature: temperature,
      topP: topP,
      maxTokens: maxTokens,
      contextLength: contextLength,
    );
  }

  void _resetToDefaults(WidgetRef ref, String? conversationId) {
    if (conversationId == null) return;
    ref.read(conv.conversationsProvider.notifier).updateChatParams(
      conversationId,
      clearTemperature: true,
      clearTopP: true,
      clearMaxTokens: true,
      clearContextLength: true,
    );
  }
}

class _SliderParam extends StatelessWidget {
  const _SliderParam({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.description,
    required this.onChanged,
    required this.isDark,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String description;
  final ValueChanged<double> onChanged;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              Text(
                value.toStringAsFixed(2),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? const Color(0xFF3B82F6)
                      : const Color(0xFF2563EB),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
              activeTrackColor: isDark
                  ? const Color(0xFF3B82F6)
                  : const Color(0xFF2563EB),
              thumbColor: isDark
                  ? const Color(0xFF3B82F6)
                  : const Color(0xFF2563EB),
              inactiveTrackColor: isDark
                  ? const Color(0xFF3A3A3A)
                  : const Color(0xFFE5E5E5),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
          Text(
            description,
            style: TextStyle(
              fontSize: 12,
              color: isDark
                  ? const Color(0xFF666666)
                  : const Color(0xFF999999),
            ),
          ),
        ],
      ),
    );
  }
}

class _IntParam extends StatefulWidget {
  const _IntParam({
    required this.label,
    required this.value,
    required this.description,
    required this.onChanged,
    required this.isDark,
  });

  final String label;
  final int value;
  final String description;
  final ValueChanged<int> onChanged;
  final bool isDark;

  @override
  State<_IntParam> createState() => _IntParamState();
}

class _IntParamState extends State<_IntParam> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value.toString());
  }

  @override
  void didUpdateWidget(_IntParam old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      _controller.text = widget.value.toString();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: widget.isDark ? Colors.white : Colors.black,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: 120,
            child: TextField(
              controller: _controller,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onChanged: (text) {
                final val = int.tryParse(text);
                if (val != null && val > 0) widget.onChanged(val);
              },
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.description,
            style: TextStyle(
              fontSize: 12,
              color: widget.isDark
                  ? const Color(0xFF666666)
                  : const Color(0xFF999999),
            ),
          ),
        ],
      ),
    );
  }
}

void showChatFilterSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const ChatFilterSheet(),
  );
}
