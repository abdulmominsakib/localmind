import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:localmind/l10n/app_localizations.dart';
import '../../../core/constants/app_constants.dart';
import '../data/models/server.dart';
import '../../../core/models/enums.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/utils/system_insets.dart';
import '../providers/server_providers.dart';
import 'components/https_scheme_hint.dart';
import 'components/server_icon_picker.dart';
import 'components/server_type_selector.dart';

class AddServerScreen extends ConsumerStatefulWidget {
  final Server? editServer;

  const AddServerScreen({super.key, this.editServer});

  @override
  ConsumerState<AddServerScreen> createState() => _AddServerScreenState();
}

class _AddServerScreenState extends ConsumerState<AddServerScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _hostController;
  late TextEditingController _portController;
  late TextEditingController _apiKeyController;
  late TextEditingController _ramGbController;
  late TextEditingController _vramGbController;

  late ServerType _selectedType;
  String? _selectedIconName;
  bool _isTesting = false;
  bool _isSaving = false;
  String? _testResult;

  bool get _isEditing => widget.editServer != null;
  bool get _requiresEndpoint => _selectedType != ServerType.openRouter;
  bool get _requiresMandatoryApiKey => _selectedType == ServerType.openRouter;

  @override
  void initState() {
    super.initState();
    final server = widget.editServer;
    _selectedType = server?.type ?? ServerType.lmStudio;
    _selectedIconName = server?.iconName;
    _nameController = TextEditingController(text: server?.name ?? '');
    _hostController = TextEditingController(text: server?.host ?? '');
    _portController = TextEditingController(
      text:
          server?.port.toString() ??
          AppConstants.lmStudioDefaultPort.toString(),
    );
    _apiKeyController = TextEditingController(text: server?.apiKey ?? '');
    _ramGbController = TextEditingController(
      text: server?.availableRamGb?.toString() ?? '',
    );
    _vramGbController = TextEditingController(
      text: server?.availableVramGb?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _apiKeyController.dispose();
    _ramGbController.dispose();
    _vramGbController.dispose();
    super.dispose();
  }

  void _onTypeChanged(ServerType type) {
    setState(() {
      _selectedType = type;
      _testResult = null;

      if (type == ServerType.openRouter) {
        _portController.text = '443';
      } else if (type == ServerType.lmStudio) {
        _portController.text = AppConstants.lmStudioDefaultPort.toString();
      } else if (type == ServerType.openAICompatible) {
        _portController.text = AppConstants.openAICompatibleDefaultPort
            .toString();
      } else if (type == ServerType.ollama) {
        _portController.text = AppConstants.ollamaDefaultPort.toString();
      }
    });
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isTesting = true;
      _testResult = null;
    });

    final apiService = ref.read(serverApiServiceProvider);
    final testServer = _buildServer();

    try {
      final isConnected = await apiService.testConnection(testServer);
      setState(() {
        _testResult = isConnected
            ? AppLocalizations.of(context)!.connection_successful
            : AppLocalizations.of(context)!.connection_failed;
      });
      if (isConnected) {
        invalidateAvailableModelsCache(testServer.id);
      }
    } catch (e) {
      setState(() {
        _testResult = AppLocalizations.of(
          context,
        )!.error_with_message(e.toString());
      });
    } finally {
      setState(() {
        _isTesting = false;
      });
    }
  }

  int? _parseOptionalGb(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return int.tryParse(trimmed);
  }

  Server _buildServer() {
    return Server(
      id:
          widget.editServer?.id ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      name: _nameController.text.trim(),
      type: _selectedType,
      host: _hostController.text.trim(),
      port: int.parse(_portController.text.trim()),
      apiKey: _selectedType == ServerType.openRouter
          ? _apiKeyController.text.trim()
          : (_apiKeyController.text.trim().isNotEmpty
                ? _apiKeyController.text.trim()
                : null),
      isDefault: widget.editServer?.isDefault ?? false,
      createdAt: widget.editServer?.createdAt ?? DateTime.now(),
      lastConnectedAt: widget.editServer?.lastConnectedAt ?? DateTime.now(),
      status: ConnectionStatus.disconnected,
      iconName: _selectedIconName,
      availableRamGb: _selectedType == ServerType.lmStudio
          ? _parseOptionalGb(_ramGbController.text)
          : widget.editServer?.availableRamGb,
      availableVramGb: _selectedType == ServerType.lmStudio
          ? _parseOptionalGb(_vramGbController.text)
          : widget.editServer?.availableVramGb,
    );
  }

  Future<void> _saveServer() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
    });

    try {
      final server = _buildServer();

      if (_isEditing) {
        await ref.read(serversProvider.notifier).updateServer(server);
      } else {
        await ref.read(serversProvider.notifier).addServer(server);
      }
      invalidateAvailableModelsCache(server.id);

      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEditing ? l10n.server_updated : l10n.server_added),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.error_with_message(e.toString()),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  String? _validateName(String? value) {
    final context = this.context;
    final l10n = AppLocalizations.of(context)!;
    if (value == null || value.trim().isEmpty) {
      return l10n.name_required;
    }
    if (value.trim().length > 50) {
      return l10n.name_length_validation;
    }
    return null;
  }

  String? _validateHost(String? value) {
    if (!_requiresEndpoint) return null;
    final l10n = AppLocalizations.of(context)!;

    if (value == null || value.trim().isEmpty) {
      return l10n.host_required;
    }
    final parsed = parseServerAddressInput(value);
    if (parsed == null) {
      return l10n.host_valid;
    }
    return null;
  }

  String? _validatePort(String? value) {
    if (!_requiresEndpoint) return null;
    final l10n = AppLocalizations.of(context)!;

    if (value == null || value.trim().isEmpty) {
      return l10n.port_required;
    }
    final port = int.tryParse(value.trim());
    if (port == null || port < 1 || port > 65535) {
      return l10n.port_range;
    }
    return null;
  }

  String? _validateApiKey(String? value) {
    if (_requiresMandatoryApiKey) {
      final l10n = AppLocalizations.of(context)!;
      if (value == null || value.trim().isEmpty) {
        return l10n.api_key_required_openrouter;
      }
      if (!value.trim().startsWith('sk-')) {
        return l10n.api_key_format;
      }
    }
    return null;
  }

  void _showIconPicker() {
    showShadSheet(
      context: context,
      side: ShadSheetSide.bottom,
      builder: (context) => ServerIconPicker(
        selectedIconName: _selectedIconName,
        onIconSelected: (iconName) {
          setState(() {
            _selectedIconName = iconName;
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final systemBottomInset = bottomSystemInset(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? l10n.edit_server : l10n.add_server_title),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: _buildFloatingActionBar(
        context,
        bottomInset: systemBottomInset,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 120 + systemBottomInset),
          children: [
            _buildHeaderCard(context),
            const SizedBox(height: 14),
            _buildSectionCard(
              context,
              title: l10n.server_type_label,
              subtitle: l10n.server_type_help,
              child: ServerTypeSelector(
                selectedType: _selectedType,
                onChanged: _onTypeChanged,
              ),
            ),
            const SizedBox(height: 12),
            _buildSectionCard(
              context,
              title: l10n.server_identity_title,
              subtitle: l10n.server_identity_desc,
              child: Column(
                children: [
                  GestureDetector(
                    onTap: _showIconPicker,
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withValues(
                          alpha: 0.35,
                        ),
                        border: Border.all(
                          color: colorScheme.outline.withValues(alpha: 0.4),
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: colorScheme.primary.withValues(
                                alpha: 0.12,
                              ),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: HugeIcon(
                              icon: _selectedIconName != null
                                  ? (getHugeIconByName(
                                          _selectedIconName,
                                        )?.icon ??
                                        getDefaultServerIcon(
                                          _selectedType.name,
                                        )!.icon)
                                  : getDefaultServerIcon(
                                      _selectedType.name,
                                    )!.icon,
                              size: 24,
                              color: colorScheme.primary,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l10n.server_icon_label,
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _selectedIconName ?? l10n.default_icon,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 16,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: l10n.name_label,
                      hintText: l10n.my_server_hint,
                    ),
                    validator: _validateName,
                    textInputAction: TextInputAction.next,
                  ),
                ],
              ),
            ),
            if (_requiresEndpoint) ...[
              const SizedBox(height: 12),
              _buildSectionCard(
                context,
                title: l10n.server_connection_title,
                subtitle: l10n.server_connection_desc,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _hostController,
                      decoration: InputDecoration(
                        labelText: l10n.host_label,
                        hintText: '192.168.1.100',
                      ),
                      validator: _validateHost,
                      keyboardType: TextInputType.text,
                      textInputAction: TextInputAction.next,
                    ),
                    HttpsSchemeHint(controller: _hostController),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _portController,
                      decoration: InputDecoration(
                        labelText: l10n.port_label,
                        hintText: _selectedType == ServerType.lmStudio
                            ? AppConstants.lmStudioDefaultPort.toString()
                            : AppConstants.ollamaDefaultPort.toString(),
                      ),
                      validator: _validatePort,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.next,
                    ),
                  ],
                ),
              ),
            ],
            if (_selectedType == ServerType.lmStudio) ...[
              const SizedBox(height: 12),
              _buildSectionCard(
                context,
                title: l10n.lm_studio_memory_settings_title,
                subtitle: l10n.lm_studio_memory_settings_desc,
                child: Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _ramGbController,
                        decoration: InputDecoration(
                          labelText: l10n.lm_studio_available_ram_gb,
                          hintText: '32',
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _vramGbController,
                        decoration: InputDecoration(
                          labelText: l10n.lm_studio_available_vram_gb,
                          hintText: '6',
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            _buildSectionCard(
              context,
              title: l10n.server_authentication_title,
              subtitle: _requiresMandatoryApiKey
                  ? l10n.server_authentication_required_desc
                  : l10n.server_authentication_optional_desc,
              child: TextFormField(
                controller: _apiKeyController,
                decoration: InputDecoration(
                  labelText: _requiresMandatoryApiKey
                      ? l10n.api_key_required
                      : l10n.api_key_optional,
                  hintText: _requiresMandatoryApiKey
                      ? l10n.api_key_hint_openrouter
                      : l10n.api_key_hint_generic,
                ),
                validator: _validateApiKey,
                obscureText: true,
                textInputAction: TextInputAction.done,
              ),
            ),
            if (_testResult != null) ...[
              const SizedBox(height: 12),
              _buildTestResultBanner(context),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCard(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(16),
            ),
            child: HugeIcon(
              icon: getDefaultServerIcon(_selectedType.name)!.icon,
              size: 28,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _isEditing ? l10n.edit_server : l10n.add_server_title,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _requiresEndpoint
                ? 'Configure a local or self-hosted endpoint, then verify the connection before saving.'
                : 'Connect through OpenRouter with a valid API key and keep this profile ready for model routing.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildInfoPill(
                context,
                icon: Icons.hub_outlined,
                label: _serverTypeLabel(context),
              ),
              _buildInfoPill(
                context,
                icon: _requiresMandatoryApiKey ? Icons.key_outlined : Icons.dns,
                label: _requiresMandatoryApiKey
                    ? l10n.api_key_required
                    : l10n.host_label,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildTestResultBanner(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final success = _testResult!.contains(
      l10n.connection_successful.split('!')[0],
    );
    final accent = success ? Colors.green : theme.colorScheme.error;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            success ? Icons.check_circle_rounded : Icons.error_rounded,
            color: accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _testResult!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingActionBar(
    BuildContext context, {
    required double bottomInset,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, bottomInset > 0 ? 4 : 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surface.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: colorScheme.outline.withValues(alpha: 0.14),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isTesting ? null : _testConnection,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: _isTesting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.network_check_rounded),
                  label: Text(_isTesting ? l10n.testing : l10n.test_connection),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _saveServer,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_rounded),
                  label: Text(
                    _isSaving
                        ? l10n.save
                        : (_isEditing ? l10n.update_server : l10n.save_server),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoPill(
    BuildContext context, {
    required IconData icon,
    required String label,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String _serverTypeLabel(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return switch (_selectedType) {
      ServerType.lmStudio => l10n.server_type_lm_studio,
      ServerType.openAICompatible => l10n.server_type_openai_display,
      ServerType.ollama => l10n.server_type_ollama,
      ServerType.openRouter => l10n.server_type_openrouter,
      ServerType.onDevice => l10n.server_type_on_device_display,
    };
  }
}
