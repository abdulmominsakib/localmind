import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:objectbox/objectbox.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/providers/storage_providers.dart';
import '../../../core/storage/entities.dart';
import '../providers/cloud_sync_providers.dart';

class CloudSyncLifecycleHost extends ConsumerStatefulWidget {
  const CloudSyncLifecycleHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<CloudSyncLifecycleHost> createState() =>
      _CloudSyncLifecycleHostState();
}

class _CloudSyncLifecycleHostState extends ConsumerState<CloudSyncLifecycleHost>
    with WidgetsBindingObserver {
  StreamSubscription<List<Type>>? _databaseSubscription;
  ProviderSubscription<dynamic>? _settingsSubscription;

  static const _syncedTypes = <Type>{
    ConversationEntity,
    MessageEntity,
    PersonaEntity,
    ConversationFolderEntity,
    SavedMessageEntity,
    SavedMessageFolderEntity,
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _databaseSubscription = ref
        .read(databaseProvider)
        .store
        .entityChanges
        .listen((types) {
          // The stream may emit one last event between cancel() and full
          // shutdown, so guard every ref access even though we cancel in
          // dispose.
          if (!mounted) return;
          if (types.any(_syncedTypes.contains)) {
            ref.read(cloudSyncControllerProvider.notifier).scheduleSync();
          }
        });
    _settingsSubscription = ref.listenManual(settingsProvider, (_, next) {
      ref.read(cloudSyncControllerProvider.notifier).scheduleSync();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Same guard — the post-frame callback runs after initState returns,
      // and the State may already be deactivated if the host was rebuilt
      // and torn down quickly.
      if (!mounted) return;
      ref
          .read(cloudSyncControllerProvider.notifier)
          .scheduleSync(delay: Duration.zero);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref
          .read(cloudSyncControllerProvider.notifier)
          .scheduleSync(delay: Duration.zero);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_databaseSubscription?.cancel());
    _settingsSubscription?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
