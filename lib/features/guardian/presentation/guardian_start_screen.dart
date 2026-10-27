import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../../../data/remote/guardian_auth_repository.dart';
import '../../../core/theme/app_colors.dart';
import 'widgets/guardian_surfaces.dart';

/// Widget keys the tests drive.
class GuardianStartKeys {
  GuardianStartKeys._();

  static const back = Key('guardian-start-back');
  static const kakao = Key('guardian-start-kakao');
  static const google = Key('guardian-start-google');
  static const email = Key('guardian-start-email');
  static const emailFallback = Key('guardian-start-email-fallback');
}

/// Guardian entry. Argues for connecting before asking for an account.
///
/// Sign-up and sign-in are one action: with Kakao or Google the first tap
/// creates the account and later taps sign in, so a separate 회원가입 control
/// would ask a question the user cannot answer correctly.
class GuardianStartScreen extends StatelessWidget {
  const GuardianStartScreen({super.key});

  /// Three things this screen may say, and the test beside it is what keeps
  /// the list to three.
  ///
  /// 사진 is back, and that is the one claim here that changed because the
  /// app changed rather than because the copy did. The photo bucket exists,
  /// its policies are checked against the live project, and both ends can
  /// send one. 배터리 · 소리 · 인터넷 stay out: the readings are still a
  /// background sync that is an interface with no implementation.
  ///
  /// It promised 배터리 · 소리 · 인터넷 "한눈에" and 사진 for months, and the
  /// app does neither: the phone readings arrive with the Phase 6 background
  /// sync, which is an interface with no implementation, and sending a
  /// picture needs an image picker and file storage that do not exist. This
  /// is the first screen a guardian reads and the only one that makes
  /// promises, so it is the worst place in the app to make one that is not
  /// kept — the same reasoning that took the mocked 배터리 72% off the
  /// dashboard, one screen earlier.
  static const _benefits = <(IconData, Color, Color, String, String)>[
    (
      Icons.grid_view_rounded,
      AppColors.guardianTintBlue,
      AppColors.guardianTintBlueInk,
      '부모님을 대신해 필요한 앱을 관리해 드릴 수 있어요',
      '홈 화면 버튼의 이름과 색을 멀리서 정리합니다',
    ),
    (
      Icons.chat_bubble_rounded,
      AppColors.guardianTintViolet,
      AppColors.guardianTintVioletInk,
      '부모님과 큰 글씨로 메시지와 사진을 주고받을 수 있어요',
      '보내면 부모님 첫 화면에 바로 뜹니다',
    ),
    (
      Icons.schedule_rounded,
      AppColors.guardianTintGreen,
      AppColors.guardianTintGreenInk,
      '부모님 폰을 언제 쓰셨는지 알 수 있어요',
      '마지막으로 쓰신 시각이 보입니다',
    ),
  ];


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.guardianGroundEnd,
      body: GuardianGround(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: IconButton(
                  key: GuardianStartKeys.back,
                  onPressed: () => context.go(Routes.firstScreen),
                  icon: const Icon(Icons.chevron_left),
                  iconSize: 26,
                  color: AppColors.guardianInkSoft,
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(26, 0, 26, 34),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _Header(),
                      const SizedBox(height: 30),
                      for (var i = 0; i < _benefits.length; i++) ...[
                        if (i > 0) const SizedBox(height: 12),
                        _BenefitCard(
                          icon: _benefits[i].$1,
                          tint: _benefits[i].$2,
                          tintInk: _benefits[i].$3,
                          title: _benefits[i].$4,
                          subtitle: _benefits[i].$5,
                          order: i,
                        ),
                      ],
                      const SizedBox(height: 30),
                      const Divider(
                        height: 1,
                        thickness: 1,
                        color: AppColors.guardianRule,
                      ),
                      const SizedBox(height: 18),
                      // Kakao first: effectively every guardian in this age
                      // range has one, and Google more often stalls on
                      // "which account was mine".
                      _ProviderButton(
                        buttonKey: GuardianStartKeys.kakao,
                        provider: GuardianOAuthProvider.kakao,
                        label: '카카오로 시작하기',
                        background: AppColors.kakaoYellow,
                        foreground: AppColors.kakaoInk,
                        icon: Icons.chat_bubble,
                      ),
                      const SizedBox(height: 10),
                      _ProviderButton(
                        buttonKey: GuardianStartKeys.google,
                        provider: GuardianOAuthProvider.google,
                        label: '구글로 시작하기',
                        background: Colors.white,
                        foreground: AppColors.guardianInk,
                        icon: Icons.g_mobiledata,
                        borderColor: AppColors.guardianRule,
                      ),
                      const SizedBox(height: 10),
                      // **The third way in, and today the only one that
                      // finishes.** Kakao and Google both dead-end in a
                      // 준비 중 sheet because neither has an OAuth client on
                      // the project, so until one exists a guardian who
                      // presses either is told to come back to this.
                      //
                      // It is last all the same: it asks for a password to
                      // invent and remember, which the other two do not. Last
                      // is the right place for the most work, not for the
                      // least important thing.
                      //
                      // It wears the app's own blue rather than a brand's,
                      // because it belongs to no one else — and that also
                      // keeps it from reading as a second Google, which the
                      // white-and-bordered treatment would have.
                      _ProviderButton(
                        buttonKey: GuardianStartKeys.email,
                        label: '이메일로 시작하기',
                        background: AppColors.guardianTintBlue,
                        foreground: AppColors.guardianTintBlueInk,
                        icon: Icons.mail_rounded,
                        // Straight to the form. There is nothing to explain
                        // and nothing being prepared, so a sheet here would
                        // be a screen that exists only to be passed through.
                        destination: Routes.guardianLogin,
                      ),
                      const SizedBox(height: 22),
                      const Text(
                        '시작하면 서비스 이용약관과\n개인정보 처리방침에 동의하게 됩니다',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.7,
                          fontWeight: FontWeight.w400,
                          color: AppColors.guardianInkDisabled,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 5,
              height: 5,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.guardianPrimary,
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              '보호자 시작하기',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 2.2,
                color: AppColors.guardianInkFaint,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Text(
          '부모님께 이런 걸\n해드릴 수 있어요',
          style: TextStyle(
            fontSize: 29,
            height: 1.42,
            fontWeight: FontWeight.w700,
            letterSpacing: -1.4,
            color: AppColors.guardianInk,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          '연결은 몇 분이면 끝납니다.',
          style: TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w500,
            letterSpacing: -0.3,
            color: AppColors.guardianInkFaint,
          ),
        ),
      ],
    );
  }
}

