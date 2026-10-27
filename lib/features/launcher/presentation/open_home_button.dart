import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/app_category.dart';
import '../../../domain/launcher_app.dart';
import '../application/senior_settings_controller.dart';
import '../data/app_launcher.dart';
import '../data/phone_dialer.dart';
import 'widgets/installed_app_picker.dart';

/// What pressing a home button does, on both screens.
///
/// Shared because it is one behaviour, and the two screens had already grown
/// identical copies of it — a third branch in each would have been the point
/// they drifted.
Future<void> openHomeButton(
  BuildContext context,
  WidgetRef ref,
  LauncherApp app,
) async {
  // An app button the guardian put there and nobody has filled in yet. 경로 2:
  // the guardian creates the slot from their own phone, which is the step
  // their parent cannot do, and the parent presses it once and picks, which
  // is the step they can. The list of what is installed never leaves this
  // phone, which is why the guardian could only make the slot.
  if (app.awaitingChoice) {
    final picked = await askForInstalledApp(context, ref);
    if (picked == null) return;
    await ref
        .read(seniorSettingsControllerProvider.notifier)
        .chooseInstalledApp(
          app.id,
          label: picked.label,
          packageName: picked.packageName,
          iconBytes: picked.icon,
        );
    return;
  }

  // A person is dialled, not opened. `tel:` resolves to ACTION_DIAL, so the
  // keypad appears with the number in it and the senior presses call —
  // exactly as 119 does, and for the same reason.
  if (app.opensDialer) {
    await ref.read(phoneDialerProvider).openDialer(app.phoneNumber!);
    return;
  }
  // A contact the guardian has not finished — a name with no number — has
  // nothing to dial. Opening the dialer blank looks broken rather than
  // unfinished, so it does nothing at all.
  if (app.category.isContact) return;

  final opened = await ref
      .read(appLauncherProvider)
      .open(launchRequestForApp(app));
  if (opened || !context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text('${app.label}을(를) 열 수 없어요. 자녀분께 말씀해 주세요.')),
    );
}
