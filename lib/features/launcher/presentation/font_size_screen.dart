import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../domain/senior_settings.dart';
import '../application/senior_settings_controller.dart';

/// 글씨 크기 조절하기 — three steps, each rendered at the size it selects.
///
/// A slider would be the obvious control and the wrong one: the person setting
/// this cannot comfortably read the current size, so the choice has to be
/// legible before it is made rather than after.
class FontSizeScreen extends ConsumerWidget {
  const FontSizeScreen({super.key});

  static const _labels = {
    FontSize.normal: '보통',
    FontSize.large: '크게',
    FontSize.extraLarge: '아주 크게',
    FontSize.largest: '제일 크게',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(seniorSettingsControllerProvider).value;
    final current = settings?.fontSize ?? FontSize.normal;

    return Scaffold(
      appBar: AppBar(title: const Text('글씨 크기')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          for (final size in FontSize.values)
            ListTile(
              selected: size == current,
              selectedTileColor: AppColors.seniorSurface,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 12,
              ),
              title: Text(
                _labels[size]!,
                // Each option previews its own size, so it must ignore the
                // size currently in force — otherwise the two multiply and
                // 아주 크게 overflows its row when it is already selected.
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                  fontSize: 22 * size.scale,
                  fontWeight: FontWeight.w700,
                  color: AppColors.seniorOnSurface,
                ),
              ),
              trailing: size == current
                  ? const Icon(
                      Icons.check_circle,
                      size: 32,
                      color: AppColors.seniorPrimary,
                    )
                  : null,
              onTap: () => ref
                  .read(seniorSettingsControllerProvider.notifier)
                  .setFontSize(size),
            ),
        ],
      ),
    );
  }
}
