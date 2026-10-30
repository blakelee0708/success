import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/clock.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../../../core/format/korean_clock.dart';
import '../../../core/app_version.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/family_message.dart';
import '../../../domain/senior_readings.dart';
import '../../../domain/senior_settings.dart';
import '../application/device_status_lines.dart';
import '../application/senior_presence.dart';
import '../application/guardian_home_apps_controller.dart';
import '../application/guardian_push_registrar.dart';
import '../application/guardian_pairing_controller.dart';
import '../application/guardian_session_controller.dart';
import '../../care/application/care_controller.dart';
import '../../care/presentation/guardian_care_tab.dart';
import '../../messages/application/unread_notice.dart';
import '../../messages/application/message_controller.dart';
import '../../messages/presentation/guardian_message_tab.dart';
import '../../notices/presentation/guardian_service_notices.dart';
import 'guardian_family_tab.dart';
import 'guardian_name_screen.dart';
import 'guardian_launcher_tab.dart';
import 'widgets/guardian_hero_card.dart';
import 'widgets/guardian_nav_bar.dart';
import 'widgets/guardian_surfaces.dart';

/// 보호자 대시보드. Navigable without a backend — everything shown here is
/// either local settings or mock data until Phase 4 wires Supabase.
///
/// Where the uploaded design and the project docs disagreed, the docs won:
/// 약 알림 and 복약 기록 are listed under Out Of MVP, call-content analysis is
/// excluded outright, `06_PERMISSION_AND_POLICY` forbids describing location
/// as real-time tracking, and inviting other guardians is a free feature
/// rather than part of 안심 케어.
class GuardianDashboardScreen extends ConsumerStatefulWidget {
  const GuardianDashboardScreen({super.key});

  @override
  ConsumerState<GuardianDashboardScreen> createState() =>
      _GuardianDashboardScreenState();
}

class _GuardianDashboardScreenState
    extends ConsumerState<GuardianDashboardScreen> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    // Where this phone can be reached, so a message from their parent arrives
    // as a notification rather than as a number on a tab they have to open
    // first. Started, never awaited - see `GuardianPushRegistrar`.
    ref.read(guardianPushRegistrarProvider).start();
  }

  @override
  Widget build(BuildContext context) {
    // The app runs on the senior theme by default; the guardian side is a
    // different persona on a different phone — 04_SCREEN_SPEC gives it a
    // white background and a blue accent rather than the warm launcher palette.
    return Theme(data: AppTheme.guardian, child: _build(context));
  }

  Widget _build(BuildContext context) {
    // **Asked once, before anything else, and there is no way past it.**
    // `guardian_accounts.display_name` was null for every guardian in the
    // system because nothing ever wrote it, and four screens fell back to the
    // literal word 보호자 - including the card a senior answers on their own
    // phone. A family with two children cannot be asked to agree to
    // they-do-not-know-who.
    //
    // Null from the provider is a guardian with no signal rather than one
    // with no name, so it leaves the dashboard alone.
    final account = ref.watch(guardianAccountProvider).value;
    if (account != null && (account.displayName ?? '').trim().isEmpty) {
      return GuardianNameScreen(
        suggestion: ref.watch(guardianSessionProvider).value?.providerName,
      );
    }

    return Scaffold(
      // The ground is a gradient, so it belongs to the body rather than to
      // `backgroundColor`, and every tab sits on the same one.
      backgroundColor: AppColors.guardianGroundEnd,
      body: GuardianGround(
        child: SafeArea(
          bottom: false,
          child: IndexedStack(
            index: _index,
            children: [
              _HomeTab(onOpenTab: (i) => setState(() => _index = i)),
              GuardianLauncherTab(onOpenTab: (i) => setState(() => _index = i)),
              GuardianMessageTab(onOpenTab: (i) => setState(() => _index = i)),
              const GuardianCareTab(),
            ],
          ),
        ),
      ),
      bottomNavigationBar: GuardianNavBar(
        selectedIndex: _index,
        onSelected: (i) => setState(() => _index = i),
        destinations: [
          GuardianDestination(
            label: '홈',
            icon: Icons.home_outlined,
            activeIcon: Icons.home_rounded,
          ),
          GuardianDestination(
            label: '부모님 화면',
            icon: Icons.grid_view_outlined,
            activeIcon: Icons.grid_view_rounded,
          ),
          GuardianDestination(
            label: '메시지',
            icon: Icons.chat_bubble_outline,
            activeIcon: Icons.chat_bubble_rounded,
            // The guardian gets a count, not a card. They are an adult with
            // an ordinary phone and this is one app on it, so a card that
            // could only appear once they had already opened the app would
            // be both late and redundant. What reaches them when it matters
            // is a push notification, which is not built yet.
            badge: ref.watch(unreadFromSeniorProvider),
          ),
          GuardianDestination(
            label: '안심 케어',
            icon: Icons.favorite_outline,
            activeIcon: Icons.favorite_rounded,
          ),
        ],
      ),
    );
  }
}

