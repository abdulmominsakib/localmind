import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/models/enums.dart';
import 'package:localmind/features/servers/data/models/server.dart';
import '../../../core/providers/service_providers.dart';
import '../../servers/providers/server_providers.dart';
import '../../../core/routes/app_routes.dart';

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

    switch (widget.selectedType) {
      case ServerType.lmStudio:
        defaultName = 'LM Studio';
        defaultPort = AppConstants.lmStudioDefaultPort.toString();
        break;
      case ServerType.ollama:
        defaultName = 'Ollama';
        defaultPort = AppConstants.ollamaDefaultPort.toString();
        break;
      case ServerType.openRouter:
        defaultName = 'OpenRouter';
        defaultPort = '443';
        break;
    }

    _nameController = TextEditingController(text: defaultName);
    _hostController = TextEditingController(
      text: widget.selectedType == ServerType.openRouter ? '' : '127.0.0.1',
    );
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
    return Server(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: _nameController.text.trim(),
      type: widget.selectedType,
      host: _hostController.text.trim(),
      port: int.parse(_portController.text.trim()),
      apiKey: widget.selectedType == ServerType.openRouter
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

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isTesting = true;
      _testResult = null;
      _testSuccess = false;
    });

    final apiService = ref.read(serverApiServiceProvider);
    final testServer = _buildServer();

    try {
      final isConnected = await apiService.testConnection(testServer);
      setState(() {
        _testSuccess = isConnected;
        _testResult = isConnected
            ? 'Connection successful!'
            : 'Connection failed. Check your settings.';
      });
    } catch (e) {
      setState(() {
        _testSuccess = false;
        _testResult = 'Error: ${e.toString()}';
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
      ref.read(activeServerProvider.notifier).setActiveServer(server);

      if (mounted) {
        context.push(AppRoutes.onboardingTheme);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
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
    final theme = Theme.of(context);
    final isCloud = widget.selectedType == ServerType.openRouter;

    return Scaffold(
      appBar: AppBar(title: const Text('Setup Connection')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.symmetric(
              horizontal: 24.0,
              vertical: 16.0,
            ),
            children: [
              Text(
                'Configure your ${widget.selectedType.name} server to start chatting.',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 32),

              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Server Name',
                  filled: true,
                  fillColor: theme.colorScheme.surface,
                ),
                validator: (val) =>
                    val == null || val.trim().isEmpty ? 'Name required' : null,
              ),
              const SizedBox(height: 16),

              if (!isCloud) ...[
                TextFormField(
                  controller: _hostController,
                  decoration: InputDecoration(
                    labelText: 'Host / IP Address',
                    filled: true,
                    fillColor: theme.colorScheme.surface,
                  ),
                  validator: (val) => val == null || val.trim().isEmpty
                      ? 'Host required'
                      : null,
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _portController,
                  decoration: InputDecoration(
                    labelText: 'Port',
                    filled: true,
                    fillColor: theme.colorScheme.surface,
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty)
                      return 'Port required';
                    if (int.tryParse(val) == null) return 'Must be a number';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
              ],

              TextFormField(
                controller: _apiKeyController,
                decoration: InputDecoration(
                  labelText: isCloud ? 'API Key *' : 'API Key (Optional)',
                  filled: true,
                  fillColor: theme.colorScheme.surface,
                ),
                validator: (val) {
                  if (isCloud && (val == null || val.trim().isEmpty)) {
                    return 'API Key required for OpenRouter';
                  }
                  return null;
                },
                obscureText: true,
              ),
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
                      Icon(
                        _testSuccess ? Icons.check_circle : Icons.error,
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
                    : const Text('Test Connection'),
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
                    : const Text(
                        'Save & Continue',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
