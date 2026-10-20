import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/clock.dart';
import '../../../core/format/korean_clock.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/family_message.dart';
import '../../../domain/senior_profile.dart';
import '../../../domain/senior_settings.dart';
import '../application/guardian_home_apps_controller.dart';
import '../application/guardian_session_controller.dart';
import '../../care/presentation/guardian_care_tab.dart';
import '../../messages/application/message_controller.dart';
import '../../messages/presentation/guardian_message_tab.dart';
import 'guardian_family_tab.dart';
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
class GuardianDashboardScreen extends StatefulWidget {
  const GuardianDashboardScreen({super.key});

  @override
  State<GuardianDashboardScreen> createState() =>
      _GuardianDashboardScreenState();
}

class _GuardianDashboardScreenState extends State<GuardianDashboardScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    // The app runs on the senior theme by default; the guardian side is a
    // different persona on a different phone — 04_SCREEN_SPEC gives it a
    // white background and a blue accent rather than the warm launcher palette.
    return Theme(data: AppTheme.guardian, child: _build(context));
  }

  Widget _build(BuildContext context) {
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
              const GuardianLauncherTab(),
              const GuardianMessageTab(),
              const GuardianCareTab(),
              const GuardianFamilyTab(),
            ],
          ),
        ),
      ),
      bottomNavigationBar: GuardianNavBar(
        selectedIndex: _index,
        onSelected: (i) => setState(() => _index = i),
        destinations: const [
          GuardianDestination(
            label: '홈',
            icon: Icons.home_outlined,
            activeIcon: Icons.home_rounded,
          ),
          GuardianDestination(
            label: '홈 화면',
            icon: Icons.grid_view_outlined,
            activeIcon: Icons.grid_view_rounded,
          ),
          GuardianDestination(
            label: '메시지',
            icon: Icons.chat_bubble_outline,
            activeIcon: Icons.chat_bubble_rounded,
          ),
          GuardianDestination(
            label: '돌봄',
            icon: Icons.favorite_outline,
            activeIcon: Icons.favorite_rounded,
          ),
          GuardianDestination(
            label: '가족',
            icon: Icons.people_outline,
            activeIcon: Icons.people_rounded,
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
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 25,
            height: 1.3,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.8,
            color: AppColors.guardianInk,
          ),
        ),
        if (lede != null) ...[
          const SizedBox(height: 5),
          Text(
            lede!,
            style: const TextStyle(
              fontSize: 14,
              letterSpacing: -0.2,
              color: AppColors.guardianInkFaint,
            ),
          ),
        ],
        const SizedBox(height: 22),
        ...children,
      ],
    );
  }
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

    if (profiles.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (profile == null) {
      return const _TabScaffold(
        title: '부모님 연결하기',
        children: [
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
                SizedBox(height: 8),
                Text(
                  '가족 탭에서 부모님을 추가하면 연결 번호가 나옵니다. '
                  '그 번호를 부모님 폰의 가족 연결 화면에 넣으면 연결돼요.',
                  style: TextStyle(
                    fontSize: 14.5,
                    height: 1.55,
                    color: AppColors.guardianInkSoft,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final device = ref.watch(selectedSeniorDeviceProvider).value;
    final quota = ref.watch(messageQuotaProvider).value;
    final apps = ref.watch(guardianHomeAppsProvider).value ?? const [];
    final messages = ref.watch(conversationProvider).value ?? const [];
    final now = ref.watch(nowProvider)();
    final lastSeen = device?.lastSeenAt;
    final phone = device?.deviceLabel ?? device?.platform;

    return _TabScaffold(
      title: profile.displayName,
      lede: lastSeen == null
          ? '폰이 아직 연결되기 전이에요'
          : '폰은 잘 켜져 있어요',
      children: [
        if ((profiles.value?.length ?? 0) > 1)
          _Card(child: _ParentSwitcher(profiles: profiles.value!)),
        GuardianHeroCard(
          key: GuardianHomeKeys.hero,
          subject: phone == null
              ? profile.displayName
              : '${profile.displayName} · $phone',
          online: lastSeen != null,
          // Says the time, or says there is none. It does not round a missing
          // check-in up to something comforting.
          headline: lastSeen == null ? '아직' : koreanTime(lastSeen),
          caption: lastSeen == null ? '연결되기 전이에요' : '까지 쓰고 계셨어요',
          metric: quota == null || quota.unlimited
              ? '무제한'
              : '${quota.textLeft}번',
          metricCaption: '메시지 남음',
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
            GuardianActionCard(
              label: '안심 케어\n알아보기',
              detail: '준비 중',
              icon: Icons.favorite_rounded,
              tint: AppColors.guardianTintGreen,
              tintInk: AppColors.guardianTintGreenInk,
              onTap: () => onOpenTab(3),
            ),
            GuardianActionCard(
              label: '가족\n초대하기',
              detail: '형제도 무료',
              icon: Icons.people_rounded,
              tint: AppColors.guardianTintAmber,
              tintInk: AppColors.guardianTintAmberInk,
              onTap: () => onOpenTab(4),
            ),
          ],
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
                  null => '아직 고르지 않으셨어요',
                },
              ),
              const GuardianFact(label: '배터리 · 소리 · 인터넷', value: '준비 중'),
            ],
          ),
        ),
      ],
    );
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
  static const switcher = Key('guardian-home-switcher');
  static const hero = Key('guardian-home-hero');
}

class _ParentSwitcher extends ConsumerWidget {
  const _ParentSwitcher({required this.profiles});

  final List<SeniorProfile> profiles;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedSeniorProfileProvider);
    return Row(
      key: GuardianHomeKeys.switcher,
      children: [
        const Text('부모님', style: TextStyle(fontSize: 15)),
        const Spacer(),
        DropdownButton<String>(
          value: selected?.id,
          underline: const SizedBox.shrink(),
          items: [
            for (final profile in profiles)
              DropdownMenuItem(value: profile.id, child: Text(profile.displayName)),
          ],
          onChanged: (id) {
            if (id != null) {
              ref.read(selectedSeniorProfileIdProvider.notifier).select(id);
            }
          },
        ),
      ],
    );
  }
}
