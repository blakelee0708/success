import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import 'widgets/guardian_surfaces.dart';
import '../application/guardian_session_controller.dart';

/// Widget keys the tests drive.
class GuardianLoginKeys {
  GuardianLoginKeys._();

  static const email = Key('guardian-login-email');
  static const password = Key('guardian-login-password');
  static const submit = Key('guardian-login-submit');

  /// The 새로 가입하기 tab. Named for what it did when it was a link under
  /// the button, which every test that creates an account still presses.
  static const toggleMode = Key('guardian-login-signup-tab');
  static const signInTab = Key('guardian-login-signin-tab');
  static const progress = Key('guardian-login-progress');
  static const forgot = Key('guardian-login-forgot');
  static const message = Key('guardian-login-message');
}

/// 보호자 로그인. Email and password, which is what the project's auth settings
/// actually support today.
///
/// `GuardianStartScreen` argues for Kakao and Google, and that is still the
/// intended entry — but neither has an OAuth client configured on the Supabase
/// project, so a button there would fail on tap. This screen is the honest
/// route in the meantime rather than a replacement for that decision.
class GuardianLoginScreen extends ConsumerStatefulWidget {
  const GuardianLoginScreen({super.key});

  /// How long 가입이 완료됐어요 stays before the next screen. Long enough to
  /// be read, short enough that nobody reaches for a button that is not there.
  static const doneHold = Duration(milliseconds: 1200);

  @override
  ConsumerState<GuardianLoginScreen> createState() =>
      _GuardianLoginScreenState();
}

