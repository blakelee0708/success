import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/clay_pad.dart';

/// 더 보기 — the easy screen's one way off its four tiles.
///
/// Adding apps is still Phase 2's unfinished edge, but 설정 is not: until now
/// 정말 쉬운 화면 had no route to it at all, so a senior on the easy screen
/// could not change their text size — the setting the whole app is sold on —
/// and could not answer the home-app question if they had said 나중에.
/// 자세한 화면 reaches 설정 from a tile; this is the easy screen's version.
class MoreAppsPlaceholder extends StatelessWidget {
  const MoreAppsPlaceholder({super.key});

  static const settingsKey = Key('more-apps-settings');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.seniorBackground,
      appBar: AppBar(
        backgroundColor: AppColors.seniorBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          '더 보기',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.6,
            color: AppColors.seniorInk,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            SizedBox(
              key: MoreAppsPlaceholder.settingsKey,
              height: 108,
              child: ClayPad(
                light: AppColors.seniorMoreLight,
                face: AppColors.seniorMore,
                deep: AppColors.seniorMoreDeep,
                wall: AppColors.seniorMoreWall,
                onTap: () => context.push(Routes.seniorSettings),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.settings, size: 40, color: Colors.white),
                        SizedBox(width: 14),
                        Text(
                          '설정',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.6,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              '더 많은 앱을 곧 추가할 수 있어요',
              style: TextStyle(
                fontSize: 19,
                height: 1.5,
                color: AppColors.seniorInkMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
