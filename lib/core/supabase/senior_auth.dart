import 'package:supabase_flutter/supabase_flutter.dart' as sb;

/// Signs the parent's phone in, because the senior is never asked to make an
/// account and the server still has to know who is calling.
///
/// **This was missing, and it took every senior-side server call down with
/// it.** `senior_devices.auth_user_id` has been the documented tie between an
/// anonymous user and the profile RLS lets it touch since Phase 4, and every
/// one of those functions opens with `if auth.uid() is null then raise
/// exception 'not authenticated'`. Nothing in the app ever created the
/// session, so on a real phone 번호 보여주기 raised that exception and the
/// screen showed `번호를 받지 못했어요. 인터넷 연결을 확인해 주세요.` — a
/// sentence about the network, for a failure that had nothing to do with it.
///
/// **No test could have caught it and no verifier did.** The in-memory twins
/// need no session at all, so `flutter test` passed; every `tool/verify_*`
/// script signs itself in with its own `/auth/v1/signup` call before it starts,
/// because it is standing in for the phone. The one path nobody exercised was
/// the app's own.
abstract interface class SeniorAuth {
  /// Returns true when there is a session to call the server with.
  ///
  /// Awaited rather than fired and forgotten: this is a network call, not a
  /// platform channel, and the thing waiting on it is a screen that is
  /// already showing a spinner. The rule it does not break is the one about
  /// channels — a channel may never answer at all, where a request either
  /// answers or fails.
  Future<bool> ensure();
}

/// The build has no project, so there is nothing to sign in to and nothing
/// above this layer should care. Every repository is already its in-memory
/// twin in that case, and those answer without a session.
class OpenSeniorAuth implements SeniorAuth {
  const OpenSeniorAuth();

  @override
  Future<bool> ensure() async => true;
}

class SupabaseSeniorAuth implements SeniorAuth {
  SupabaseSeniorAuth(this._client);

  final sb.SupabaseClient _client;

  /// The sign-in in flight, so a burst of callers — the check-in, the
  /// settings pull and a tap on 번호 보여주기 can all land in the same frame —
  /// produces one anonymous user rather than three.
  Future<bool>? _pending;

  @override
  Future<bool> ensure() {
    // A session restored from disk is the usual case: gotrue persists it and
    // refreshes it, so this costs nothing on every launch after the first.
    if (_client.auth.currentSession != null) return Future.value(true);
    return _pending ??= _signIn();
  }

  Future<bool> _signIn() async {
    try {
      final result = await _client.auth.signInAnonymously();
      return result.session != null;
    } on Object {
      // A phone with no signal, or a project with anonymous sign-ins turned
      // off. The caller's own failure path says what the senior sees; this
      // one must not throw a second exception over the first.
      return false;
    } finally {
      _pending = null;
    }
  }
}
