import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../care/application/care_controller.dart';
import 'guardian_home_apps_controller.dart';

/// How many times this guardian may still rearrange their parent's home
/// screen from their own phone.
///
/// **The senior's own phone is never limited**, and nothing here reaches it.
/// This prices one thing: changing somebody else's home screen remotely,
/// which is a convenience the guardian bought rather than something their
/// parent needs.
///
/// Lifetime rather than monthly, which the owner chose knowing the cost: a
/// guardian who spends both while setting up cannot fix a wrong button from
/// their own phone afterwards. What keeps that from stranding anyone is the
/// rule above - 앱 설정하기 is two presses from the parent's home screen.
class HomeEditAllowance {
  const HomeEditAllowance({
    required this.unlimited,
    required this.used,
    required this.limit,
  });

  final bool unlimited;
  final int used;
  final int limit;

  int get left => unlimited ? 0 : (limit - used).clamp(0, limit);

  bool get canEdit => unlimited || left > 0;

  /// Whether to say anything at all. An unlimited family does not need a
  /// counter on a screen they will never hit the end of.
  bool get shouldShow => !unlimited;
}

/// Kept in step with `public.guardian_home_edits_free()`. Two copies, because
/// the server has to enforce it and the screen has to say it before a save
/// is attempted - a guardian told only by a refusal has already lost the
/// arrangement they made.
const guardianHomeEditsFree = 2;

final homeEditAllowanceProvider = Provider<HomeEditAllowance>((ref) {
  final profile = ref.watch(selectedSeniorProfileProvider);
  final care = ref.watch(careStateProvider).value;
  return HomeEditAllowance(
    unlimited: care?.stage == CareStage.active,
    used: profile?.guardianHomeEdits ?? 0,
    limit: guardianHomeEditsFree,
  );
});