/// One benefit, fading up from below so the eye is walked from 1 to 3.
class _BenefitCard extends StatefulWidget {
  const _BenefitCard({
    required this.icon,
    required this.tint,
    required this.tintInk,
    required this.title,
    required this.subtitle,
    required this.order,
  });

  /// A mark rather than a number. The three are not steps — nobody does them
  /// in order — and the numbered badges said they were.
  final IconData icon;
  final Color tint;
  final Color tintInk;

  final String title;
  final String subtitle;
  final int order;

  @override
  State<_BenefitCard> createState() => _BenefitCardState();
}

class _BenefitCardState extends State<_BenefitCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 550),
  );

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(
      Duration(milliseconds: 50 + widget.order * 70),
      () {
        if (mounted) _controller.forward();
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.12),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut)),
        child: GuardianCard(
          padding: const EdgeInsets.fromLTRB(16, 17, 18, 17),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: widget.tint,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(widget.icon, size: 21, color: widget.tintInk),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 16,
                        height: 1.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                        color: AppColors.guardianInk,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      widget.subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.55,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.2,
                        color: AppColors.guardianInkFaint,
                      ),
                    ),
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
      height: 56,
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
        onPressed: () => destination == null
            ? _start(context, ref, provider!, supabaseConfigured: configured)
            : context.go(destination!),
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