/// The page every tab draws into: one headline, then its content.
class _TabScaffold extends StatelessWidget {
  const _TabScaffold({required this.title, this.lede, required this.children});

  final String title;
  final String? lede;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    // Same 26px crown and same 22px gap as 홈 화면, which draws its heading
    // inside its own list. Every tab of this half starts at the same height.
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, GuardianHeading.crown, 20, 28),
      children: [
        GuardianHeading(title: title, lede: lede),
        const SizedBox(height: GuardianHeading.gap),
        ...children,
      ],
    );
  }
}

/// Asks again while the guardian is looking at 기다리고 있어요.
///
/// **Nothing else would tell them.** The answer is pressed on their parent's
/// phone, so no action of theirs produces it, and this half of the app has no
/// equivalent of the launcher's check-in to ride on. Without this the card
/// stays up until the app is relaunched - on the one screen whose whole
/// content is 허락하시면 바로 이어집니다.
///
/// It is scoped to the waiting state rather than put on the dashboard: the
/// widget goes away the moment the parent agrees, and with it the timer, so
/// a connected guardian polls nothing.
class _ConsentWatcher extends ConsumerStatefulWidget {
  const _ConsentWatcher({required this.child});

  final Widget child;

  static const every = Duration(seconds: 5);

  @override
  ConsumerState<_ConsentWatcher> createState() => _ConsentWatcherState();
}

