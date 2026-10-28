import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../domain/guardian_account.dart';

/// Raised when sign-in or sign-up fails for a reason the guardian can act on.
///
/// Carries a Korean message because every caller is a screen. Supabase's own
/// messages are English and phrased for developers.
class GuardianAuthException implements Exception {
  const GuardianAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// What a sign-up attempt produced.
///
/// The project requires email confirmation, so signing up usually yields no
/// session at all. Returning that as a state rather than an error is the whole
/// point — the screen has to say 메일함을 확인해 주세요 instead of showing a failure.
class GuardianSignUpResult {
  const GuardianSignUpResult({this.session, required this.needsConfirmation});

  final GuardianSession? session;
  final bool needsConfirmation;
}

/// Guardian authentication.
///
/// Email/password only in Phase 4. `GuardianStartScreen` offers Kakao and
/// Google, and both are the intended path, but neither has an OAuth client
/// configured on the project yet; wiring a button that cannot complete would
/// be worse than one honest route that works.
abstract interface class GuardianAuthRepository {
  GuardianSession? get currentSession;

  /// Emits on every sign-in, sign-out and token refresh, starting with the
  /// session already restored from disk.
  Stream<GuardianSession?> sessionChanges();

  Future<GuardianSession> signIn({
    required String email,
    required String password,
  });

  Future<GuardianSignUpResult> signUp({
    required String email,
    required String password,
  });

  /// Opens the provider's own sign-in, and returns as soon as the browser
  /// has it. **A guardian is not signed in when this completes** — the
  /// session arrives later, through [oauthRedirect], and the screen must not
  /// move on as though it had.
  Future<void> signInWithOAuth(GuardianOAuthProvider provider);

  /// Emails a link that lets the holder choose a new password.
  ///
  /// **Never reports whether the address has an account.** Answering that
  /// turns the login form into a way of asking the server which addresses
  /// are registered; Supabase declines to answer and so does this.
  ///
  /// The link lands on [passwordResetRedirect] rather than on `site_url`,
  /// because a reset has to arrive at a form that takes a new password — the
  /// confirmation page only says a thing already happened.
  Future<void> sendPasswordReset({required String email});

  Future<void> signOut();
}

/// The social providers the start screen offers.
///
/// An enum rather than a string because one handler serves both buttons, and
/// passing the wrong provider is the kind of mistake that looks right on the
/// screen and signs somebody in to the other account.
enum GuardianOAuthProvider {
  kakao,
  google;

  /// What the sheet calls it when the project has not set it up yet.
  String get label => switch (this) {
    GuardianOAuthProvider.kakao => '카카오',
    GuardianOAuthProvider.google => '구글',
  };
}

/// Where the provider sends the guardian back to.
///
/// A custom scheme built from the application id, which is the convention
/// and is already unique to this app. It has to be registered in **three**
/// places that cannot see each other: the Android manifest's intent-filter,
/// the project's `uri_allow_list`, and here. Miss the allow list and
/// Supabase refuses the redirect; miss the manifest and the browser finishes
/// the sign-in and then has nowhere to hand it back to.
const oauthRedirect = 'com.jalboine.app://login-callback';

/// Where the emailed reset link lands.
///
/// Published from `site/` by `.github/workflows/pages.yml`. It is a constant
/// rather than a `--dart-define` because it is not a secret and a build that
/// silently had no value would send guardians to nowhere.
///
/// **It must also be in the project's `uri_allow_list`.** Supabase refuses a
/// `redirectTo` it does not recognise and falls back to `site_url`, which
/// would land a password reset on the page that says 확인이 끝났어요 — a
/// screen with no password field, reached by someone who came to set one.
///
/// **A custom domain, not `*.github.io`, and that is the owner's decision
/// rather than a tidying-up.** This string is printed in a password-reset
/// mail, so it is the one place a guardian reads the project's address, and
/// a GitHub username is not what should be standing there. The repository
/// moved from `jdnnetwork` to `blakelee0708` on 2026-10-27, which would have
/// broken the old value anyway: a project site serves under `/<repo>/` only
/// on the default `*.github.io` host, and a repository with its own domain
/// serves at that domain's root — so there is no `/success/` in the path any
/// more.
const passwordResetRedirect = 'https://app.jalboine.com/reset.html';

class SupabaseGuardianAuthRepository implements GuardianAuthRepository {
  SupabaseGuardianAuthRepository(this._client);

