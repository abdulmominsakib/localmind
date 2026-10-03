import 'package:flutter/widgets.dart';

/// Back-button policy the app shell hands down to the pages of its nested
/// navigator.
///
/// The shell's own route sits on the root navigator, above the nested one.
/// A [PopScope] placed there is invisible to Android's predictive back
/// (Android 16+): the nested navigator reports "can't handle back" on every
/// navigation, the root navigator forwards that unchanged, and the engine
/// gives back to the OS, which closes the app. The [PopScope] therefore has
/// to live inside each page of the nested navigator — see [ShellBackScope].
class ShellBackPolicy extends InheritedWidget {
  const ShellBackPolicy({
    super.key,
    required this.interceptsAll,
    required this.interceptsRoot,
    required this.onBack,
    required super.child,
  });

  /// Back goes to [onBack] on every page, even ones that could pop
  /// themselves — e.g. while the drawer is open.
  final bool interceptsAll;

  /// Back on the nested navigator's first page goes to [onBack] instead of
  /// leaving the app.
  final bool interceptsRoot;

  /// Must read live state when called rather than capture it, since a
  /// change to this callback alone doesn't notify dependents.
  final VoidCallback onBack;

  static ShellBackPolicy? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellBackPolicy>();

  @override
  bool updateShouldNotify(ShellBackPolicy oldWidget) =>
      interceptsAll != oldWidget.interceptsAll ||
      interceptsRoot != oldWidget.interceptsRoot ||
      onBack != oldWidget.onBack;
}

/// Lets a widget above the app shell — e.g. a full-screen overlay drawn over
/// it — claim Back while it is visible. The shell routes every Back press
/// to [onBack] while one is present.
class ShellBackOverride extends InheritedWidget {
  const ShellBackOverride({
    super.key,
    required this.onBack,
    required super.child,
  });

  final VoidCallback? onBack;

  static VoidCallback? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellBackOverride>()?.onBack;

  /// Reads the current override without registering a dependency, for use
  /// in event handlers.
  static VoidCallback? read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ShellBackOverride>()?.onBack;

  @override
  bool updateShouldNotify(ShellBackOverride oldWidget) =>
      onBack != oldWidget.onBack;
}

/// Wraps a page of the shell's nested navigator so Back follows the
/// enclosing [ShellBackPolicy].
class ShellBackScope extends StatelessWidget {
  const ShellBackScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final policy = ShellBackPolicy.maybeOf(context);
    if (policy == null) return child;

    final routeCanPop = ModalRoute.of(context)?.canPop ?? false;
    final intercepts =
        policy.interceptsAll || (!routeCanPop && policy.interceptsRoot);

    return PopScope(
      canPop: !intercepts,
      onPopInvokedWithResult: (didPop, _) {
        // Another PopScope on this page may have blocked the pop; only act
        // when this scope is the one intercepting.
        if (didPop || !intercepts) return;
        policy.onBack();
      },
      child: child,
    );
  }
}
