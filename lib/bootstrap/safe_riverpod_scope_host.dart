// ignore_for_file: implementation_imports, invalid_use_of_internal_member

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/src/internals.dart';

/// A [Vsync] proxy that intercepts Riverpod task scheduling and safely defers
/// refreshes to the next event loop iteration if Flutter is currently in the
/// middle of a build or render pass (`SchedulerPhase.persistentCallbacks`).
///
/// In Riverpod 3.x, out-of-view widgets are paused by default. When routes pop
/// or transition, [TickerMode] toggles during Flutter's build phase
/// (`_TickerModeState.didUpdateWidget`), synchronously resuming paused
/// subscriptions. Resuming flushes providers that changed while paused.
/// If any dependent provider invalidates during flush, Riverpod's default
/// [UncontrolledProviderScope] vsync invokes `setState()` synchronously,
/// crashing Flutter with "setState() or markNeedsBuild() called during build".
///
/// [SafeRiverpodVsync] eliminates this by checking if Flutter is currently
/// building, and using [Timer.zero] to schedule the refresh immediately after
/// the frame concludes.
class SafeRiverpodVsync implements Vsync {
  final Vsync delegate;

  SafeRiverpodVsync(this.delegate);

  @override
  void Function()? scheduleRefresh(Task task) {
    final phase = SchedulerBinding.instance.schedulerPhase;
    final isBuilding =
        phase == SchedulerPhase.persistentCallbacks ||
        WidgetsBinding.instance.buildOwner?.debugBuilding == true;

    if (isBuilding) {
      final timer = Timer(Duration.zero, task.call);
      return timer.cancel;
    }

    try {
      return delegate.scheduleRefresh(task);
    } catch (_) {
      final timer = Timer(Duration.zero, task.call);
      return timer.cancel;
    }
  }

  @override
  void Function()? scheduleDispose(Task task) {
    return delegate.scheduleDispose(task);
  }
}

/// Wraps the child of [UncontrolledProviderScope] and ensures all registered
/// vsyncs in [ProviderContainer.scheduler.flutterVsyncs] are protected by
/// [SafeRiverpodVsync].
class SafeRiverpodScopeHost extends StatefulWidget {
  final ProviderContainer container;
  final Widget child;

  const SafeRiverpodScopeHost({
    super.key,
    required this.container,
    required this.child,
  });

  @override
  State<SafeRiverpodScopeHost> createState() => _SafeRiverpodScopeHostState();
}

class _SafeRiverpodScopeHostState extends State<SafeRiverpodScopeHost> {
  @override
  void initState() {
    super.initState();
    _protectVsyncs();
  }

  @override
  void didUpdateWidget(SafeRiverpodScopeHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    _protectVsyncs();
  }

  void _protectVsyncs() {
    final scheduler = widget.container.scheduler;
    final vsyncs = scheduler.flutterVsyncs.toList();
    var hasUnwrapped = false;
    for (final v in vsyncs) {
      if (v is! SafeRiverpodVsync) {
        hasUnwrapped = true;
        break;
      }
    }
    if (hasUnwrapped) {
      scheduler.flutterVsyncs.clear();
      for (final v in vsyncs) {
        scheduler.flutterVsyncs.add(
          v is SafeRiverpodVsync ? v : SafeRiverpodVsync(v),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    _protectVsyncs();
    return widget.child;
  }
}