  final sb.SupabaseClient _client;

  @override
  GuardianSession? get currentSession =>
      _toSession(_client.auth.currentSession);

  @override
  Stream<GuardianSession?> sessionChanges() async* {
    yield currentSession;
    yield* _client.auth.onAuthStateChange.map((e) => _toSession(e.session));
  }

  @override
  Future<GuardianSession> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      final session = _toSession(response.session);
      if (session == null) {
        throw const GuardianAuthException('로그인하지 못했어요. 잠시 후 다시 시도해 주세요.');
      }
      return session;
    } on sb.AuthException catch (e) {
      throw GuardianAuthException(_readable(e));
    }
  }

  @override
  Future<GuardianSignUpResult> signUp({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _client.auth.signUp(
        email: email.trim(),
        password: password,
      );
      final session = _toSession(response.session);
      return GuardianSignUpResult(
        session: session,
        needsConfirmation: session == null,
      );
    } on sb.AuthException catch (e) {
      throw GuardianAuthException(_readable(e));
    }
  }

  @override
  Future<void> signInWithOAuth(GuardianOAuthProvider provider) async {
    try {
      await _client.auth.signInWithOAuth(
        switch (provider) {
          GuardianOAuthProvider.kakao => sb.OAuthProvider.kakao,
          GuardianOAuthProvider.google => sb.OAuthProvider.google,
        },
        redirectTo: oauthRedirect,
        // The phone's own browser, not a web view inside the app. Kakao
        // signs people in through the session their browser already holds,
        // and an in-app view starts from nobody — which turns one tap into
        // typing a password the guardian probably does not remember.
        authScreenLaunchMode: sb.LaunchMode.externalApplication,
      );
    } on sb.AuthException catch (e) {
      throw GuardianAuthException(_readable(e));
    }
  }

  @override
  Future<void> sendPasswordReset({required String email}) async {
    try {
      await _client.auth.resetPasswordForEmail(
        email.trim(),
        redirectTo: passwordResetRedirect,
      );
    } on sb.AuthException catch (e) {
      throw GuardianAuthException(_readable(e));
    }
  }

  @override
  Future<void> signOut() => _client.auth.signOut();

  static GuardianSession? _toSession(sb.Session? session) {
    final user = session?.user;
    if (user == null) return null;
    return GuardianSession(userId: user.id, email: user.email);
  }

  /// Only the cases a guardian can do something about are translated; anything
  /// else keeps Supabase's text so a bug does not hide behind a friendly line.
  static String _readable(sb.AuthException e) {
    final code = e.code ?? '';
    if (code == 'invalid_credentials' ||
        e.message.contains('Invalid login credentials')) {
      return '이메일이나 비밀번호가 맞지 않아요.';
    }
    if (code == 'email_not_confirmed') {
      return '메일함에서 인증 메일을 먼저 확인해 주세요.';
    }
    if (code == 'user_already_exists' || code == 'email_exists') {
      return '이미 가입된 이메일이에요. 로그인해 주세요.';
    }
    if (code == 'weak_password') {
      return '비밀번호가 너무 짧아요. 6자 이상으로 정해 주세요.';
    }
    // Said by the project until the owner finishes that provider's console
    // work. Worth translating because it is the one failure here that is
    // nobody's mistake and fixes itself the day the setup lands.
    if (code == 'validation_failed' ||
        e.message.contains('provider is not enabled') ||
        e.message.contains('Unsupported provider')) {
      return '아직 준비 중이에요. 이메일로 시작해 주세요.';
    }
    if (code == 'over_email_send_rate_limit') {
      return '메일을 너무 자주 보냈어요. 잠시 후 다시 시도해 주세요.';
    }
    return e.message;
  }
}

