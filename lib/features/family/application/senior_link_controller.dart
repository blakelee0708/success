import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../../data/remote/senior_link_repository.dart';
import '../../../data/senior_link_store.dart';
import '../../../domain/senior_profile.dart';
import '../../../domain/senior_settings.dart';
import '../../launcher/application/senior_settings_controller.dart';
import '../../launcher/application/senior_settings_sync.dart';

/// The parent's phone, connecting itself to a profile.
///
/// Phase 4 connects by the profile's customer code — the guardian creates the
/// parent in their dashboard and reads the code out. Phase 5 replaces that with
/// the 4-digit code and the install link; this controller is the seam those
/// will plug into, which is why [connect] takes a code rather than a link.
class SeniorLinkController extends AsyncNotifier<SeniorLink> {
  @override
  Future<SeniorLink> build() => ref.watch(seniorLinkStoreProvider).load();

  /// Claims [customerCode] for this install.
  ///
  /// Throws [SeniorLinkException] with a message meant for the senior's screen;
  /// the caller shows it rather than a generic failure, because a mistyped code
  /// is the likely cause and it is the one thing they can fix.
  Future<SeniorProfile> connect(String customerCode) async {
    final link = state.value ?? await ref.read(seniorLinkStoreProvider).load();
    final profile = await ref
        .read(seniorLinkRepositoryProvider)
        .registerSeniorDevice(
          customerCode: customerCode,
          installId: link.installId,
          platform: defaultTargetPlatform.name,
        );

    final linked = link.copyWith(seniorProfileId: profile.id);
    await ref.read(seniorLinkStoreProvider).save(linked);
    state = AsyncData(linked);

    // Pull before push: a guardian may have arranged the home screen while
    // waiting for the parent to connect, and that arrangement is the newer
    // intent. `pull` leaves this phone's buttons alone when the profile has
    // none, so nothing is lost when it is the first device to connect.
    final settings = ref.read(seniorSettingsControllerProvider.notifier);
    if (!await settings.pullFromServer()) {
      await ref
          .read(seniorSettingsSyncProvider)
          .push(
            ref.read(seniorSettingsControllerProvider).value ??
                const SeniorSettings(),
          );
    }
    return profile;
  }
}

final seniorLinkControllerProvider =
    AsyncNotifierProvider<SeniorLinkController, SeniorLink>(
      SeniorLinkController.new,
    );
