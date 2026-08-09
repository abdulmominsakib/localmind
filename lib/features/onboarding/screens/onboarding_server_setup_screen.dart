import 'package:hugeicons/hugeicons.dart';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:cue/cue.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/models/enums.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/routes/app_routes.dart';
import '../../../l10n/app_localizations.dart';
import '../../servers/data/models/server.dart';
import '../../servers/providers/server_providers.dart';
import '../../servers/views/components/https_scheme_hint.dart';

class OnboardingServerSetupScreen extends ConsumerStatefulWidget {
  final ServerType selectedType;

  const OnboardingServerSetupScreen({super.key, required this.selectedType});

  @override
  ConsumerState<OnboardingServerSetupScreen> createState() =>
      _OnboardingServerSetupScreenState();
}

class _OnboardingServerSetupScreenState
    extends ConsumerState<OnboardingServerSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _hostController;
  late TextEditingController _portController;
  late TextEditingController _apiKeyController;

  bool _isTesting = false;
  bool _isSaving = false;
  String? _testResult;
  bool _testSuccess = false;

  @override
  void initState() {
    super.initState();
    String defaultName = '';
    String defaultPort = '';
    String defaultHost = '';

    switch (widget.selectedType) {
      case ServerType.lmStudio:
        defaultName = 'LM Studio';
        defaultPort = AppConstants.lmStudioDefaultPort.toString();
        defaultHost = Platform.isAndroid ? '192.168.0.0' : '127.0.0.1';
        break;
      case ServerType.openAICompatible:
        defaultName = 'OpenAI Compatible';
        defaultPort = AppConstants.openAICompatibleDefaultPort.toString();
        defaultHost = Platform.isAndroid ? '192.168.0.0' : '127.0.0.1';
        break;
      case ServerType.ollama:
        defaultName = 'Ollama';
        defaultPort = AppConstants.ollamaDefaultPort.toString();
        defaultHost = Platform.isAndroid ? '192.168.0.0' : '127.0.0.1';
        break;
      case ServerType.ollamaCloud:
        defaultName = 'Ollama Cloud';
        defaultHost = AppConstants.ollamaCloudBaseUrl;
        defaultPort = AppConstants.ollamaCloudDefaultPort.toString();
        break;
      case ServerType.openRouter:
        defaultName = 'OpenRouter';
        defaultPort = '443';
        break;
      case ServerType.onDevice:
        defaultName = 'On-Device';
        defaultPort = '0';
        break;
    }

    _nameController = TextEditingController(text: defaultName);
    _hostController = TextEditingController(text: defaultHost);
    _portController = TextEditingController(text: defaultPort);
    _apiKeyController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  Server _buildServer() {
    final requiresCloudConfig =
        widget.selectedType == ServerType.ollamaCloud;
    final host = requiresCloudConfig
        ? AppConstants.ollamaCloudBaseUrl
        : _hostController.text.trim();
    final port = requiresCloudConfig
        ? AppConstants.ollamaCloudDefaultPort
        : int.parse(_portController.text.trim());

    return Server(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: _nameController.text.trim(),
      type: widget.selectedType,
      host: host,
      port: port,
      apiKey: _isCloudProvider
          ? _apiKeyController.text.trim()
          : (_apiKeyController.text.trim().isNotEmpty
                ? _apiKeyController.text.trim()
                : null),
      isDefault: true, // Make it default since it's the first one
      createdAt: DateTime.now(),
      lastConnectedAt: DateTime.now(),
      status: ConnectionStatus.disconnected,
    );
  }

  bool get _isCloudProvider =>
      widget.selectedType == ServerType.openRouter ||
      widget.selectedType == ServerType.ollamaCloud;

  String? _validateHost(String? value) {
    if (_isCloudProvider) return null;
    final l10n = AppLocalizations.of(context)!;
    if (value == null || value.trim().isEmpty) {
      return l10n.host_required;
    }
    if (parseServerAddressInput(value) == null) {
      return l10n.host_valid;
    }
    return null;
  }

  String? _validatePort(String? value) {
    if (_isCloudProvider) return null;
    final l10n = AppLocalizations.of(context)!;
    if (value == null || value.trim().isEmpty) {
      return l10n.port_required;
    }
    final port = int.tryParse(value.trim());
    if (port == null || port < 1 || port > 65535) {
      return l10n.port_invalid;
    }
    return null;
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isTesting = true;
      _testResult = null;
      _testSuccess = false;
    });

    final l10n = AppLocalizations.of(context)!;
    final apiService = ref.read(serverApiServiceProvider);
    final testServer = _buildServer();

    try {
      final isConnected = await apiService.testConnection(testServer);
      setState(() {
        _testSuccess = isConnected;
        _testResult = isConnected
            ? l10n.connection_successful
            : l10n.connection_failed;
      });
      if (isConnected) {
        invalidateAvailableModelsCache(testServer.id);
      }
    } catch (e) {
      setState(() {
        _testSuccess = false;
        _testResult = l10n.error_with_message(e.toString());
      });
    } finally {
      setState(() {
        _isTesting = false;
      });
    }
  }

  Future<void> _saveAndContinue() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
    });

    try {
      final server = _buildServer();
      await ref.read(serversProvider.notifier).addServer(server);
      await ref.read(serversProvider.notifier).setDefault(server.id);
      invalidateAvailableModelsCache(server.id);
      ref.read(activeServerIdProvider.notifier).setActiveServer(server);

      if (mounted) {
        context.push(AppRoutes.onboardingTheme);
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isCloud = _isCloudProvider;
    final isOllamaCloud = widget.selectedType == ServerType.ollamaCloud;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.setup_connection)),
      body: SafeArea(
        child: Cue.onMount(
          motion: .smooth(),
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.symmetric(
                horizontal: 24.0,
                vertical: 16.0,
              ),
              children: [
                Actor(
                  acts: [
                    .fadeIn(),
                    .slideY(from: 0.08),
                  ],
                  child: Text(
                    l10n.setup_connection_desc(widget.selectedType.name),
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ),
                Actor(
                  delay: 60.ms,
                  acts: [
                    .fadeIn(),
                    .slideY(from: 0.08),
                  ],
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 32),
                      TextFormField(
                        controller: _nameController,
                        decoration: InputDecoration(
                          labelText: l10n.server_name,
                          filled: true,
                          fillColor: theme.colorScheme.surface,
                        ),
                        validator: (val) => val == null || val.trim().isEmpty
                            ? l10n.name_required
                            : null,
                      ),
                      const SizedBox(height: 16),
                      if (!isCloud) ...[
                        TextFormField(
                          controller: _hostController,
                          decoration: InputDecoration(
                            labelText: l10n.host_label,
                            filled: true,
                            fillColor: theme.colorScheme.surface,
                          ),
                          validator: _validateHost,
                        ),
                        HttpsSchemeHint(controller: _hostController),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _portController,
                          decoration: InputDecoration(
                            labelText: l10n.port_label,
                            filled: true,
                            fillColor: theme.colorScheme.surface,
                          ),
                          validator: _validatePort,
                        ),
                        const SizedBox(height: 16),
                      ],
                      TextFormField(
                        controller: _apiKeyController,
                        decoration: InputDecoration(
                          labelText: isCloud
                              ? l10n.api_key_required
                              : l10n.api_key_optional,
                          filled: true,
                          fillColor: theme.colorScheme.surface,
                          hintText: isCloud
                              ? (isOllamaCloud
                                    ? l10n.api_key_hint_ollama_cloud
                                    : l10n.api_key_hint_openrouter)
                              : null,
                        ),
                        validator: (val) {
                          if (isCloud && (val == null || val.trim().isEmpty)) {
                            return isOllamaCloud
                                ? l10n.api_key_required_ollama_cloud
                                : l10n.api_key_required_openrouter;
                          }
                          if (isCloud &&
                              widget.selectedType == ServerType.openRouter &&
                              val != null &&
                              !val.trim().startsWith('sk-')) {
                            return l10n.api_key_format;
                          }
                          return null;
                        },
                        obscureText: true,
                      ),
                      if (isCloud) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: theme.colorScheme.primary.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              HugeIcon(
                                icon: HugeIcons.strokeRoundedShield01,
                                size: 18,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  isOllamaCloud
                                      ? l10n.ollama_cloud_disclosure
                                      : l10n.openrouter_disclosure,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Actor(
                  delay: 120.ms,
                  acts: [
                    .fadeIn(),
                    .slideY(from: 0.08),
                  ],
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 24),
                      if (_testResult != null)
                        Container(
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 24),
                          decoration: BoxDecoration(
                            color: _testSuccess
                                ? Colors.green.withValues(alpha: 0.1)
                                : Colors.red.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _testSuccess ? Colors.green : Colors.red,
                            ),
                          ),
                          child: Row(
                            children: [
                              HugeIcon(icon: 
                                _testSuccess ? HugeIcons.strokeRoundedCheckmarkCircle01 : HugeIcons.strokeRoundedAlertCircle,
                                color: _testSuccess ? Colors.green : Colors.red,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _testResult!,
                                  style: TextStyle(
                                    color: _testSuccess ? Colors.green : Colors.red,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ShadButton.outline(
                        width: double.infinity,
                        onPressed: _isTesting ? null : _testConnection,
                        child: _isTesting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(l10n.test_connection),
                      ),
                      const SizedBox(height: 16),
                      ShadButton(
                        width: double.infinity,
                        onPressed: _isSaving ? null : _saveAndContinue,
                        child: _isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                l10n.save_continue,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}