class _ConsentWatcherState extends ConsumerState<_ConsentWatcher> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(_ConsentWatcher.every, (_) {
      if (!mounted) return;
      ref.invalidate(pendingSeniorLinksProvider);
      ref.invalidate(linkedSeniorProfilesProvider);
      ref.invalidate(waitingInviteProvider);
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _Card extends StatelessWidget {
  const _Card({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GuardianCard(child: child),
    );
  }
}

/// 홈 — the parent's phone at a glance.
///
/// Only what the server actually knows. Battery, ringer volume and network
/// were mocked here through Phase 3; they arrive with the 5-minute background
/// sync in Phase 6, and a plausible-looking 배터리 72% on a dashboard whose
/// whole job is to reassure would be worse than an empty state that says so.
/// The hero card follows the same rule — see [GuardianHeroCard].
class _HomeTab extends ConsumerWidget {
  const _HomeTab({required this.onOpenTab});

  /// The action cards move between tabs of this same dashboard, so they ask
  /// the shell to switch rather than pushing a route over it.
  final ValueChanged<int> onOpenTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profiles = ref.watch(linkedSeniorProfilesProvider);
    final profile = ref.watch(selectedSeniorProfileProvider);
    final careOn =
        ref.watch(careStateProvider).value?.stage == CareStage.active;

    // The first read only. The list is re-read every fifteen seconds now, and
    // a refresh keeps the last answer while it runs - a spinner on each one
    // would blank the dashboard four times a minute.
    if (profiles.isLoading && !profiles.hasValue) {
      return const Center(child: CircularProgressIndicator());
    }
    if (profile == null) {
      // **Waiting is not the same as nothing.** On the install-SMS path the
      // guardian creates the profile and their parent's phone has not even
      // connected; on 경로 B they typed the number and the card is on their
      // mother's screen. Saying 아직 연결된 부모님이 없어요 to either reads as
      // the connection having failed, and the first thing they would do is
      // do it again.
      final waiting = ref.watch(pendingSeniorLinksProvider).value ?? const [];
      if (waiting.isNotEmpty) {
        final request = waiting.first;
        final who = request.seniorName;
        final named = who == null || who.isEmpty ? '부모님' : '$who님';
        // **An unused install invite means the parent has not installed
        // yet**, so nothing is on their screen to answer - and saying 화면이
        // 떠 있어요 to that guardian sent them to ask their mother about a
        // card she could not see. The server's copy first, so the number is
        // still here tomorrow; the one just issued while that read is in
        // flight, so it does not flicker away the moment it is made.
        final open = ref.watch(waitingInviteProvider);
        final issued = ref.watch(lastInviteProvider);
        final invite = open.hasValue ? open.value : issued?.link;
        final phone = issued?.link.id == invite?.id
            ? issued?.phoneNumber
            : null;
        // **The number ran out and nobody installed.** No phone has ever
        // attached and the server holds no live number. This used to fall
        // through to 여쭤보는 화면이 떠 있어요, and under 1대1 the waiting
        // request held the guardian's one seat, so they could not start again
        // either - the only way out was 계정 삭제. Decided only once the read
        // has answered, so a page opened before it does not flash this.
        final expired =
            !request.hasPhone &&
            open.hasValue &&
            open.value == null &&
            issued == null;
        final title = expired
            ? '설치 번호가 만료됐어요'
            : invite == null
            ? '부모님 동의를 기다리고 있어요'
            : '부모님 폰에 앱을 설치해 주세요';
        final heading = expired
            ? '$named 폰에 아직 앱이 설치되지 않았어요'
            : invite == null
            ? '$named 폰에 여쭤봤어요'
            : '${who == null || who.isEmpty ? '부모님' : who}께 '
                  '${(ref.watch(appConfigProvider).value?.storeListed ?? false) ? '문자 두 개를' : '연결 번호 문자를'} 보내 주세요';
        final detail = expired
            ? '보내신 번호는 14일이 지나 더 이상 쓸 수 없어요. '
                  '새 번호를 만들어 다시 보내 주세요.'
            : invite == null
            ? '부모님 폰에 연결해도 되는지 여쭤보는 화면이 떠 있어요. '
                  '허락하시면 바로 이어집니다.'
            : '설치하고 번호를 넣으시면, 부모님 폰에 연결해도 되는지 '
                  '여쭤보는 화면이 떠요. 허락하시면 바로 이어집니다.';
        return _TabScaffold(
          title: title,
          children: [
            const GuardianServiceNotices(),
            _ConsentWatcher(
              child: _Card(
                key: GuardianHomeKeys.waitingForConsent,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      heading,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.4,
                        color: AppColors.guardianInk,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      detail,
                      style: const TextStyle(
                        fontSize: 14.5,
                        height: 1.55,
                        color: AppColors.guardianInkSoft,
                      ),
                    ),
                    if (invite != null && !expired) ...[
                      const SizedBox(height: 16),
                      GuardianInviteSender(link: invite, phoneNumber: phone),
                    ],
                    _WaitingActions(
                      seniorProfileId: request.seniorProfileId,
                      seniorName: who,
                      expired: expired,
                    ),
                  ],
                ),
              ),
            ),
            // **The account is still theirs while they wait.** This branch
            // used to end at the card, so 로그아웃 and 계정 삭제 were nowhere
            // on the screen for somebody whose parent had not answered yet -
            // found on a real phone. No notices here: the one notice there is
            // says to type a number below, and there is no form below.
            const GuardianFamilySection(title: '내 계정', notices: false),
          ],
        );
      }

      // **The thing to do sits under the sentence saying it has not been
      // done.** This card used to read 가족 탭에서 부모님을 추가하면, which
      // is an instruction to go and find a tab - on the first screen a new
      // guardian sees, about the one thing the app cannot work without.
      //
      // **And it says what connecting is for.** On a real phone this page
      // was one sentence saying nobody was connected and a form, which tells
      // a new guardian what is missing and nothing about why they would
      // want it. The three lines are what the app does once a parent is
      // there, and nothing in them is a promise the app does not keep.
      //
      // Order is the point: why they lost a connection first, then what
      // connecting gives them, then the form, then their own account.
      return const _TabScaffold(
        title: '부모님 연결하기',
        children: [
          GuardianServiceNotices(),
          GuardianNotices(),
          _Card(
            key: GuardianHomeKeys.noParent,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '아직 연결된 부모님이 없어요',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                    color: AppColors.guardianInk,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  '연결하면 이렇게 도와드릴 수 있어요.',
                  style: TextStyle(
                    fontSize: 14.5,
                    height: 1.55,
                    color: AppColors.guardianInkSoft,
                  ),
                ),
                SizedBox(height: 14),
                _Promise(
                  key: GuardianHomeKeys.promise,
                  icon: Icons.grid_view_rounded,
                  tint: AppColors.guardianTintBlue,
                  ink: AppColors.guardianTintBlueInk,
                  title: '부모님 첫 화면을 여기서 정리해 드려요',
                  detail: '버튼 이름과 색, 앱을 바꿔 드려요',
                ),
                _Promise(
                  icon: Icons.chat_bubble_rounded,
                  tint: AppColors.guardianTintViolet,
                  ink: AppColors.guardianTintVioletInk,
                  title: '메시지가 부모님 폰에 크게 떠요',
                  detail: '글씨가 안 보이시면 소리로 읽어 드립니다',
                ),
                _Promise(
                  icon: Icons.schedule_rounded,
                  tint: AppColors.guardianTintGreen,
                  ink: AppColors.guardianTintGreenInk,
                  title: '폰 쓰신 때와 배터리가 보여요',
                  detail: '첫 1주일 무료, 그다음은 안심 케어',
                ),
              ],
            ),
          ),
          GuardianConnectParentCard(heading: false),
          // **The same block, because a guardian with no parent still has an
          // account.** Without it 로그아웃, 내 전화번호, 개인정보처리방침 and
          // 계정 삭제 were all unreachable for exactly the person most likely
          // to want the last one: somebody who signed up, connected nobody,
          // and changed their mind. It draws no second connect form - every
          // part of it that needs a parent is guarded on having one.
          GuardianFamilySection(title: '내 계정', notices: false),
        ],
      );
    }

    final device = ref.watch(selectedSeniorDeviceProvider).value;
    final quota = ref.watch(messageQuotaProvider).value;
    final apps = ref.watch(guardianHomeAppsProvider).value ?? const [];
    final messages = ref.watch(conversationProvider).value ?? const [];
    final now = ref.watch(nowProvider)();
    final phone = device?.deviceLabel ?? device?.platform;
    // Every line about the parent's phone comes from here, so the card cannot
    // speak in the present tense about a check-in from three days ago — which
    // is what `폰은 잘 켜져 있어요` did for as long as `last_seen_at` was
    // written only at registration.
    // Read through the gate rather than off the device row. 안부 신호 and the
    // battery are what 안심 케어 sells; which handset is connected is 연결
    // 관리 and stays free, which is why `device` is still here for the name.
    final readings =
        ref.watch(seniorReadingsProvider).value ?? SeniorReadings.none;
    final locked = !readings.visible;
    final presence = SeniorPresence.from(
      lastSeen: readings.lastSeenAt,
      now: now,
    );
    final status = DeviceStatusLines.from(status: readings.status, now: now);

    return _TabScaffold(
      title: profile.displayName,
      // Withheld, the subtitle must not go on describing a phone it is not
      // being told about - `아직 / 연결되기 전이에요` would be the card
      // claiming the parent never set theirs up.
      lede: locked ? '안심 케어를 시작하시면 부모님 폰 상태를 알려 드려요.' : presence.lede,
      children: [
        const GuardianServiceNotices(),
        GuardianHeroCard(
          key: GuardianHomeKeys.hero,
          subject: phone == null
              ? profile.displayName
              : '${profile.displayName} · $phone',
          // The dot claims *now*, so it is lit for nothing else - and
          // withheld, there is nothing to claim.
          online: !locked && presence.online,
          headline: locked ? '안심 케어로 볼 수 있어요' : presence.headline,
          caption: locked ? '부모님이 폰을 쓰신 때, 배터리와 소리를 알려 드립니다.' : presence.caption,
          metric: quota == null || quota.unlimited
              ? '무제한'
              : '${quota.textLeft}번',
          metricCaption: '메시지 남음',
        ),
        // The week has to be visible while it is running. A free trial that
        // simply stops on the eighth day reads as the app breaking, and the
        // guardian never connects the two - they were never told there was a
        // week. Said only when nobody has subscribed, because `visible` is
        // true for both and one of them is about to end.
        if (!careOn && readings.trialRunningAt(now))
          Padding(
            key: GuardianHomeKeys.trial,
            padding: const EdgeInsets.only(top: 12),
            child: _TrialLine(daysLeft: readings.trialDaysLeftAt(now)),
          ),
        const SizedBox(height: 26),
        const Text(
          '무엇을 해 드릴까요',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            color: AppColors.guardianInk,
          ),
        ),
        const SizedBox(height: 12),
        // **Three things, not four, since the app went 1대1.** 가족 초대하기
        // held the fourth square and there is nobody to invite now, so the
        // grid is two squares and one wide card rather than a 2x2 with a
        // hole in it - the same reason a fifth card was refused when 소리
        // 울리기 was taken out.
        //
        // The wide one is 안심 케어, which is the only one of the three that
        // is selling something and the one that gains from the room.
        GridView.count(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          // Sized to the content rather than to a square-ish guess. At 0.98
          // every card carried about 40px of nothing under its caption, and
          // the 설정 card below the grid was pushed off the fold by it.
          childAspectRatio: 1.08,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            GuardianActionCard(
              label: '홈 버튼\n정리하기',
              detail: '버튼 ${apps.length}개',
              icon: Icons.grid_view_rounded,
              tint: AppColors.guardianTintBlue,
              tintInk: AppColors.guardianTintBlueInk,
              onTap: () => onOpenTab(1),
            ),
            GuardianActionCard(
              label: '메시지\n보내기',
              detail: _lastWord(messages, now),
              icon: Icons.chat_bubble_rounded,
              tint: AppColors.guardianTintViolet,
              tintInk: AppColors.guardianTintVioletInk,
              onTap: () => onOpenTab(2),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // **소리 울리기 held a slot here once the tier was bought**, so the
        // card that sold 안심 케어 turned into the thing it sold. With the
        // ring out of the product it goes back to one card, shown whether or
        // not they have paid: a buyer reading 알아보기 about something they
        // already have is better than a grid with a hole in it.
        //
        // Wide rather than square because it is the odd one out of three
        // now, and because it is the only one selling anything.
        GuardianActionCard(
          key: GuardianHomeKeys.care,
          wide: true,
          label: '안심 케어 알아보기',
          detail: '부모님이 어떻게 지내시는지',
          icon: Icons.favorite_rounded,
          tint: AppColors.guardianTintGreen,
          tintInk: AppColors.guardianTintGreenInk,
          onTap: () => onOpenTab(3),
        ),
        const SizedBox(height: 22),
        GuardianCard(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 10),
          child: Column(
            children: [
              GuardianFact(
                label: '화면',
                first: true,
                value: switch (profile.screenMode) {
                  ScreenMode.easy => '정말 쉬운 화면',
                  ScreenMode.detailed => '자세한 화면',
                  null => '아직 고르지 않으셨어요',
                },
              ),
              GuardianFact(
                label: '글씨 크기',
                value: switch (profile.fontSize) {
                  FontSize.normal => '보통',
                  FontSize.large => '크게',
                  FontSize.extraLarge => '아주 크게',
                  FontSize.largest => '제일 크게',
                  null => '아직 고르지 않으셨어요',
                },
              ),
              // 준비 중 was the honest answer while nothing read the phone.
              // It stops being the honest answer the moment something does.
              //
              // 인터넷 is gone from the row rather than kept as a third
              // 준비 중: reporting it would mean ACCESS_NETWORK_STATE for a
              // fact the check-in already proves.
              if (locked)
                GuardianFact(
                  key: GuardianHomeKeys.lockedStatus,
                  label: '배터리 · 소리',
                  value: '안심 케어',
                )
              else if (!status.hasReading)
                GuardianFact(label: '배터리 · 소리', value: status.battery)
              else ...[
                GuardianFact(
                  label: '배터리',
                  value: status.battery,
                  warn: status.isBatteryLow,
                ),
                GuardianFact(label: '소리', value: status.ringer),
                GuardianFact(label: '읽은 때', value: status.age),
              ],
              // **Only when the parent's phone is behind this one.** Play
              // installs an update while the app is not the one in front of
              // the user, and this app is the home screen - so a launcher is
              // the app least likely to update itself, and the senior is the
              // last person who should be asked to fix that.
              //
              // Nothing is said when the phone has not reported a version,
              // or when the two agree: a row that is always there is
              // furniture, and 말할 수 없음 is not 오래됐어요.
              if (_isBehind(device?.appVersion))
                GuardianFact(
                  key: GuardianHomeKeys.appOutOfDate,
                  label: '부모님 폰 앱',
                  value: '오래됐어요',
                  warn: true,
                ),
            ],
          ),
        ),
        // **연결 관리 is here now, not on 안심 케어.** Nothing in it is about
        // the paid tier, and a guardian who has not bought it has no reason
        // to open that tab - which left leaving,
        // reconnecting a phone and signing out with no route at all. 홈
        // already shows 부모님 연결하기 when there is none, so everything
        // about a connection is on one tab.
        // Keyed: an unkeyed child in a list is matched by position, and a
        // card appearing above this block once threw its form's State away
        // mid-submit.
        const GuardianFamilySection(key: ValueKey('family-section')),
      ],
    );
  }

  /// Whether the parent's phone is running an older build than this one.
  ///
  /// Build numbers, not version names: a name is marketing and can go
  /// sideways, a build number only goes up. Anything unreadable on either
  /// side answers false - a phone that did not say is never reported old.
  static bool _isBehind(String? theirs) {
    final parent = buildNumberOf(theirs);
    final mine = buildNumberOf(appVersion);
    if (parent == null || mine == null) return false;
    return parent < mine;
  }

  /// How long the conversation has been quiet, which is the only thing about
  /// 메시지 worth putting on a card that is read at a glance.
  static String _lastWord(List<FamilyMessage> messages, DateTime now) {
    if (messages.isEmpty) return '아직 대화가 없어요';
    return '마지막 대화 ${koreanDaysAgo(messages.last.sentAt, now)}';
  }
}

