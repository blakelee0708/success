import 'package:supabase_flutter/supabase_flutter.dart' as sb;

/// What came of asking the server to make the parent's phone loud.
///
/// Five outcomes rather than a bool, and the reason is the moment this button
/// is pressed: the guardian is already worried, and **silence is the one
/// answer that makes them press it again.** A phone that was never connected,
/// a phone whose address died with a reinstall, a subscription that is not on
/// and a sender that is broken all look identical from behind a spinner, and
/// only one of them is the guardian's to do anything about.
sealed class RingOutcome {
  const RingOutcome();
}

/// FCM took it. The phone makes a noise now, or FCM holds it for the five
/// minutes the sender asked for and it arrives when the phone wakes.
class RingSent extends RingOutcome {
  const RingSent();
}

/// There was nothing to send to. [miss] says which kind of nothing, because
/// the two need different sentences and neither is a fault.
class RingMissed extends RingOutcome {
  const RingMissed(this.miss);

  final RingMiss miss;
}

enum RingMiss {
  /// The parent's phone has never checked in, so it has no address yet. The
  /// dashboard already says this in its own words; the sheet agrees with it
  /// rather than inventing a second explanation.
  neverConnected,

  /// There was an address and it is dead — a reinstall, or a new handset.
  /// The next check-in writes a fresh one, so this fixes itself and is not
  /// worth alarming anyone about in those words.
  unreachable,
}

/// The gate said no: not a guardian of this parent, a link that was removed,
/// no subscription, or a senior who has not agreed.
///
/// [message] is the server's own sentence and is shown exactly as it came.
/// Rewording it here would put the rule's explanation in two places, and the
/// copy a guardian actually reads would be the one no test can reach.
class RingRefused extends RingOutcome {
  const RingRefused(this.message);

  final String message;
}

/// The sender itself could not authenticate to Google.
///
/// Kept apart from [RingMissed] on purpose. This one means **every ring for
/// every family is failing**, and collapsed into "the phone did not answer"
/// it would look like one parent's phone being off, forever, with nobody
/// going to look.
class RingSenderDown extends RingOutcome {
  const RingSenderDown();
}

/// Asks the server to ring the parent's phone.
///
/// Every question about whether the ring is allowed is answered in SQL by
/// `request_phone_ring`, and the Edge Function in front of it only sends. So
/// this has one method and no rules of its own.
abstract interface class RingRepository {
  Future<RingOutcome> ring({
    required String seniorProfileId,
    String? message,
  });
}

class SupabaseRingRepository implements RingRepository {
  const SupabaseRingRepository(this._client);

  final sb.SupabaseClient _client;

  @override
  Future<RingOutcome> ring({
    required String seniorProfileId,
    String? message,
  }) async {
    final trimmed = message?.trim();
    try {
      final res = await _client.functions.invoke(
        'ring-phone',
        body: {
          'senior_profile_id': seniorProfileId,
          // Left out rather than sent empty: the gate substitutes
          // `전화 한 번만 주세요.` for a blank, and that default belongs next
          // to the rule, not here.
          if (trimmed != null && trimmed.isNotEmpty) 'message': trimmed,
        },
      );
      final data = res.data;
      if (data is Map && data['delivered'] == true) return const RingSent();
      return RingMissed(
        data is Map && data['reason'] == 'no_device'
            ? RingMiss.neverConnected
            : RingMiss.unreachable,
      );
    } on sb.FunctionException catch (e) {
      return _outcomeOf(e);
    }
  }

  /// A non-2xx reply, read by status rather than by the `reason` string.
  ///
  /// `reason` is for whoever is debugging this and may change; the statuses
  /// are what the function's own comments commit to.
  static RingOutcome _outcomeOf(sb.FunctionException e) {
    final details = e.details;
    final said = details is Map ? details['error'] : null;
    return switch (e.status) {
      // The gate's refusals, and a missing session, which is one of them.
      401 || 403 => RingRefused(
        said is String && said.isNotEmpty ? said : '지금은 보낼 수 없어요.',
      ),
      // 502 is FCM refusing the send for a reason that is not a dead token.
      // The phone is the half that did not answer, so it reads as one.
      502 => const RingMissed(RingMiss.unreachable),
      // 500 is `sender_unconfigured`, and so is anything unexpected: both
      // mean nobody's ring is getting out and somebody has to be told.
      _ => const RingSenderDown(),
    };
  }
}

/// One call that was made, so a test can check what went out.
class RingCall {
  const RingCall({required this.seniorProfileId, this.message});

  final String seniorProfileId;
  final String? message;
}

/// What a build with no project gets, and what the tests use.
///
/// It answers [RingSent] by default so a keyless build can walk the whole
/// screen. Set [outcome] to rehearse the four that are harder to reach.
class InMemoryRingRepository implements RingRepository {
  InMemoryRingRepository({this.outcome = const RingSent()});

  RingOutcome outcome;

  final calls = <RingCall>[];

  @override
  Future<RingOutcome> ring({
    required String seniorProfileId,
    String? message,
  }) async {
    calls.add(RingCall(seniorProfileId: seniorProfileId, message: message));
    return outcome;
  }
}
