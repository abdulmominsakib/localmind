import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:localmind/core/providers/app_providers.dart';
import 'package:localmind/core/providers/storage_providers.dart' as storage;
import 'package:localmind/core/theme/app_theme.dart';
import 'package:localmind/features/conversations/providers/conversation_providers.dart';
import 'package:localmind/features/servers/providers/server_providers.dart';
import 'package:localmind/features/settings/data/models/app_settings.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          _SectionHeader(title: 'Chat Parameters'),
          _SliderSetting(
            label: 'Temperature',
            value: settings.temperature,
            min: 0.0,
            max: 2.0,
            divisions: 20,
            description:
                'Controls randomness. Lower = focused, Higher = creative.',
            onChanged: (v) =>
                ref.read(settingsProvider.notifier).setTemperature(v),
            isDark: isDark,
          ),
          _SliderSetting(
            label: 'Top P',
            value: settings.topP,
            min: 0.0,
            max: 1.0,
            divisions: 10,
            description: 'Nucleus sampling threshold. Lower = more focused.',
            onChanged: (v) => ref.read(settingsProvider.notifier).setTopP(v),
            isDark: isDark,
          ),
          _IntInputSetting(
            label: 'Max Tokens',
            value: settings.maxTokens,
            description: 'Maximum response length in tokens.',
            onChanged: (v) =>
                ref.read(settingsProvider.notifier).setMaxTokens(v),
            isDark: isDark,
          ),
          _IntInputSetting(
            label: 'Context Length',
            value: settings.contextLength,
            description: 'Conversation history window in tokens.',
            onChanged: (v) =>
                ref.read(settingsProvider.notifier).setContextLength(v),
            isDark: isDark,
          ),
          const Divider(height: 32),
          _SectionHeader(title: 'Appearance'),
          _ThemeToggle(current: settings.themeMode, ref: ref),
          _SliderSetting(
            label: 'Font Size',
            value: settings.fontSize,
            min: 12.0,
            max: 24.0,
            divisions: 12,
            description: 'Adjust text size in chat.',
            onChanged: (v) =>
                ref.read(settingsProvider.notifier).setFontSize(v),
            isDark: isDark,
            valueFormat: (v) => v.toStringAsFixed(0),
            previewText: 'The quick brown fox jumps over the lazy dog.',
          ),
          _CodeThemeDropdown(
            label: 'Code Theme (Dark)',
            current: settings.codeThemeDark,
            onChanged: (v) =>
                ref.read(settingsProvider.notifier).setCodeThemeDark(v),
            isDark: isDark,
          ),
          _CodeThemeDropdown(
            label: 'Code Theme (Light)',
            current: settings.codeThemeLight,
            onChanged: (v) =>
                ref.read(settingsProvider.notifier).setCodeThemeLight(v),
            isDark: isDark,
          ),
          const Divider(height: 32),
          _SectionHeader(title: 'Behavior'),
          _ToggleSetting(
            label: 'Streaming Responses',
            value: settings.streamingEnabled,
            onChanged: (v) =>
                ref.read(settingsProvider.notifier).setStreamingEnabled(v),
            isDark: isDark,
          ),
          _ToggleSetting(
            label: 'Auto-generate Titles',
            value: settings.autoGenerateTitle,
            onChanged: (v) =>
                ref.read(settingsProvider.notifier).setAutoGenerateTitle(v),
            isDark: isDark,
          ),
          _ToggleSetting(
            label: 'Send on Enter',
            value: settings.sendOnEnter,
            onChanged: (v) =>
                ref.read(settingsProvider.notifier).setSendOnEnter(v),
            isDark: isDark,
          ),
          _ToggleSetting(
            label: 'Show System Messages',
            value: settings.showSystemMessages,
            onChanged: (v) =>
                ref.read(settingsProvider.notifier).setShowSystemMessages(v),
            isDark: isDark,
          ),
          _ToggleSetting(
            label: 'Haptic Feedback',
            value: settings.hapticFeedbackEnabled,
            onChanged: (v) =>
                ref.read(settingsProvider.notifier).setHapticFeedback(v),
            isDark: isDark,
          ),
          _ToggleSetting(
            label: 'Enable MCP',
            value: settings.mcpEnabled,
            onChanged: (v) =>
                ref.read(settingsProvider.notifier).setMcpEnabled(v),
            isDark: isDark,
          ),
          const Divider(height: 32),
          _SectionHeader(title: 'Default Server'),
          _DropdownSetting(
            label: 'Default Server',
            currentValue: settings.defaultServerId,
            items: ref
                .watch(serversProvider)
                .map((s) => (s.id, s.name))
                .toList(),
            onChanged: (v) =>
                ref.read(settingsProvider.notifier).setDefaultServer(v),
            isDark: isDark,
            icon: Icons.computer,
          ),
          const Divider(height: 32),
          _SectionHeader(title: 'Default Persona'),
          _DropdownSetting(
            label: 'Default Persona',
            currentValue: settings.defaultPersonaId,
            items: ref
                .watch(storage.personasProvider)
                .map((p) => (p.id, '${p.emoji} ${p.name}'))
                .toList(),
            onChanged: (v) =>
                ref.read(settingsProvider.notifier).setDefaultPersona(v),
            isDark: isDark,
            icon: Icons.smart_toy_outlined,
          ),
          const Divider(height: 32),
          _SectionHeader(title: 'Privacy'),
          _ToggleSetting(
            label: 'Show Data Indicator',
            value: settings.showDataIndicator,
            onChanged: (v) =>
                ref.read(settingsProvider.notifier).setShowDataIndicator(v),
            isDark: isDark,
          ),
          Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 8),
            child: Text(
              '"LocalMind never sees your data"',
              style: TextStyle(
                fontSize: 12,
                color: isDark
                    ? const Color(0xFF888888)
                    : const Color(0xFF999999),
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
          const Divider(height: 32),
          _SectionHeader(title: 'Data Management'),
          _DangerousAction(
            label: 'Delete All Conversations',
            icon: Icons.delete_outline,
            onConfirm: () =>
                ref.read(conversationsProvider.notifier).deleteAll(),
            isDark: isDark,
          ),
          _DangerousAction(
            label: 'Reset Settings to Defaults',
            icon: Icons.restore,
            onConfirm: () =>
                ref.read(settingsProvider.notifier).resetToDefaults(),
            isDark: isDark,
          ),
          const Divider(height: 32),
          _SectionHeader(title: 'About'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'LocalMind v1.0.0',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 8),
            child: Text(
              'Your AI. Your Device. Your Rules.',
              style: TextStyle(
                fontSize: 13,
                color: isDark
                    ? const Color(0xFF888888)
                    : const Color(0xFF999999),
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8, top: 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
          color: isDark ? const Color(0xFF888888) : const Color(0xFF999999),
        ),
      ),
    );
  }
}