/// Widget keys the tests drive.
class GuardianHomeKeys {
  GuardianHomeKeys._();

  static const noParent = Key('guardian-home-no-parent');
  static const hero = Key('guardian-home-hero');
  static const lockedStatus = Key('guardian-home-locked-status');
  static const trial = Key('guardian-home-trial');
  static const care = Key('guardian-home-care');
  static const ring = Key('guardian-home-ring');
  static const appOutOfDate = Key('guardian-home-app-out-of-date');
  static const waitingForConsent = Key('guardian-home-waiting-consent');
  static const reissueInvite = Key('guardian-home-reissue-invite');
  static const withdrawRequest = Key('guardian-home-withdraw-request');
  static const withdrawConfirm = Key('guardian-home-withdraw-confirm');
  static const promise = Key('guardian-home-promise');
}

/// 번호 다시 만들기 and 연결 요청 취소, under the waiting card.
///
/// **The way out of a request the parent has not answered.** Under 1대1 the
/// request holds the guardian's one seat, so before these a wrong name, a
/// change of mind or an install number that ran out could only be undone by
/// 계정 삭제.
///
/// 취소 is a text button rather than a filled one, for the reason 로그아웃 is:
/// nobody opens the app in order to do it. 번호 다시 만들기 is filled because
/// on an expired request it is the only thing left to do.
class _WaitingActions extends ConsumerStatefulWidget {
  const _WaitingActions({
    required this.seniorProfileId,
    required this.seniorName,
    required this.expired,
  });

