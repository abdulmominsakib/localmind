import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../../core/constants/app_constants.dart';
import 'package:localmind/features/servers/data/models/server.dart';
import '../../../core/models/enums.dart';
import '../../../core/providers/service_providers.dart';
import '../providers/server_providers.dart';
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

  late ServerType _selectedType;
  String? _selectedIconName;
  bool _isTesting = false;
  bool _isSaving = false;
  String? _testResult;

  bool get _isEditing => widget.editServer != null;

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
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _apiKeyController.dispose();
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
            ? 'Connection successful!'
            : 'Connection failed. Check your settings.';
      });
    } catch (e) {
      setState(() {
        _testResult = 'Error: ${e.toString()}';
      });
    } finally {
      setState(() {
        _isTesting = false;
      });
    }
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

      if (mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEditing ? 'Server updated' : 'Server added'),
            duration: const Duration(seconds: 2),
          ),
        );
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

  String? _validateName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Name is required';
    }
    if (value.trim().length > 50) {
      return 'Name must be 50 characters or less';
    }
    return null;
  }

  String? _validateHost(String? value) {
    if (_selectedType == ServerType.openRouter) return null;

    if (value == null || value.trim().isEmpty) {
      return 'Host is required';
    }
    final hostPattern = RegExp(r'^[a-zA-Z0-9]([a-zA-Z0-9\-\.]*[a-zA-Z0-9])?$');
    if (!hostPattern.hasMatch(value.trim())) {
      return 'Enter a valid hostname or IP address';
    }
    return null;
  }

  String? _validatePort(String? value) {
    if (_selectedType == ServerType.openRouter) return null;

    if (value == null || value.trim().isEmpty) {
      return 'Port is required';
    }
    final port = int.tryParse(value.trim());
    if (port == null || port < 1 || port > 65535) {
      return 'Enter a valid port (1-65535)';
    }
    return null;
  }

  String? _validateApiKey(String? value) {
    if (_selectedType == ServerType.openRouter) {
      if (value == null || value.trim().isEmpty) {
        return 'API key is required for OpenRouter';
      }
      if (!value.trim().startsWith('sk-')) {
        return 'OpenRouter API keys start with sk-';
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
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Server' : 'Add Server'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Server Type', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            ServerTypeSelector(
              selectedType: _selectedType,
              onChanged: _onTypeChanged,
            ),
            const SizedBox(height: 24),

            Text('Server Icon', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _showIconPicker,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: theme.colorScheme.outline),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        // color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: HugeIcon(
                        icon: _selectedIconName != null
                            ? (getHugeIconByName(_selectedIconName)?.icon ??
                                  getDefaultServerIcon(
                                    _selectedType.name,
                                  )!.icon)
                            : getDefaultServerIcon(_selectedType.name)!.icon,
                        size: 24,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _selectedIconName ?? 'Default icon',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    Icon(
                      Icons.edit,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'My Server',
              ),
              validator: _validateName,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),

            if (_selectedType != ServerType.openRouter) ...[
              TextFormField(
                controller: _hostController,
                decoration: const InputDecoration(
                  labelText: 'Host / IP Address',
                  hintText: '192.168.1.100',
                ),
                validator: _validateHost,
                keyboardType: TextInputType.text,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _portController,
                decoration: InputDecoration(
                  labelText: 'Port',
                  hintText: _selectedType == ServerType.lmStudio
                      ? AppConstants.lmStudioDefaultPort.toString()
                      : AppConstants.ollamaDefaultPort.toString(),
                ),
                validator: _validatePort,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),
            ],

            TextFormField(
              controller: _apiKeyController,
              decoration: InputDecoration(
                labelText: _selectedType == ServerType.openRouter
                    ? 'API Key *'
                    : 'API Key (optional)',
                hintText: _selectedType == ServerType.openRouter
                    ? 'sk-...'
                    : 'For authenticated servers',
              ),
              validator: _validateApiKey,
              obscureText: true,
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: 24),

            if (_testResult != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _testResult!.contains('successful')
                      ? Colors.green.withAlpha(25)
                      : Colors.red.withAlpha(25),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _testResult!.contains('successful')
                        ? Colors.green
                        : Colors.red,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _testResult!.contains('successful')
                          ? Icons.check_circle
                          : Icons.error,
                      color: _testResult!.contains('successful')
                          ? Colors.green
                          : Colors.red,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _testResult!,
                        style: TextStyle(
                          color: _testResult!.contains('successful')
                              ? Colors.green
                              : Colors.red,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            OutlinedButton.icon(
              onPressed: _isTesting ? null : _testConnection,
              icon: _isTesting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.network_check),
              label: Text(_isTesting ? 'Testing...' : 'Test Connection'),
            ),
            const SizedBox(height: 24),

            ElevatedButton(
              onPressed: _isSaving ? null : _saveServer,
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_isEditing ? 'Update Server' : 'Save Server'),
            ),
          ],
        ),
      ),
    );
  }
}
