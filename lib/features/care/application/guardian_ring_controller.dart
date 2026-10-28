import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../../data/remote/ring_repository.dart';
import '../../guardian/application/guardian_home_apps_controller.dart';

/// Where the guardian's 소리 울리기 stands, on their own screen.
sealed class RingSendState {
  const RingSendState();
}

class RingIdle extends RingSendState {
  const RingIdle();
}

class RingSending extends RingSendState {
  const RingSending();
}

class RingSettled extends RingSendState {
  const RingSettled(this.outcome);

  final RingOutcome outcome;
}

/// Sends the ring and keeps what came back.
///
/// The result is state rather than a return value because the sheet has to go
/// on saying it: a guardian who presses 울리기 and is handed back an unchanged
/// form has no way of telling a ring that worked from one that was swallowed,
/// and will press again.
class GuardianRingController extends Notifier<RingSendState> {
  @override
  RingSendState build() => const RingIdle();

  Future<void> send(String message) async {
    if (state is RingSending) return;
    final profile = ref.read(selectedSeniorProfileProvider);
    if (profile == null) return;
    state = const RingSending();
    // A blank form field means *no message*, and that is decided here rather
    // than left for each repository to re-derive. The gate substitutes
    // 전화 한 번만 주세요. for an absent one, so an empty string sent through
    // would be a second way of saying the same thing with nothing enforcing
    // that it keeps meaning it.
    final written = message.trim();
    final outcome = await ref
        .read(ringRepositoryProvider)
        .ring(
          seniorProfileId: profile.id,
          message: written.isEmpty ? null : written,
        );
    state = RingSettled(outcome);
  }

  /// Called when the sheet opens, so a result from last time is not the first
  /// thing the guardian reads.
  void reset() => state = const RingIdle();
}

final guardianRingControllerProvider =
    NotifierProvider<GuardianRingController, RingSendState>(
      GuardianRingController.new,
    );