  final String seniorProfileId;
  final String? seniorName;
  final bool expired;

  @override
  ConsumerState<_WaitingActions> createState() => _WaitingActionsState();
}

class _WaitingActionsState extends ConsumerState<_WaitingActions> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('처리하지 못했어요. 잠시 후 다시 시도해 주세요.')),
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _withdraw() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: GuardianHomeKeys.withdrawConfirm,
        title: const Text('연결 요청을 취소할까요?'),
        content: const Text(
          // What happens to the parent's side first: the number they may be
          // holding, and the question that may be on their screen.
          '보내신 번호는 더 이상 쓸 수 없게 되고, 부모님 폰에 떠 있던 질문도 사라져요.\n'
          '언제든 처음부터 다시 연결하실 수 있어요.',
          style: TextStyle(fontSize: 14.5, height: 1.55),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('아니요, 기다릴게요'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('요청 취소하기'),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;
    await _run(
      () => ref
          .read(guardianPairingControllerProvider.notifier)
          .withdrawRequest(widget.seniorProfileId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.seniorName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.expired) ...[
          const SizedBox(height: 16),
          GuardianPrimaryButton(
            key: GuardianHomeKeys.reissueInvite,
            label: '번호 다시 만들기',
            icon: Icons.refresh_rounded,
            onPressed: _busy
                ? null
                : () => _run(() async {
                    await ref
                        .read(guardianPairingControllerProvider.notifier)
                        .reissueInvite(
                          seniorProfileId: widget.seniorProfileId,
                          displayName: name == null || name.isEmpty
                              ? '부모님'
                              : name,
                        );
                  }),
          ),
        ],
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: GuardianHomeKeys.withdrawRequest,
            onPressed: _busy ? null : _withdraw,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.guardianInkSoft,
              padding: EdgeInsets.zero,
            ),
            child: const Text(
              '연결 요청 취소하기',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }
}

/// One thing connecting a parent gives the guardian, on the empty page.
///
/// A tinted mark rather than a number, for the reason the sign-in screen
/// already gives: numbered badges read as steps, and these are not done in
/// any order.
class _Promise extends StatelessWidget {
  const _Promise({
    super.key,
    required this.icon,
    required this.tint,
    required this.ink,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final Color tint;
  final Color ink;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: tint,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, size: 19, color: ink),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                    letterSpacing: -0.3,
                    color: AppColors.guardianInk,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: const TextStyle(
                    fontSize: 13.5,
                    height: 1.45,
                    color: AppColors.guardianInkSoft,
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

/// How much of the free week is left, on the card it applies to.
///
/// Amber rather than grey: it is the one line on this tab with a deadline,
/// and a guardian who misses it finds the most reassuring thing on the screen
/// gone one morning with no explanation they can connect it to.
class _TrialLine extends StatelessWidget {
  const _TrialLine({required this.daysLeft});

  final int daysLeft;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.guardianTintAmber,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.schedule_rounded,
            size: 18,
            color: AppColors.guardianTintAmberInk,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              // `오늘까지` rather than `0일 남음`, which reads as already
              // over. Calendar days, the same way 안부 신호 counts them.
              daysLeft == 0
                  ? '폰 상태를 보여 드리는 무료 기간이 오늘까지예요.'
                  : '폰 상태를 보여 드리는 무료 기간이 $daysLeft일 남았어요.',
              style: const TextStyle(
                fontSize: 13,
                height: 1.5,
                fontWeight: FontWeight.w700,
                color: AppColors.guardianTintAmberInk,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