/// Stand-in used when the build carries no Supabase keys, and by tests.
///
/// Behaves like the real thing on the paths screens depend on — a bad password
/// fails, a duplicate email fails, a session survives until sign-out — so a
/// widget test exercises the same branches the live repository would.
class InMemoryGuardianAuthRepository implements GuardianAuthRepository {
  InMemoryGuardianAuthRepository({this.confirmationRequired = true});

  /// Mirrors the project's `mailer_autoconfirm = false`.
  final bool confirmationRequired;

  final _accounts = <String, String>{};
  final _confirmed = <String>{};
  final _sessions = StreamController<GuardianSession?>.broadcast();

  GuardianSession? _current;

  @override
  GuardianSession? get currentSession => _current;

  @override
  Stream<GuardianSession?> sessionChanges() async* {
    yield _current;
    yield* _sessions.stream;
  }

  @override
  Future<GuardianSession> signIn({
    required String email,
    required String password,
  }) async {
    final key = email.trim().toLowerCase();
    if (_accounts[key] != password) {
      throw const GuardianAuthException('이메일이나 비밀번호가 맞지 않아요.');
    }
    if (!_confirmed.contains(key)) {
      throw const GuardianAuthException('메일함에서 인증 메일을 먼저 확인해 주세요.');
    }
    return _emit(GuardianSession(userId: 'user-$key', email: key))!;
  }

  @override
  Future<GuardianSignUpResult> signUp({
    required String email,
    required String password,
  }) async {
    final key = email.trim().toLowerCase();
    if (_accounts.containsKey(key)) {
      throw const GuardianAuthException('이미 가입된 이메일이에요. 로그인해 주세요.');
    }
    if (password.length < 6) {
      throw const GuardianAuthException('비밀번호가 너무 짧아요. 6자 이상으로 정해 주세요.');
    }
    _accounts[key] = password;
    if (confirmationRequired) {
      return const GuardianSignUpResult(needsConfirmation: true);
    }
    _confirmed.add(key);
    return GuardianSignUpResult(
      session: _emit(GuardianSession(userId: 'user-$key', email: key)),
      needsConfirmation: false,
    );
  }

  /// Every provider a sign-in was asked of, in order.
  final oauthAttempts = <GuardianOAuthProvider>[];

  /// Set to make the next provider sign-in fail with this message, the way a
  /// project that has not set the provider up answers.
  String? oauthFailure;

  @override
  Future<void> signInWithOAuth(GuardianOAuthProvider provider) async {
    oauthAttempts.add(provider);
    final failure = oauthFailure;
    if (failure != null) throw GuardianAuthException(failure);
    // Deliberately emits no session. The real one opens a browser and comes
    // back through a deep link much later, so a test that signed in here
    // would be testing something the app never does.
  }

  /// Every address a reset was asked for, in order — including ones with no
  /// account, because the real repository cannot tell the difference either.
  final resetRequests = <String>[];

  @override
  Future<void> sendPasswordReset({required String email}) async {
    resetRequests.add(email.trim());
  }

  @override
  Future<void> signOut() async => _emit(null);

  /// Lets a test start from a signed-in guardian without a round trip.
  void seedSignedIn(GuardianSession session) => _emit(session);

  /// Marks an address as having followed the confirmation link.
  void confirm(String email) => _confirmed.add(email.trim().toLowerCase());

  GuardianSession? _emit(GuardianSession? session) {
    _current = session;
    if (!_sessions.isClosed) _sessions.add(session);
    return session;
  }

  void dispose() => _sessions.close();
}
