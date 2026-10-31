import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../../../data/remote/guardian_auth_repository.dart';
import '../../../core/theme/app_colors.dart';
import 'widgets/guardian_surfaces.dart';
import 'widgets/signup_consent_sheet.dart';

/// Widget keys the tests drive.
class GuardianStartKeys {
  GuardianStartKeys._();

  static const back = Key('guardian-start-back');
  static const kakao = Key('guardian-start-kakao');
  static const google = Key('guardian-start-google');
  static const email = Key('guardian-start-email');
  static const emailFallback = Key('guardian-start-email-fallback');
  static const skip = Key('guardian-start-skip');
  static const next = Key('guardian-start-next');
  static const pages = Key('guardian-start-pages');
  static const picture = Key('guardian-start-picture');
}

/// Guardian entry: three pages saying what this is for, then the buttons.
///
/// **Shown every time a signed-out guardian arrives**, on the owner's call
/// (2026-10-31), with 건너뛰기 on the first two pages for somebody who has
/// read them before. A guardian who is signed in never sees it: `/` sends
/// them to the dashboard.
///
/// The buttons are on the last page, after the reasons to press them. A
/// guardian who leaves here leaves the product, so what the app does for
/// their parent comes before what it asks of them.
///
/// Sign-up and sign-in are one action on this page: with Kakao or Google the
/// first tap creates the account and later taps sign in, so a separate
/// 회원가입 control would ask a question the user cannot answer correctly.
///
/// **What the pages may say is held to what the app does.** It is the one
/// place that makes promises before an account exists, so a claim here that
/// is not kept is worse than one anywhere else - the same reasoning that took
/// the mocked 배터리 72% off the dashboard. The parent's internet state is
/// not something the guardian's phone can read, and the test beside this
/// file keeps the word off all three pages.
class GuardianStartScreen extends StatefulWidget {
  const GuardianStartScreen({super.key, this.initialPage = 0});

  /// 2 opens on the buttons: the email form's back arrow comes here, and
  /// sending somebody who has just chosen email back to page one would be
  /// making them read the pitch twice to change their mind.
  final int initialPage;

  static const lastPage = 2;

  @override
  State<GuardianStartScreen> createState() => _GuardianStartScreenState();
}

class _GuardianStartScreenState extends State<GuardianStartScreen> {
  late final PageController _pages = PageController(
    initialPage: widget.initialPage,
  );
  late int _page = widget.initialPage;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _goTo(int page) => _pages.animateToPage(
    page,
    duration: const Duration(milliseconds: 320),
    curve: Curves.easeOutCubic,
  );

