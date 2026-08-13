import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routes/app_routes.dart';
import '../../../l10n/app_localizations.dart';
import '../data/models/cloud_sync_models.dart';
import '../providers/cloud_sync_providers.dart';
import 'components/cloud_sync_status_card.dart';

class CloudSyncScreen extends ConsumerStatefulWidget {
  const CloudSyncScreen({super.key});

  @override
  ConsumerState<CloudSyncScreen> createState() => _CloudSyncScreenState();
}

class _CloudSyncScreenState extends ConsumerState<CloudSyncScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _endpoint;
  late final TextEditingController _bucket;
  late final TextEditingController _region;
  late final TextEditingController _prefix;
  final _accessKey = TextEditingController();
  final _secretKey = TextEditingController();
  final _sessionToken = TextEditingController();
  final _passphrase = TextEditingController();
  final _confirmPassphrase = TextEditingController();
  bool _pathStyle = true;
  bool _allowHttp = false;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    final config = ref.read(cloudSyncControllerProvider.notifier).config;
    _endpoint = TextEditingController(
      text: config?.endpoint ?? 'https://s3.amazonaws.com',
    );
    _bucket = TextEditingController(text: config?.bucket ?? '');
    _region = TextEditingController(text: config?.region ?? 'us-east-1');
    _prefix = TextEditingController(text: config?.prefix ?? 'localmind');
    _pathStyle = config?.pathStyle ?? true;
    _allowHttp = config?.allowInsecureHttp ?? false;
  }

  @override
  void dispose() {
    _endpoint.dispose();
    _bucket.dispose();
    _region.dispose();
    _prefix.dispose();
    _accessKey.dispose();
    _secretKey.dispose();
    _sessionToken.dispose();
    _passphrase.dispose();
    _confirmPassphrase.dispose();
    super.dispose();
  }

  S3SyncConfig get _config => S3SyncConfig(
    endpoint: _endpoint.text.trim(),
    bucket: _bucket.text.trim(),
    region: _region.text.trim(),
    prefix: _prefix.text.trim(),
    pathStyle: _pathStyle,
    allowInsecureHttp: _allowHttp,
  );

  CloudSyncCredentials get _credentials => CloudSyncCredentials(
    accessKeyId: _accessKey.text.trim(),
    secretAccessKey: _secretKey.text,
    sessionToken: _sessionToken.text.trim().isEmpty
        ? null
        : _sessionToken.text.trim(),
  );

  Future<void> _run(Future<void> Function() action) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _working = true);
    try {
      await action();
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l10n?.s3_connection_succeeded ?? 'S3 connection succeeded.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final status = ref.watch(cloudSyncControllerProvider);
    final enabled =
        ref.read(cloudSyncControllerProvider.notifier).config?.enabled == true;
    const fieldSpacing = SizedBox(height: 16);
    return Column(
      children: [
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => context.canPop()
                      ? context.pop()
                      : context.go(AppRoutes.settings),
                  icon: const Icon(Icons.arrow_back),
                ),
                Expanded(
                  child: Text(
                    l10n.cloud_sync,
                    style: Theme.of(context).textTheme.titleLarge,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        CloudSyncStatusCard(status: status),
                        const SizedBox(height: 20),
                        if (!enabled) ...[
                          TextFormField(
                            controller: _endpoint,
                            decoration: InputDecoration(
                              labelText: l10n.cloud_sync_endpoint,
                            ),
                            keyboardType: TextInputType.url,
                            validator: (_) => _config.validate(),
                          ),
                          fieldSpacing,
                          TextFormField(
                            controller: _bucket,
                            decoration: InputDecoration(
                              labelText: l10n.cloud_sync_bucket,
                            ),
                          ),
                          fieldSpacing,
                          TextFormField(
                            controller: _region,
                            decoration: InputDecoration(
                              labelText: l10n.cloud_sync_region,
                            ),
                          ),
                          fieldSpacing,
                          TextFormField(
                            controller: _prefix,
                            decoration: InputDecoration(
                              labelText: l10n.cloud_sync_prefix,
                            ),
                          ),
                          fieldSpacing,
                          TextFormField(
                            controller: _accessKey,
                            decoration: InputDecoration(
                              labelText: l10n.cloud_sync_access_key,
                            ),
                          ),
                          fieldSpacing,
                          TextFormField(
                            controller: _secretKey,
                            obscureText: true,
                            decoration: InputDecoration(
                              labelText: l10n.cloud_sync_secret_key,
                            ),
                          ),
                          fieldSpacing,
                          TextFormField(
                            controller: _sessionToken,
                            obscureText: true,
                            decoration: InputDecoration(
                              labelText: l10n.cloud_sync_session_token,
                            ),
                          ),
                          fieldSpacing,
                          TextFormField(
                            controller: _passphrase,
                            obscureText: true,
                            decoration: InputDecoration(
                              labelText: l10n.cloud_sync_passphrase,
                            ),
                            validator: (value) => (value?.length ?? 0) < 8
                                ? 'Use at least 8 characters.'
                                : null,
                          ),
                          fieldSpacing,
                          TextFormField(
                            controller: _confirmPassphrase,
                            obscureText: true,
                            decoration: InputDecoration(
                              labelText: l10n.cloud_sync_confirm_passphrase,
                            ),
                            validator: (value) => value != _passphrase.text
                                ? l10n.cloud_sync_passphrase_mismatch
                                : null,
                          ),
                          const SizedBox(height: 8),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(l10n.cloud_sync_path_style),
                            value: _pathStyle,
                            onChanged: (value) =>
                                setState(() => _pathStyle = value),
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(l10n.cloud_sync_allow_http),
                            subtitle: Text(l10n.cloud_sync_http_warning),
                            value: _allowHttp,
                            onChanged: (value) =>
                                setState(() => _allowHttp = value),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: _working
                                ? null
                                : () => _run(
                                    () => ref
                                        .read(
                                          cloudSyncControllerProvider.notifier,
                                        )
                                        .testConnection(_config, _credentials),
                                  ),
                            child: Text(l10n.cloud_sync_test),
                          ),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: _working
                                ? null
                                : () => _run(
                                    () => ref
                                        .read(
                                          cloudSyncControllerProvider.notifier,
                                        )
                                        .configure(
                                          config: _config,
                                          credentials: _credentials,
                                          passphrase: _passphrase.text,
                                        ),
                                  ),
                            child: Text(l10n.cloud_sync_enable),
                          ),
                        ] else ...[
                          FilledButton.icon(
                            onPressed: status.phase == CloudSyncPhase.syncing
                                ? null
                                : () => ref
                                      .read(
                                        cloudSyncControllerProvider.notifier,
                                      )
                                      .syncNow(),
                            icon: const Icon(Icons.sync),
                            label: Text(l10n.cloud_sync_now),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton(
                            onPressed: status.phase == CloudSyncPhase.syncing
                                ? null
                                : () => ref
                                      .read(
                                        cloudSyncControllerProvider.notifier,
                                      )
                                      .disconnect(),
                            child: Text(l10n.cloud_sync_disconnect),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
