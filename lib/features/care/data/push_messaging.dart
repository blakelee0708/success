import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How the guardian's phone is told a message arrived.
///
/// It was built for 소리 울리기 and that feature is out of the product, so
/// what is left is one direction: a notification on the **child's** phone
/// when their parent writes. Android draws that itself from a `notification`
/// payload, with no handler here, so this interface is down to the two calls
/// that get an address and ask permission to use it.
///
/// It never runs on the parent's phone any more. A token is an address, and
/// with nothing left to send to it there is nothing to collect — see
/// `20261029060000_drop_ring.sql`, which takes the column away.
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
  /// Only the **guardian's** half reaches this, because theirs is the only
  /// half that is sent anything. A system dialog arriving on a launcher is
  /// the exact problem `HomeAppCoach` exists to soften.
  ///
  /// `POST_NOTIFICATIONS` is already in the built APK: `firebase_messaging`
  /// declares it and Gradle merges it in. What was missing was the asking.
  Future<void> requestPermission();
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
}

/// What a build with no Firebase gets. Silent rather than throwing: the
/// parent's launcher has to open on a phone that has never heard of FCM.
class NoPushMessaging implements PushMessaging {
  const NoPushMessaging();

  @override
  Future<String?> token() async => null;

  @override
  Future<void> requestPermission() async {}
}

/// What the tests use.
class FakePushMessaging implements PushMessaging {
  FakePushMessaging({this.fixedToken = 'token-abc'});

  String? fixedToken;

  /// Set to make [token] behave like a phone with no network.
  bool offline = false;

  int tokenReads = 0;
  int permissionAsks = 0;

  @override
  Future<String?> token() async {
    tokenReads++;
    if (offline) throw StateError('no network');
    return fixedToken;
  }

  @override
  Future<void> requestPermission() async => permissionAsks++;
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
