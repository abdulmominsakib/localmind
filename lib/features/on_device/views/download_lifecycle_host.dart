import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/on_device_providers.dart';

/// App-lifecycle host that starts the download lifecycle observer (app
/// backgrounding, detachment and connectivity changes driving pause/resume
/// of download-engine tasks) and stops it on dispose.
class DownloadLifecycleHost extends ConsumerStatefulWidget {
  const DownloadLifecycleHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<DownloadLifecycleHost> createState() =>
      _DownloadLifecycleHostState();
}

class _DownloadLifecycleHostState
    extends ConsumerState<DownloadLifecycleHost> {
  @override
  void initState() {
    super.initState();
    ref.read(downloadLifecycleObserverProvider).start();
  }

  @override
  void dispose() {
    ref.read(downloadLifecycleObserverProvider).stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