class _SliderSetting extends StatelessWidget {
  const _SliderSetting({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.description,
    required this.onChanged,
    required this.isDark,
    this.valueFormat,
    this.previewText,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String description;
  final ValueChanged<double> onChanged;
  final bool isDark;
  final String Function(double)? valueFormat;
  final String? previewText;

  @override
  Widget build(BuildContext context) {
    final displayValue = valueFormat != null
        ? valueFormat!(value)
        : value.toStringAsFixed(2);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
                displayValue,
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
              color: isDark ? const Color(0xFF666666) : const Color(0xFF999999),
            ),
          ),
          if (previewText != null) ...[
            const SizedBox(height: 4),
            Text(
              previewText!,
              style: TextStyle(
                fontSize: value.clamp(12, 24),
                color: isDark
                    ? const Color(0xFF888888)
                    : const Color(0xFF666666),
              ),
            ),
          ],
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _IntInputSetting extends StatefulWidget {
  const _IntInputSetting({
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
  State<_IntInputSetting> createState() => _IntInputSettingState();
}

class _IntInputSettingState extends State<_IntInputSetting> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value.toString());
  }

  @override
  void didUpdateWidget(_IntInputSetting old) {
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _ToggleSetting extends StatelessWidget {
  const _ToggleSetting({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.isDark,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      title: Text(
        label,
        style: TextStyle(
          fontSize: 14,
          color: isDark ? Colors.white : Colors.black,
        ),
      ),
      value: value,
      onChanged: onChanged,
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
    );
  }
}

class _ThemeToggle extends StatelessWidget {
  const _ThemeToggle({required this.current, required this.ref});
  final ThemeMode current;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentType = ref.watch(themeModeProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Theme',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _ThemeOption(
                label: 'System',
                icon: Icons.brightness_auto,
                isSelected: currentType == AppThemeType.system,
                onTap: () => ref
                    .read(themeModeProvider.notifier)
                    .setThemeMode(AppThemeType.system),
                isDark: isDark,
              ),
              const SizedBox(width: 8),
              _ThemeOption(
                label: 'Light',
                icon: Icons.light_mode,
                isSelected: currentType == AppThemeType.light,
                onTap: () => ref
                    .read(themeModeProvider.notifier)
                    .setThemeMode(AppThemeType.light),
                isDark: isDark,
              ),
              const SizedBox(width: 8),
              _ThemeOption(
                label: 'Dark',
                icon: Icons.dark_mode,
                isSelected: currentType == AppThemeType.dark,
                onTap: () => ref
                    .read(themeModeProvider.notifier)
                    .setThemeMode(AppThemeType.dark),
                isDark: isDark,
              ),
              const SizedBox(width: 8),
              _ThemeOption(
                label: 'Claude',
                icon: Icons.auto_awesome,
                isSelected: currentType == AppThemeType.claude,
                onTap: () => ref
                    .read(themeModeProvider.notifier)
                    .setThemeMode(AppThemeType.claude),
                isDark: isDark,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
    required this.isDark,
  });

  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final accent = isDark ? const Color(0xFF3B82F6) : const Color(0xFF2563EB);

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? accent.withValues(alpha: 0.15)
                : (isDark ? const Color(0xFF1F1F1F) : const Color(0xFFF5F5F5)),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected
                  ? accent
                  : (isDark
                        ? const Color(0xFF3A3A3A)
                        : const Color(0xFFE5E5E5)),
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 20,
                color: isSelected
                    ? accent
                    : (isDark
                          ? const Color(0xFF888888)
                          : const Color(0xFF999999)),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected
                      ? accent
                      : (isDark
                            ? const Color(0xFF888888)
                            : const Color(0xFF999999)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DropdownSetting extends StatelessWidget {
  const _DropdownSetting({
    required this.label,
    required this.currentValue,
    required this.items,
    required this.onChanged,
    required this.isDark,
    required this.icon,
  });

  final String label;
  final String? currentValue;
  final List<(String id, String name)> items;
  final ValueChanged<String?> onChanged;
  final bool isDark;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1F1F1F) : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isDark ? const Color(0xFF3A3A3A) : const Color(0xFFE5E5E5),
          ),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: currentValue,
            isExpanded: true,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            borderRadius: BorderRadius.circular(8),
            dropdownColor: isDark ? const Color(0xFF1F1F1F) : Colors.white,
            hint: Text(
              'None selected',
              style: TextStyle(
                fontSize: 14,
                color: isDark
                    ? const Color(0xFF666666)
                    : const Color(0xFF999999),
              ),
            ),
            items: [
              DropdownMenuItem(
                value: null,
                child: Text(
                  'None',
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark
                        ? const Color(0xFF888888)
                        : const Color(0xFF666666),
                  ),
                ),
              ),
              ...items.map(
                (item) => DropdownMenuItem(
                  value: item.$1,
                  child: Row(
                    children: [
                      Icon(
                        icon,
                        size: 16,
                        color: isDark
                            ? const Color(0xFF888888)
                            : const Color(0xFF999999),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        item.$2,
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }
}

class _CodeThemeDropdown extends StatelessWidget {
  const _CodeThemeDropdown({
    required this.label,
    required this.current,
    required this.onChanged,
    required this.isDark,
  });

  final String label;
  final SyntaxThemeName current;
  final ValueChanged<SyntaxThemeName> onChanged;
  final bool isDark;

  String _getDisplayName(SyntaxThemeName theme) {
    switch (theme) {
      case SyntaxThemeName.vscodeDark:
        return 'VS Code Dark';
      case SyntaxThemeName.vscodeLight:
        return 'VS Code Light';
      case SyntaxThemeName.dracula:
        return 'Dracula';
      case SyntaxThemeName.monokaiSublime:
        return 'Monokai';
      case SyntaxThemeName.ayuLight:
        return 'Ayu Light';
      case SyntaxThemeName.ayuDark:
        return 'Ayu Dark';
      case SyntaxThemeName.gravityLight:
        return 'Gravity Light';
      case SyntaxThemeName.gravityDark:
        return 'Gravity Dark';
      case SyntaxThemeName.obsidian:
        return 'Obsidian';
      case SyntaxThemeName.oceanSunset:
        return 'Ocean Sunset';
      case SyntaxThemeName.standard:
        return 'Standard';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1F1F1F) : const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isDark
                    ? const Color(0xFF3A3A3A)
                    : const Color(0xFFE5E5E5),
              ),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<SyntaxThemeName>(
                value: current,
                isExpanded: true,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                borderRadius: BorderRadius.circular(8),
                dropdownColor: isDark ? const Color(0xFF1F1F1F) : Colors.white,
                items: SyntaxThemeName.values.map((theme) {
                  return DropdownMenuItem(
                    value: theme,
                    child: Text(
                      _getDisplayName(theme),
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                  );
                }).toList(),
                onChanged: (v) {
                  if (v != null) onChanged(v);
                },
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Choose syntax highlighting theme for code blocks.',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? const Color(0xFF666666) : const Color(0xFF999999),
            ),
          ),
        ],
      ),
    );
  }
}

class _DangerousAction extends StatelessWidget {
  const _DangerousAction({
    required this.label,
    required this.icon,
    required this.onConfirm,
    required this.isDark,
  });

  final String label;
  final IconData icon;
  final VoidCallback onConfirm;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: OutlinedButton.icon(
        onPressed: () {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(label),
              content: const Text(
                'Are you sure? This action cannot be undone.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    onConfirm();
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('$label completed')));
                  },
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('Confirm'),
                ),
              ],
            ),
          );
        },
        icon: Icon(icon, color: Colors.red, size: 18),
        label: Text(label, style: const TextStyle(color: Colors.red)),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Colors.red),
          minimumSize: const Size(double.infinity, 44),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }
}
