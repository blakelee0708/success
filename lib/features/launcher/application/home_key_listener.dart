import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../../notices/application/notice_providers.dart';
import '../../family/application/senior_pairing_controller.dart';
import '../../guardian/application/guardian_pairing_controller.dart';
import '../../guardian/application/guardian_session_controller.dart';
import '../../family/presentation/link_consent_prompt.dart';
import '../data/app_launcher.dart';
import 'senior_presence_reporter.dart';
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
  const HomeKeyListener({super.key, required this.router, required this.child});

  final GoRouter router;
  final Widget child;

  /// How often the parent's phone re-reads what their family arranged.
  ///
  /// **Start-up and resume were not enough, and the gap was the whole
  /// promise.** 홈 화면 tells the guardian 바꾸면 부모님 폰에 반영됩니다, and
  /// a launcher is the screen a phone *sits* on: a parent looking straight at
  /// their home screen is in neither of those moments, so a colour their
  /// child changed while they watched never arrived at all. They had to lock
  /// the phone and wake it again, which nobody would guess.
  ///
  /// Fifteen seconds is the answer to 얼마나 기다려야 하나. It is one small
  /// read, and it only runs while the app is in the foreground - the screen
  /// going off takes the app out of `resumed`, so a phone in a pocket asks
  /// nothing.
  static const refreshEvery = Duration(seconds: 15);

  @override
  ConsumerState<HomeKeyListener> createState() => _HomeKeyListenerState();
}

class _HomeKeyListenerState extends ConsumerState<HomeKeyListener>
    with WidgetsBindingObserver {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    MethodChannelAppLauncher.channel.setMethodCallHandler(_onCall);
    WidgetsBinding.instance.addObserver(this);
    _startTicking();
    // The first report of the run. Not awaited and not shown: see [_report].
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _report();
    });
  }

  /// 안부 신호. Deliberately fire-and-forget — the guardian's dashboard is
  /// told the phone is in use, and the senior's own launcher waits for
  /// nothing while that happens.
  void _report() {
    if (!mounted) return;
    ref.read(seniorPresenceReporterProvider).report();
  }

  /// The periodic read. Cancelled and restarted rather than left running, so
  /// a resume never leaves two timers behind.
  void _startTicking() {
    _tick?.cancel();
    _tick = Timer.periodic(HomeKeyListener.refreshEvery, (_) {
      if (!mounted) return;
      ref.read(seniorSettingsControllerProvider.notifier).refresh();
      _refreshFamily();
      _refreshGuardian();
    });
  }

  /// Who is attached to this phone, and whether anybody is waiting to be.
  ///
  /// **Nothing else re-asks either question.** 가족 연결 동의 is answered on
  /// this phone and *asked* from another one: the senior presses 번호
  /// 보여주기 and puts the phone down, and their child types the number a
  /// minute later. Read once at launch, the card would never be drawn at all
  /// on the path it exists for - a launcher runs for weeks between restarts.
  ///
  /// Both providers guard on this phone having a profile before they reach
  /// the network, which is what makes this safe to run from here: this widget
  /// wraps the whole router, so it is on the guardian's phone too.
  void _refreshFamily() {
    ref.invalidate(pendingGuardianLinkProvider);
    ref.invalidate(seniorGuardiansProvider);
    // Only while the phone shows no family, which is exactly what a phone
    // that was moved onto another profile shows - so a connected phone asks
    // nothing extra every fifteen seconds.
    if ((ref.read(seniorGuardiansProvider).value ?? const []).isEmpty) {
      unawaited(
        ref
            .read(seniorPairingControllerProvider.notifier)
            .followMovedPhone()
            .catchError((Object _) {}),
      );
    }
  }

  /// The guardian's half of the same question, on resume **and** on the tick.
  ///
  /// Their dashboard is built from cached `FutureProvider`s, and a Riverpod
  /// container lives as long as the process - so a parent who cut the link
  /// left their child looking at a screen that still named them until the
  /// app was killed, with the notice explaining it sitting unread behind the
  /// same cache.
  ///
  /// **Resume alone was tried first and was not enough**, found on two real
  /// phones: the parent pressed 끊기 while their child had the dashboard
  /// open, and the child's screen went on saying 연결됨 while every message
  /// they typed was refused. Somebody watching the screen is exactly the
  /// person resume never reaches. Fifteen seconds is the same answer the
  /// parent's phone already gets, and it costs three small reads while the
  /// app is in front of them and none while it is not.
  ///
  /// Each of the three answers empty without a guardian session, and none is
  /// watched by anything on the parent's phone, which is what makes this safe
  /// here: this widget wraps the whole router, so it runs there too.
  void _refreshGuardian() {
    ref.invalidate(linkedSeniorProfilesProvider);
    ref.invalidate(pendingSeniorLinksProvider);
    ref.invalidate(guardianNoticesProvider);
  }

  @override
  void dispose() {
    _tick?.cancel();
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
    if (state != AppLifecycleState.resumed) {
      // Nothing is worth reading while nobody is looking, and the screen
      // going off is what takes the app out of `resumed`.
      _tick?.cancel();
      _tick = null;
      return;
    }
    _startTicking();
    ref.read(seniorSettingsControllerProvider.notifier).refresh();
    _refreshFamily();
    _refreshGuardian();
    // 공지 and the guardian's 새 버전, on resume only. They change once in a
    // while and on the company's schedule, so the fifteen-second tick would
    // be a read every time for nothing.
    ref.invalidate(runningNoticesProvider);
    ref.invalidate(appConfigProvider);
    // The commoner half of 안부 신호 by far. A launcher may go weeks without
    // being restarted, so start-up alone would report once and then go quiet
    // while the parent used the phone every day.
    _report();
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
