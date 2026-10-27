import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../../data/remote/guardian_auth_repository.dart';
import '../../../domain/guardian_account.dart';
import '../../../domain/senior_profile.dart';

/// The signed-in guardian, or null. Follows sign-in, sign-out and token
/// refresh for the life of the app.
final guardianSessionProvider = StreamProvider<GuardianSession?>(
  (ref) => ref.watch(guardianAuthRepositoryProvider).sessionChanges(),
);

/// Whether a guardian session exists right now.
///
/// The launch gate needs an answer before the stream has produced one, so this
/// falls back to what the repository already restored from disk rather than
/// leaving `/` undecided while a spinner shows.
final guardianSignedInProvider = Provider<bool>((ref) {
  final stream = ref.watch(guardianSessionProvider);
  final restored = ref.watch(guardianAuthRepositoryProvider).currentSession;
  // `hasValue` rather than a null check on `value`: while the stream is still
  // loading, `value` is null for the same reason a signed-out guardian is, and
  // treating those alike would bounce a signed-in guardian to the splash.
  return ((stream.hasValue ? stream.value : null) ?? restored) != null;
});

/// The parents this guardian manages. Empty until they add one.
final linkedSeniorProfilesProvider = FutureProvider<List<SeniorProfile>>((
  ref,
) async {
  final session = ref.watch(guardianSessionProvider);
  if (!session.hasValue || session.value == null) return const [];
  final links = ref.watch(seniorLinkRepositoryProvider);
  await links.ensureGuardianAccount();
  return links.linkedSeniorProfiles();
});

/// What the login form is doing. Kept separate from the session itself so a
/// failed attempt does not read as a signed-out state.
sealed class GuardianLoginState {
  const GuardianLoginState();
}

class GuardianLoginIdle extends GuardianLoginState {
  const GuardianLoginIdle();
}

class GuardianLoginBusy extends GuardianLoginState {
  const GuardianLoginBusy();
}

class GuardianLoginFailed extends GuardianLoginState {
  const GuardianLoginFailed(this.message);

  final String message;
}

/// Sign-up succeeded but the account is not usable until the emailed link is
/// followed. Its own state because it is neither a failure nor a session.
class GuardianLoginAwaitingConfirmation extends GuardianLoginState {
  const GuardianLoginAwaitingConfirmation(this.email);

  final String email;
}

/// A reset link was sent, or would have been. Its own state because it is
/// neither a failure nor a session, and because the screen says the same
/// thing whether or not the address has an account.
class GuardianLoginResetSent extends GuardianLoginState {
  const GuardianLoginResetSent(this.email);

  final String email;
}

/// The address box was empty when 비밀번호를 잊으셨나요 was pressed. Not a
/// [GuardianLoginFailed]: nothing failed, the form is just not ready.
class GuardianLoginNeedsEmail extends GuardianLoginState {
  const GuardianLoginNeedsEmail();
}

class GuardianLoginController extends Notifier<GuardianLoginState> {
  @override
  GuardianLoginState build() => const GuardianLoginIdle();

  Future<bool> signIn({required String email, required String password}) async {
    if (!_validate(email, password)) return false;
    state = const GuardianLoginBusy();
    try {
      await ref
          .read(guardianAuthRepositoryProvider)
          .signIn(email: email, password: password);
      // The guardian's own row has to exist before any link can point at it,
      // and first sign-in on a new device is the first chance to create it.
      await ref.read(seniorLinkRepositoryProvider).ensureGuardianAccount();
      state = const GuardianLoginIdle();
      return true;
    } on GuardianAuthException catch (e) {
      state = GuardianLoginFailed(e.message);
      return false;
    } on Object {
      state = const GuardianLoginFailed('연결에 실패했어요. 잠시 후 다시 시도해 주세요.');
      return false;
    }
  }

  Future<bool> signUp({required String email, required String password}) async {
    if (!_validate(email, password)) return false;
    state = const GuardianLoginBusy();
    try {
      final result = await ref
          .read(guardianAuthRepositoryProvider)
          .signUp(email: email, password: password);
      if (result.needsConfirmation) {
        state = GuardianLoginAwaitingConfirmation(email.trim());
        return false;
      }
      await ref.read(seniorLinkRepositoryProvider).ensureGuardianAccount();
      state = const GuardianLoginIdle();
      return true;
    } on GuardianAuthException catch (e) {
      state = GuardianLoginFailed(e.message);
      return false;
    } on Object {
      state = const GuardianLoginFailed('연결에 실패했어요. 잠시 후 다시 시도해 주세요.');
      return false;
    }
  }

  /// Asks for the reset mail. Returns nothing a caller can branch on,
  /// because there is nothing a caller should branch on — an address with no
  /// account must look exactly like one that has.
  Future<void> sendPasswordReset({required String email}) async {
    final address = email.trim();
    if (address.isEmpty || !address.contains('@')) {
      state = const GuardianLoginNeedsEmail();
      return;
    }
    state = const GuardianLoginBusy();
    try {
      await ref
          .read(guardianAuthRepositoryProvider)
          .sendPasswordReset(email: address);
      state = GuardianLoginResetSent(address);
    } on GuardianAuthException catch (e) {
      // The rate limit is the one refusal worth passing on: pressing again
      // is exactly what a guardian does when no mail arrives, and 30 an hour
      // is a real ceiling.
      state = GuardianLoginFailed(e.message);
    } on Object {
      state = const GuardianLoginFailed('연결에 실패했어요. 잠시 후 다시 시도해 주세요.');
    }
  }

  Future<void> signOut() =>
      ref.read(guardianAuthRepositoryProvider).signOut();

  /// Checked here rather than in the form so the same rules apply however the
  /// screen is driven, and so the message is written once.
  bool _validate(String email, String password) {
    final trimmed = email.trim();
    if (trimmed.isEmpty || !trimmed.contains('@')) {
      state = const GuardianLoginFailed('이메일 주소를 확인해 주세요.');
      return false;
    }
    if (password.length < 6) {
      state = const GuardianLoginFailed('비밀번호는 6자 이상이어야 해요.');
      return false;
    }
    return true;
  }
}

final guardianLoginControllerProvider =
    NotifierProvider<GuardianLoginController, GuardianLoginState>(
      GuardianLoginController.new,
    );
