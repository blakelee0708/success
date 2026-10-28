import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../care/data/push_messaging.dart';

/// Tells the server where this guardian's phone can be reached.
///
/// Run from the dashboard rather than from sign-in, and on **every** open:
/// a token rotates on a reinstall, on a restore onto a new handset, and
/// occasionally for Firebase's own reasons. Registering once at sign-in would
/// go stale in silence, which is how a notification stops arriving with
/// nothing anywhere saying so - the same argument the senior's token rides on
/// the check-in for.
///
/// **Nothing here is awaited by anything drawn.** `token()` is a platform
/// channel and a channel that never answers throws nothing at all, so the
/// rule this codebase has walked into three times applies: the dashboard must
/// open whether or not Firebase replies.
class GuardianPushRegistrar {
  GuardianPushRegistrar(this._ref);

  final Ref _ref;

  /// Guards against the two rebuilds a tab switch causes. Not a one-shot:
  /// a fresh registrar is built per dashboard, which is what gives the
  /// rotation its chance.
  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;
    unawaited(_register());
  }

  Future<void> _register() async {
    try {
      final push = _ref.read(pushMessagingProvider);
      // Asked before the token is read, because a token with notifications
      // denied is an address that accepts post and burns it. On Android 13+
      // this is the `POST_NOTIFICATIONS` dialog; `firebase_messaging` already
      // declares the permission, so what was missing was only the asking.
      await push.requestPermission();
      final token = await push.token();
      if (token == null || token.isEmpty) return;
      await _ref.read(seniorLinkRepositoryProvider).registerPushToken(token);
    } on Object {
      // A phone with no Play Services, no network, or a guardian account that
      // does not exist yet. The next dashboard open tries again, and what is
      // lost in between is a notification rather than a screen.
    }
  }
}

final guardianPushRegistrarProvider = Provider<GuardianPushRegistrar>(
  GuardianPushRegistrar.new,
);
