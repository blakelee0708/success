import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How a guardian's 소리 울리기 reaches their parent's phone.
///
/// It is the only thing in the app that is triggered remotely. Everything
/// else the guardian changes — the home buttons, the text size, a message —
/// is read by the parent's phone the next time it asks, and that is fine
/// because none of it is urgent. A phone that has to make a noise *now*
/// cannot wait for the next resume, because the case this exists for is a
/// phone nobody is holding.
///
/// Wrapped in an interface for the same reason every repository here is: a
/// build with no `google-services.json`, and every `flutter test`, resolves to
/// [NoPushMessaging] and carries on. Nothing above this layer knows which one
/// it got.
abstract interface class PushMessaging {
  /// The address this phone is reachable at, or null when this build has no
  /// Firebase and when the phone has no network to fetch one over.
  Future<String?> token();

  /// Asks for permission to show notifications, where the phone has such a
  /// thing to ask.
  ///
  /// Only the **guardian's** half calls this. On the senior's phone a ring is
  /// drawn as a full-screen layer by the app itself, so no notification is
  /// posted and nothing needs granting — and a system dialog arriving on a
  /// launcher is the exact problem `HomeAppCoach` exists to soften.
  ///
  /// `POST_NOTIFICATIONS` is already in the built APK: `firebase_messaging`
  /// declares it and Gradle merges it in. What was missing was the asking.
  Future<void> requestPermission();

  /// Data messages arriving **while the app is running in the foreground**.
  ///
  /// That limit is real and it is currently the feature's ceiling: a phone
  /// with its screen off does not deliver here, and waking it needs a native
  /// background handler that does not exist yet. See `## 소리 울리기` in
  /// CLAUDE.md.
  Stream<Map<String, String>> messages();
}

class FirebasePushMessaging implements PushMessaging {
  FirebasePushMessaging(this._messaging);

  final FirebaseMessaging _messaging;

  @override
  Future<String?> token() async {
    try {
      return await _messaging.getToken();
    } on Object {
      // A phone with no Play Services, or no network at the moment it asked.
      // The check-in runs again on every resume, so this fixes itself.
      return null;
    }
  }

  @override
  Future<void> requestPermission() async {
    try {
      await _messaging.requestPermission();
    } on Object {
      // A phone with no Play Services, or one that answered nothing. The
      // dashboard draws either way; what is lost is a notification, not a
      // screen.
    }
  }

  @override
  Stream<Map<String, String>> messages() => FirebaseMessaging.onMessage.map(
    (m) => m.data.map((k, v) => MapEntry(k, '$v')),
  );
}

/// What a build with no Firebase gets. Silent rather than throwing: the
/// parent's launcher has to open on a phone that has never heard of FCM.
class NoPushMessaging implements PushMessaging {
  const NoPushMessaging();

  @override
  Future<String?> token() async => null;

  @override
  Future<void> requestPermission() async {}

  @override
  Stream<Map<String, String>> messages() => const Stream.empty();
}

/// What the tests use.
class FakePushMessaging implements PushMessaging {
  FakePushMessaging({this.fixedToken = 'token-abc'});

  String? fixedToken;

  /// Set to make [token] behave like a phone with no network.
  bool offline = false;

  int tokenReads = 0;
  int permissionAsks = 0;

  final _messages = StreamController<Map<String, String>>.broadcast();

  @override
  Future<String?> token() async {
    tokenReads++;
    if (offline) throw StateError('no network');
    return fixedToken;
  }

  @override
  Future<void> requestPermission() async => permissionAsks++;

  @override
  Stream<Map<String, String>> messages() => _messages.stream;

  /// Delivers a push as if it had arrived from the server.
  void deliver(Map<String, String> data) => _messages.add(data);

  void dispose() => _messages.close();
}

/// Firebase when the build has it, silence when it does not.
///
/// `Firebase.apps` is the question rather than a `--dart-define`, because
/// whether this build has Firebase is decided by whether
/// `android/app/google-services.json` was present at build time and whether
/// `main` managed to initialise — not by anything that can be passed in.
final pushMessagingProvider = Provider<PushMessaging>((ref) {
  if (Firebase.apps.isEmpty) return const NoPushMessaging();
  return FirebasePushMessaging(FirebaseMessaging.instance);
});
