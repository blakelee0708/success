import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../data/app_launcher.dart';
import 'senior_settings_controller.dart';

/// Returns the app to its first screen when the Home key is pressed.
///
/// Once this app is the phone's home app, pressing Home does not restart it —
/// Android hands the running task a fresh HOME intent. Without listening for
/// that, the key does nothing whenever the senior is anywhere but the home
/// screen, which is exactly when they reach for it.
///
/// Wrapped around the router rather than placed on a screen: the point is to
/// leave whichever screen is on top, so it cannot live on any of them.
class HomeKeyListener extends ConsumerStatefulWidget {
  const HomeKeyListener({
    super.key,
    required this.router,
    required this.child,
  });

  final GoRouter router;
  final Widget child;

  @override
  ConsumerState<HomeKeyListener> createState() => _HomeKeyListenerState();
}

class _HomeKeyListenerState extends ConsumerState<HomeKeyListener>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    MethodChannelAppLauncher.channel.setMethodCallHandler(_onCall);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    MethodChannelAppLauncher.channel.setMethodCallHandler(null);
    super.dispose();
  }

  /// Coming back to the foreground re-reads the server.
  ///
  /// The start-up pull covers a phone that was switched off. This covers the
  /// commoner case: a launcher is the screen a phone sits on, so it may not
  /// be restarted for weeks, and a change the guardian made yesterday would
  /// otherwise wait for a reboot.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    ref.read(seniorSettingsControllerProvider.notifier).refresh();
  }

  Future<void> _onCall(MethodCall call) async {
    if (call.method != 'goHome') return;
    // The launch gate, not a home screen directly: on a phone the senior has
    // set up it resolves to their chosen home, and on one they have not it
    // still lands somewhere sensible.
    widget.router.go(Routes.firstScreen);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