  @override
  Widget build(BuildContext context) {
    final onLast = _page == GuardianStartScreen.lastPage;
    return Scaffold(
      backgroundColor: AppColors.guardianGroundEnd,
      body: GuardianGround(
        child: SafeArea(
          child: Column(
            children: [
              SizedBox(
                height: 48,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      IconButton(
                        key: GuardianStartKeys.back,
                        onPressed: () => _page == 0
                            ? context.go(Routes.firstScreen)
                            : _goTo(_page - 1),
                        icon: const Icon(Icons.chevron_left),
                        iconSize: 26,
                        color: AppColors.guardianInkSoft,
                      ),
                      const Spacer(),
                      if (!onLast)
                        TextButton(
                          key: GuardianStartKeys.skip,
                          onPressed: () => _goTo(GuardianStartScreen.lastPage),
                          child: const Text(
                            '건너뛰기',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.guardianInkSoft,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: PageView(
                  key: GuardianStartKeys.pages,
                  controller: _pages,
                  onPageChanged: (page) => setState(() => _page = page),
                  children: [
                    _IntroPage(
                      page: 0,
                      title: '스마트폰이 어려운 부모님,\n이제 걱정하지 마세요',
                      picture: 'assets/intro/senior_home.png',
                      cards: const [
                        _Point(
                          Icons.grid_view_rounded,
                          AppColors.guardianTintBlue,
                          AppColors.guardianTintBlueInk,
                          '큰 아이콘',
                          '눈이 어두운 부모님도 쉽게 확인할 수 있어요',
                        ),
                        _Point(
                          Icons.format_size_rounded,
                          AppColors.guardianTintViolet,
                          AppColors.guardianTintVioletInk,
                          '글씨 크기 4단계',
                          '제일 크게까지 키울 수 있어요',
                        ),
                        _Point(
                          Icons.record_voice_over_rounded,
                          AppColors.guardianTintGreen,
                          AppColors.guardianTintGreenInk,
                          '메시지 읽어 드리기',
                          '자녀가 보낸 글을 소리로 들려 드려요',
                        ),
                      ],
                      onNext: () => _goTo(1),
                    ),
                    _IntroPage(
                      page: 1,
                      title: '부모님의 런처 앱 화면을\n자녀(보호자)가 직접\n바꿔드릴 수 있어요',
                      picture: 'assets/intro/guardian_launcher.png',
                      cards: const [
                        _Point(
                          Icons.add_rounded,
                          AppColors.guardianTintBlue,
                          AppColors.guardianTintBlueInk,
                          '앱 추가',
                          '부모님이 자주 쓰시는 앱이 있다면, 앱 추가를 눌러 '
                              '부모님이 쉽게 추가하시도록 도와드릴 수 있어요',
                        ),
                        _Point(
                          Icons.palette_rounded,
                          AppColors.guardianTintViolet,
                          AppColors.guardianTintVioletInk,
                          '앱 버튼 색과 이름',
                          '부모님이 쉽게 보실 수 있는 색과 이름으로 '
                              '바꿔 드릴 수 있어요',
                        ),
                      ],
                      onNext: () => _goTo(2),
                    ),
                    const _LastPage(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One line on a page: a tinted mark, a name and what it does.
class _Point {
  const _Point(this.icon, this.tint, this.tintInk, this.title, this.detail);

  final IconData icon;
  final Color tint;
  final Color tintInk;
  final String title;
  final String detail;
}

class _IntroPage extends StatelessWidget {
  const _IntroPage({
    required this.page,
    required this.title,
    required this.picture,
    required this.cards,
    required this.onNext,
  });

  final int page;
  final String title;
  final String picture;
  final List<_Point> cards;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 30),
      child: Column(
        children: [
          Expanded(
            child: _Centred(
              child: Column(
                children: [
                  _Title(title),
                  const SizedBox(height: 26),
                  _Picture(asset: picture, width: 115),
                  const SizedBox(height: 26),
                  for (var i = 0; i < cards.length; i++) ...[
                    if (i > 0) const SizedBox(height: 14),
                    _PointCard(cards[i]),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          _Dots(current: page),
          const SizedBox(height: 18),
          GuardianPrimaryButton(
            key: GuardianStartKeys.next,
            label: '다음',
            icon: Icons.arrow_forward_rounded,
            onPressed: onNext,
          ),
        ],
      ),
    );
  }
}

class _LastPage extends StatelessWidget {
  const _LastPage();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      child: Column(
        children: [
          Expanded(
            child: _Centred(
              child: Column(
                children: [
                  const _Title('부모님의 안부가\n걱정되시나요?'),
                  const SizedBox(height: 18),
                  const _Picture(
                    asset: 'assets/intro/guardian_home.png',
                    width: 84,
                  ),
                  const SizedBox(height: 18),
                  // It dials, exactly as the 119 tile does: the senior
                  // presses call themselves, and nothing is sent to the
                  // guardian. The line says 전화, not 알림, for that reason.
                  const _PointCard(
                    _Point(
                      Icons.emergency_rounded,
                      AppColors.guardianTintAmber,
                      AppColors.guardianTintAmberInk,
                      '긴급 구조 요청',
                      '119, 112, 자녀에게 바로 전화해요',
                    ),
                  ),
                  const SizedBox(height: 10),
                  const _PointCard(
                    _Point(
                      Icons.favorite_rounded,
                      AppColors.guardianTintGreen,
                      AppColors.guardianTintGreenInk,
                      '마지막 폰 사용 시간',
                      '언제 부모님이 폰을 사용하셨는지 확인할 수 있어요',
                    ),
                  ),
                  const SizedBox(height: 10),
                  const _PointCard(
                    _Point(
                      Icons.chat_bubble_rounded,
                      AppColors.guardianTintViolet,
                      AppColors.guardianTintVioletInk,
                      '메시지',
                      '큰 글씨로 부모님도 쉽게 메시지를 보내실 수 있어요',
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Kakao first: effectively every guardian in this age
                  // range has one, and Google more often stalls on "which
                  // account was mine".
                  const _ProviderButton(
                    buttonKey: GuardianStartKeys.kakao,
                    provider: GuardianOAuthProvider.kakao,
                    label: '카카오로 시작하기',
                    background: AppColors.kakaoYellow,
                    foreground: AppColors.kakaoInk,
                    icon: Icons.chat_bubble,
                  ),
                  const SizedBox(height: 8),
                  const _ProviderButton(
                    buttonKey: GuardianStartKeys.google,
                    provider: GuardianOAuthProvider.google,
                    label: '구글로 시작하기',
                    background: Colors.white,
                    foreground: AppColors.guardianInk,
                    icon: Icons.g_mobiledata,
                    borderColor: AppColors.guardianRule,
                  ),
                  const SizedBox(height: 8),
                  // Last because it asks for a password to invent and
                  // remember, which the other two do not. It wears the app's
                  // own blue rather than a brand's, so it does not read as a
                  // second Google.
                  const _ProviderButton(
                    buttonKey: GuardianStartKeys.email,
                    label: '이메일로 시작하기',
                    background: AppColors.guardianTintBlue,
                    foreground: AppColors.guardianTintBlueInk,
                    icon: Icons.mail_rounded,
                    destination: Routes.guardianLogin,
                  ),
                  const SizedBox(height: 12),
                  // Says where agreeing happens rather than claiming it has:
                  // passing a screen is not an act of agreement.
                  const Text(
                    '버튼을 누르면 약관을 확인하고 동의하는 화면이 나옵니다',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.6,
                      color: AppColors.guardianInkDisabled,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const _Dots(current: GuardianStartScreen.lastPage),
        ],
      ),
    );
  }
}

/// Centred in the height it has, and scrolling only when it does not fit -
/// a short phone at a large system font size is still a phone this has to
/// work on, and the guardian's half may scroll.
class _Centred extends StatelessWidget {
  const _Centred({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontSize: 25,
        height: 1.36,
        fontWeight: FontWeight.w700,
        letterSpacing: -1,
        color: AppColors.guardianInk,
      ),
    );
  }
}

/// A screen of this app, in a phone's frame.
///
/// **Captures of the real screens**, from `screenshots_test.dart`, cut to the
/// top half and shrunk to 300x600 - `assets/intro/`. A drawing would have to
/// be kept in step with the screens by hand; a capture is regenerated.
class _Picture extends StatelessWidget {
  const _Picture({required this.asset, required this.width});

  final String asset;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: GuardianStartKeys.picture,
      width: width,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.guardianInk,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: AppColors.guardianCardShadow,
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: AspectRatio(
          aspectRatio: 1 / 2,
          child: Image.asset(asset, fit: BoxFit.cover),
        ),
      ),
    );
  }
}

class _PointCard extends StatelessWidget {
  const _PointCard(this.point);

  final _Point point;

  @override
  Widget build(BuildContext context) {
    return GuardianCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: point.tint,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(point.icon, size: 20, color: point.tintInk),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  point.title,
                  style: const TextStyle(
                    fontSize: 15.5,
                    height: 1.4,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                    color: AppColors.guardianInk,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  point.detail,
                  style: const TextStyle(
                    fontSize: 13.5,
                    height: 1.5,
                    letterSpacing: -0.2,
                    color: AppColors.guardianInkFaint,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.current});

  final int current;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i <= GuardianStartScreen.lastPage; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: i == current ? 22 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: i == current
                  ? AppColors.guardianPrimary
                  : AppColors.guardianRule,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
      ],
    );
  }
}

/// What a provider button does once a Supabase project is attached.
///
/// It **asks the project** and reports the answer. The previous version
/// opened a sheet whose text was written here — `카카오 로그인은 준비 중이에요`
/// — on the standing assumption that no OAuth client existed. That sentence
/// would have gone on claiming so for as long as nobody remembered to delete
/// it, including the day after Kakao started working. Nothing on a screen
/// should assert a server fact it never asked about.
///
/// With no project attached the Phase 3 behaviour stands and the button opens
/// the dashboard, which is what keeps a keyless build navigable.
Future<void> _start(
  BuildContext context,
  WidgetRef ref,
  GuardianOAuthProvider provider, {
  required bool supabaseConfigured,
}) async {
  if (!supabaseConfigured) {
    context.go(Routes.guardianDashboard);
    return;
  }

  try {
    await ref.read(guardianAuthRepositoryProvider).signInWithOAuth(provider);
    // The browser has it now. **Nothing happens here on success** — the
    // session arrives through the deep link, and moving the screen on would
    // claim a sign-in that has not happened.
    return;
  } on GuardianAuthException catch (e) {
    if (!context.mounted) return;
    await _offerEmail(context, '${provider.label} 로그인은 ${e.message}');
  } on Object {
    if (!context.mounted) return;
    await _offerEmail(context, '${provider.label} 로그인을 열지 못했어요.');
  }
}

/// Says why, and offers the one route that is known to work.
Future<void> _offerEmail(BuildContext context, String reason) async {
  final useEmail = await showModalBottomSheet<bool>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              reason,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.guardianInk,
              ),
            ),
            const SizedBox(height: 22),
            FilledButton(
              key: GuardianStartKeys.emailFallback,
              onPressed: () => Navigator.of(sheetContext).pop(true),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
              child: const Text('이메일로 계속하기'),
            ),
          ],
        ),
      ),
    ),
  );
  if (useEmail == true && context.mounted) context.go(Routes.guardianLogin);
}

class _ProviderButton extends ConsumerWidget {
  const _ProviderButton({
    required this.buttonKey,
    required this.label,
    required this.background,
    required this.foreground,
    required this.icon,
    this.borderColor,
    this.destination,
    this.provider,
  });

  final Key buttonKey;
  final String label;
  final Color background;
  final Color foreground;
  final IconData icon;
  final Color? borderColor;

  /// Where this button goes directly, for a way in that needs no OAuth
  /// client and so has nothing to apologise for. Null means the provider
  /// route, and then [provider] says which one.
  final String? destination;

  /// Which provider to ask. Null for the email button, which asks nobody.
  final GuardianOAuthProvider? provider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configured = ref.watch(supabaseConfigProvider).isConfigured;
    return SizedBox(
      height: 50,
      width: double.infinity,
      child: FilledButton(
        key: buttonKey,
        style: FilledButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: borderColor == null
                ? BorderSide.none
                : BorderSide(color: borderColor!, width: 1.4),
          ),
        ),
        // **Every way in goes through the sheet first**, including the two
        // that dead-end in 준비 중 today. A consent asked after the provider
        // screen is a consent asked after the account exists, and one asked
        // only on the email route would be missing from the two a guardian
        // is most likely to press.
        onPressed: () async {
          if (!await SignupConsentSheet.ensure(context, ref)) return;
          if (!context.mounted) return;
          if (destination == null) {
            await _start(
              context,
              ref,
              provider!,
              supabaseConfigured: configured,
            );
          } else {
            context.go(destination!);
          }
        },
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: foreground),
            const SizedBox(width: 9),
            Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
                color: foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