class _GuardianLoginScreenState extends ConsumerState<GuardianLoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _creatingAccount = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  /// Set while the 가입 card is up; true once the account exists.
  ValueNotifier<bool>? _signUpDone;

  Future<void> _submit() async {
    final controller = ref.read(guardianLoginControllerProvider.notifier);
    if (!_creatingAccount) {
      final ok = await controller.signIn(
        email: _email.text,
        password: _password.text,
      );
      if (ok && mounted) context.go(Routes.guardianDashboard);
      return;
    }

    final ok = await controller.signUp(
      email: _email.text,
      password: _password.text,
    );
    final card = _signUpDone;
    if (!mounted) return;
    if (!ok) {
      // Refused, or waiting on a confirmation mail: the card goes and the
      // message under the fields says which.
      if (card != null) Navigator.of(context, rootNavigator: true).pop();
      return;
    }
    card?.value = true;
    await Future<void>.delayed(GuardianLoginScreen.doneHold);
    if (!mounted) return;
    if (_signUpDone != null) Navigator.of(context, rootNavigator: true).pop();
    context.go(Routes.guardianDashboard);
  }

  /// **Said in the middle of the screen, not on the button.** The button
  /// changing its word to 잠시만요 was the whole of it before, and the screen
  /// then moved on with nothing having said an account now existed. Opened
  /// only once the request is actually sent - a form refused for a short
  /// password never shows it - and never dismissible, because there is
  /// nothing to cancel.
  void _showSignUpCard() {
    final done = ValueNotifier(false);
    _signUpDone = done;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(canPop: false, child: _SignUpCard(done: done)),
    ).whenComplete(() {
      if (identical(_signUpDone, done)) _signUpDone = null;
      done.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(guardianLoginControllerProvider);
    final busy = state is GuardianLoginBusy;
    ref.listen(guardianLoginControllerProvider, (before, now) {
      if (now is GuardianLoginBusy &&
          before is! GuardianLoginBusy &&
          _creatingAccount &&
          _signUpDone == null) {
        _showSignUpCard();
      }
    });

    return Theme(
      data: AppTheme.guardian,
      child: Scaffold(
        backgroundColor: AppColors.guardianGroundEnd,
        // No AppBar. A transparent one still leaves the Scaffold's own colour
        // behind it, so the gradient ended in a hard seam under the arrow.
        // The back control goes in the body, as it does on the start screen.
        body: GuardianGround(
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 4, 22, 34),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      icon: const Icon(Icons.chevron_left),
                      iconSize: 26,
                      color: AppColors.guardianInkSoft,
                      onPressed: () => context.go(Routes.guardianStartButtons),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // **Two tabs, not a link.** Signing up was one small blue
                  // line under the button, 계정이 없어요, 새로 만들래요, and a
                  // guardian looking for it could not tell it was there. A
                  // password is the one thing a person does have to know
                  // whether they already made, so on this screen the two are
                  // a choice in plain view.
                  GuardianSwitcher(
                    large: true,
                    keys: const [
                      GuardianLoginKeys.signInTab,
                      GuardianLoginKeys.toggleMode,
                    ],
                    options: const [
                      ('로그인', Icons.login_rounded),
                      ('새로 가입하기', Icons.person_add_rounded),
                    ],
                    selected: _creatingAccount ? 1 : 0,
                    onSelected: (i) {
                      if (busy) return;
                      setState(() => _creatingAccount = i == 1);
                    },
                  ),
                  const SizedBox(height: 26),
                  GuardianHeading(
                    title: _creatingAccount ? '보호자 계정 만들기' : '보호자 로그인',
                    lede: _creatingAccount
                        ? '부모님 폰을 대신 정리해 드리려면 보호자 계정이 필요해요.'
                        // **폰을 바꿨을 때의 함정이 여기 있다.** A guardian
                        // changing handset needs no reconnecting at all -
                        // `guardian_accounts` is unique on `auth_user_id`, so
                        // the same account is the same family, subscription
                        // and conversation. But signing in **another way**
                        // makes a different person: email first and then
                        // Kakao is an empty account with no parent, and
                        // connecting their mother again meets the family-plan
                        // gate, which tells them 가족 플랜이 필요해요 about
                        // the parent they already had. One line, before they
                        // can do it, because afterwards it cannot be undone
                        // from inside the app.
                        : '전에 쓰시던 방법으로 로그인해 주세요. '
                              '다른 방법으로 로그인하면 새 계정이 됩니다.',
                  ),
                  const SizedBox(height: 26),
                  TextField(
                    key: GuardianLoginKeys.email,
                    controller: _email,
                    enabled: !busy,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: guardianField(label: '이메일'),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    key: GuardianLoginKeys.password,
                    controller: _password,
                    enabled: !busy,
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    decoration: guardianField(label: '비밀번호', helper: '6자 이상'),
                  ),
                  if (_messageFor(state) case final message?) ...[
                    const SizedBox(height: 14),
                    _Message(
                      key: GuardianLoginKeys.message,
                      text: message,
                      isError: state is GuardianLoginFailed,
                    ),
                  ],
                  const SizedBox(height: 22),
                  GuardianPrimaryButton(
                    key: GuardianLoginKeys.submit,
                    onPressed: busy ? null : _submit,
                    icon: _creatingAccount
                        ? Icons.person_add_rounded
                        : Icons.login_rounded,
                    label: busy ? '잠시만요' : (_creatingAccount ? '가입하기' : '로그인'),
                  ),
                  const SizedBox(height: 10),
                  // **Only while signing in.** Nobody creating an account has
                  // a password to recover, and on the screen where they are
                  // inventing one it is one more thing to read.
                  //
                  // It sends to whatever is in the address box rather than
                  // opening a dialog or a second screen: the field is already
                  // here, and a guardian who is locked out is not helped by
                  // being asked to type the same address somewhere else.
                  if (!_creatingAccount)
                    TextButton(
                      key: GuardianLoginKeys.forgot,
                      onPressed: busy
                          ? null
                          : () => ref
                                .read(guardianLoginControllerProvider.notifier)
                                .sendPasswordReset(email: _email.text),
                      child: const Text('비밀번호를 잊으셨나요?'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String? _messageFor(GuardianLoginState state) => switch (state) {
    GuardianLoginFailed(:final message) => message,
    GuardianLoginAwaitingConfirmation(:final email) =>
      '$email 으로 인증 메일을 보냈어요. 메일의 링크를 누른 뒤 로그인해 주세요.',
    // Said the same way for an address with no account, because the
    // alternative is a form that tells anyone which addresses are
    // registered.
    GuardianLoginResetSent(:final email) =>
      '$email 으로 메일을 보냈어요. 메일의 링크에서 새 비밀번호를 정해 주세요.',
    GuardianLoginNeedsEmail() => '가입하실 때 쓰신 이메일을 위에 적어 주세요.',
    _ => null,
  };
}

class _Message extends StatelessWidget {
  const _Message({super.key, required this.text, required this.isError});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final color = isError
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        // ignore: deprecated_member_use
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(text, style: TextStyle(color: color, height: 1.45)),
    );
  }
}

/// 가입하는 중이에요, then 가입이 완료됐어요 in the same place.
class _SignUpCard extends StatelessWidget {
  const _SignUpCard({required this.done});

  final ValueNotifier<bool> done;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        key: GuardianLoginKeys.progress,
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        child: SizedBox(
          width: 250,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 30, 24, 28),
            child: ValueListenableBuilder<bool>(
              valueListenable: done,
              builder: (context, finished, _) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 56,
                    height: 56,
                    child: finished
                        ? const DecoratedBox(
                            decoration: BoxDecoration(
                              color: AppColors.guardianTintGreen,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.check_rounded,
                              size: 34,
                              color: AppColors.guardianTintGreenInk,
                            ),
                          )
                        : const Padding(
                            padding: EdgeInsets.all(6),
                            child: CircularProgressIndicator(
                              strokeWidth: 5,
                              color: AppColors.guardianPrimary,
                              backgroundColor: AppColors.guardianTintBlue,
                            ),
                          ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    finished ? '가입이 완료됐어요' : '가입하는 중이에요',
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4,
                      color: AppColors.guardianInk,
                    ),
                  ),
                  if (finished) ...[
                    const SizedBox(height: 6),
                    const Text(
                      '잠시 뒤 다음 화면으로 넘어가요',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.guardianInkFaint,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
