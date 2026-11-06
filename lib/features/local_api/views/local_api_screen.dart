import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/inference/local_inference.dart';
import '../../../l10n/app_localizations.dart';
import '../providers/local_api_provider.dart';
import 'components/local_api_configuration_form.dart';
import 'components/local_api_connection_details.dart';

class LocalApiScreen extends ConsumerWidget {
  const LocalApiScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(localApiProvider);
    final model = ref.watch(localInferenceModelProvider);
    final notifier = ref.read(localApiProvider.notifier);
    final status = switch (state.phase) {
      LocalApiPhase.running => l10n.localApiRunning,
      LocalApiPhase.stopped => l10n.localApiStopped,
      LocalApiPhase.starting => l10n.localApiStarting,
      LocalApiPhase.stopping => l10n.localApiStopping,
      LocalApiPhase.rotating => l10n.localApiRotating,
    };
    final failure = switch (state.failure) {
      LocalApiFailure.modelRequired => l10n.localApiModelRequired,
      LocalApiFailure.invalidPort => l10n.localApiInvalidPort,
      LocalApiFailure.unavailable => l10n.localApiStartFailed,
      LocalApiFailure.portUnavailable => l10n.localApiPortUnavailable,
      LocalApiFailure.key => l10n.localApiKeyFailed,
      null => null,
    };
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: const LocalApiBackButton(),
        title: Text(l10n.localApiTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(l10n.localApiIntro),
          const SizedBox(height: 16),
          Semantics(
            liveRegion: true,
            child: Text(status, style: Theme.of(context).textTheme.titleMedium),
          ),
          if (failure != null)
            Semantics(
              liveRegion: true,
              child: Text(
                failure,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 12),
          if (model == null)
            Text(l10n.localApiModelRequired)
          else
            LocalApiCopyRow(label: l10n.localApiModelId, value: model.id),
          if (model != null)
            Text(
              model.supportsTools
                  ? l10n.localApiTextAndTools
                  : l10n.localApiTextOnly,
            ),
          const SizedBox(height: 16),
          LocalApiConfigurationForm(
            config: state.config,
            enabled: !state.running && !state.busy,
            canStart: !state.running && !state.busy && model != null,
            onStart: (port, lan) => notifier.start(
              port: port,
              lan: lan,
              notification: l10n.localApiRunning,
              stopLabel: l10n.localApiStop,
            ),
          ),
          if (state.running)
            FilledButton(
              onPressed: state.busy ? null : notifier.stop,
              child: Text(l10n.localApiStop),
            ),
          if (state.running) ...[
            const SizedBox(height: 12),
            LocalApiCopyRow(label: l10n.localApiUrl, value: state.url),
            for (final url in state.lanUrls)
              LocalApiCopyRow(label: l10n.localApiLanUrl, value: url),
            if (state.config.lan && state.lanUrls.isEmpty)
              Text(l10n.localApiNoLan),
          ],
          if (state.key case final key?)
            LocalApiKeyCard(
              apiKey: key,
              onRotate: state.busy ? null : notifier.rotateKey,
            ),
        ],
      ),
    );
  }
}
