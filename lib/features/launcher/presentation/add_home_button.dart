import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/app_category.dart';
import '../application/senior_settings_controller.dart';
import 'widgets/category_picker.dart';
import 'widgets/contact_dialog.dart';
import 'widgets/installed_app_picker.dart';
import 'widgets/name_dialog.dart';

/// Adds a button, asking only what cannot be worked out.
///
/// Shared by 앱 설정하기 and by the hollow slot on 자세한 화면, because they
/// are the same act and the slot used to reach it the long way round — out to
/// the settings list, down to 버튼 추가하기, and only then here.
///
/// Returns the label added, or null if the senior backed out at any step.
Future<String?> addHomeButton(BuildContext context, WidgetRef ref) async {
  final category = await askForCategory(context);
  if (category == null || !context.mounted) return null;

  // An app already on the phone brings its own name and its own icon, so
  // there is nothing left to ask. Two presses and no keyboard.
  if (category == AppCategory.installed) {
    final picked = await askForInstalledApp(context, ref);
    if (picked == null) return null;
    await ref
        .read(seniorSettingsControllerProvider.notifier)
        .addApp(
          label: picked.label,
          category: category,
          packageName: picked.packageName,
          iconBytes: picked.icon,
        );
    return picked.label;
  }

  // A person needs a number as well as a name, and there is no sensible
  // default for either.
  if (category.isContact) {
    final draft = await askForContact(context);
    if (draft == null) return null;
    await ref
        .read(seniorSettingsControllerProvider.notifier)
        .addApp(
          label: draft.name,
          category: category,
          phoneNumber: draft.number,
        );
    return draft.name;
  }

  final name = await askForButtonName(
    context,
    title: '버튼 추가하기',
    initial: category.defaultLabel,
  );
  if (name == null) return null;
  await ref
      .read(seniorSettingsControllerProvider.notifier)
      .addApp(label: name, category: category);
  return name;
}
