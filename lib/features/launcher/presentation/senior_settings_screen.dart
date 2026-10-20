import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';

/// 설정 — what the 자세한 화면 tab bar used to hold, now a screen of its own.
///
/// It had to become one when the tab bar went: this list is the only way into
/// 앱 설정하기 and 글씨 크기 조절하기 anywhere in the app, and 글씨 크기 is the
/// setting the app exists for. 더 보기 on the easy screen still leads to a
/// "곧 추가할 수 있어요" placeholder, so it is not a second way in.
class SeniorSettingsScreen extends StatelessWidget {
  const SeniorSettingsScreen({super.key});

  /// The last two are Phase 6 shapes and say so by being unpressable, rather
  /// than by opening a screen that apologises.
  static const _items = <(String, String?)>[
    ('앱 설정하기', Routes.appSettings),
    ('글씨 크기 조절하기', Routes.fontSize),
    ('가족 메시지', Routes.familyMessages),
    ('가족 연결 설정', Routes.familyLink),
    ('진동/벨소리 전환', null),
    ('잘보이네 사용하지 않기', null),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          for (final (label, route) in _items)
            Card(
              color: AppColors.seniorSurface,
              child: ListTile(
                title: Text(
                  label,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: route == null
                        ? AppColors.seniorTextSecondary
                        : AppColors.seniorOnSurface,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: route == null ? null : () => context.push(route),
              ),
            ),
        ],
      ),
    );
  }
}
