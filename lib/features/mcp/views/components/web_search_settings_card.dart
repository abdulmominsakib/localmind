import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:localmind/l10n/app_localizations.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../core/providers/app_providers.dart';
import '../../../chat/data/tools/web/web_search_client.dart';
import '../../../chat/data/tools/web/web_search_service.dart';
import '../../../chat/providers/tooling_providers.dart';

/// Settings for the built-in web search: on/off, which provider, and the
/// address or key it needs, with a button to try a search.
class WebSearchSettingsCard extends ConsumerStatefulWidget {
  const WebSearchSettingsCard({super.key});

  @override
  ConsumerState<WebSearchSettingsCard> createState() =>
      _WebSearchSettingsCardState();
}

class _WebSearchSettingsCardState extends ConsumerState<WebSearchSettingsCard> {
  late final TextEditingController _urlController;
  final _keyController = TextEditingController();
  bool _hasSavedKey = false;
  bool _testing = false;
  String? _testMessage;
  bool _testOk = false;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(
      text: ref.read(settingsProvider).webSearchSearxngUrl,
    );
    _loadKey();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _keyController.dispose();
    super.dispose();
  }

  WebSearchProviderKind get _kind =>
      WebSearchProviderKind.parse(ref.read(settingsProvider).webSearchProvider);

  Future<void> _loadKey() async {
    final kind = _kind;
    if (!kind.needsApiKey) {
      if (mounted) setState(() => _hasSavedKey = false);
      return;
    }
    final key = await ref.read(webSearchKeyStoreProvider).read(kind);
    if (mounted) setState(() => _hasSavedKey = key != null);
  }

  void _refreshTools() {
    ref.invalidate(webSearchReadyProvider);
    ref.invalidate(availableToolsProvider);
  }

  Future<void> _setProvider(WebSearchProviderKind kind) async {
    ref.read(settingsProvider.notifier).setWebSearchProvider(kind.name);
    _keyController.clear();
    setState(() => _testMessage = null);
    await _loadKey();
    _refreshTools();
  }

  void _saveUrl() {
    final url = _urlController.text.trim();
    if (url == ref.read(settingsProvider).webSearchSearxngUrl) return;
    ref.read(settingsProvider.notifier).setWebSearchSearxngUrl(url);
    _refreshTools();
  }

  Future<void> _saveKey() async {
    final value = _keyController.text.trim();
    if (value.isEmpty) return;
    final focus = FocusScope.of(context);
    await ref.read(webSearchKeyStoreProvider).write(_kind, value);
    _keyController.clear();
    focus.unfocus();
    await _loadKey();
    _refreshTools();
  }

  Future<void> _removeKey() async {
    await ref.read(webSearchKeyStoreProvider).write(_kind, null);
    await _loadKey();
    _refreshTools();
  }

  Future<void> _test() async {
    final l10n = AppLocalizations.of(context)!;
    _saveUrl();
    setState(() {
      _testing = true;
      _testMessage = null;
    });
    try {
      final results = await ref
          .read(webSearchServiceProvider)
          .search('weather today', count: 3);
      if (!mounted) return;
      setState(() {
        _testOk = results.isNotEmpty;
        _testMessage = l10n.web_search_test_ok(results.length);
      });
    } on WebSearchException catch (e) {
      if (!mounted) return;
      setState(() {
        _testOk = false;
        _testMessage = l10n.web_search_test_failed(e.message);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testOk = false;
        _testMessage = l10n.web_search_test_failed('$e');
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = ShadTheme.of(context).colorScheme;
    final settings = ref.watch(settingsProvider);
    final kind = WebSearchProviderKind.parse(settings.webSearchProvider);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    const accent = Color(0xFF0EA5E9);

    return Container(
      key: const ValueKey('web_search_settings_card'),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.border.withValues(alpha: 0.9)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Center(
                  child: HugeIcon(
                    icon: HugeIcons.strokeRoundedGlobalSearch,
                    color: accent,
                    size: 16,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l10n.web_search_title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Switch.adaptive(
                key: const ValueKey('web_search_enabled_switch'),
                value: settings.webSearchEnabled,
                onChanged: (value) {
                  ref
                      .read(settingsProvider.notifier)
                      .setWebSearchEnabled(value);
                  _refreshTools();
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(l10n.web_search_enable_desc, style: muted),
          if (settings.webSearchEnabled) ...[
            const SizedBox(height: 14),
            Text(
              l10n.web_search_provider,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in WebSearchProviderKind.values)
                  ChoiceChip(
                    key: ValueKey('web_search_provider_${option.name}'),
                    label: Text(WebSearchService.providerLabel(option)),
                    selected: option == kind,
                    onSelected: (_) => _setProvider(option),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            if (kind == WebSearchProviderKind.searxng) ...[
              TextField(
                key: const ValueKey('web_search_searxng_url'),
                controller: _urlController,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: l10n.web_search_searxng_url,
                  hintText: l10n.web_search_searxng_hint,
                ),
                onSubmitted: (_) => _saveUrl(),
                onTapOutside: (_) => _saveUrl(),
              ),
              const SizedBox(height: 6),
              Text(l10n.web_search_searxng_help, style: muted),
            ] else ...[
              TextField(
                key: const ValueKey('web_search_api_key'),
                controller: _keyController,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: l10n.web_search_api_key,
                  hintText: _hasSavedKey ? l10n.web_search_api_key_saved : null,
                  suffixIcon: IconButton(
                    tooltip: l10n.save,
                    onPressed: _saveKey,
                    icon: const HugeIcon(
                      icon: HugeIcons.strokeRoundedTick02,
                      size: 18,
                    ),
                  ),
                ),
                onSubmitted: (_) => _saveKey(),
              ),
              if (_hasSavedKey) ...[
                const SizedBox(height: 4),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    key: const ValueKey('web_search_remove_key'),
                    onPressed: _removeKey,
                    child: Text(l10n.web_search_remove_key),
                  ),
                ),
              ],
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                OutlinedButton.icon(
                  key: const ValueKey('web_search_test'),
                  onPressed: _testing ? null : _test,
                  icon: _testing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const HugeIcon(
                          icon: HugeIcons.strokeRoundedSearch01,
                          size: 16,
                        ),
                  label: Text(l10n.web_search_test),
                ),
              ],
            ),
            if (_testMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _testMessage!,
                key: const ValueKey('web_search_test_message'),
                style: muted?.copyWith(
                  color: _testOk
                      ? const Color(0xFF16A34A)
                      : theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Text(l10n.web_search_tools_note, style: muted),
          ],
        ],
      ),
    );
  }
}
