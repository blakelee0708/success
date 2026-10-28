import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/senior_link_store.dart';
import '../data/push_messaging.dart';
import 'senior_ring_controller.dart';

/// Turns a push from the family into the noise and the sentence that go with
/// it.
///
/// The payload is a **data message**, not a notification: a notification would
/// be drawn by Android in the status bar, which is the one place a senior who
/// cannot find their own contacts app will not look. What arrives here is
/// turned into [SeniorRingLayer], which covers the whole screen and says who
/// is asking before it says anything else.
///
/// ```
/// {"type": "ring", "from_id": "<uuid>", "from": "영희",
///  "message": "엄마 전화 좀 줘"}
/// ```
class PushRingListener {
  PushRingListener(this._ref);

  final Ref _ref;
  StreamSubscription<Map<String, String>>? _sub;

  /// Starts listening, but only on a phone that is a parent's.
  ///
  /// The guard is first and the stream is reached for *after* it, for the
  /// reason the presence reporter sets out at length: `HomeKeyListener` wraps
  /// the whole router, so this runs on the guardian's phone too, and building
  /// the senior half's dependencies there is what hung every guardian login
  /// test the last two times somebody forgot.
  Future<void> start() async {
    if (_sub != null) return;
    final link = await _ref.read(seniorLinkStoreProvider).load();
    if (link.seniorProfileId == null) return;
    _sub = _ref.read(pushMessagingProvider).messages().listen(_onPush);
  }

  Future<void> stop() async {
    final sub = _sub;
    _sub = null;
    await sub?.cancel();
  }

  void _onPush(Map<String, String> data) {
    if (data['type'] != 'ring') return;
    final from = data['from']?.trim();
    _ref
        .read(seniorRingControllerProvider.notifier)
        .ring(
          RingRequest(
            // A push that arrived without a name still rings. The guardian
            // pressed the button and has no way of learning it did nothing,
            // so dropping it silently is the one outcome worse than a
            // slightly vaguer line — and `가족` is true of whoever sent it.
            from: from == null || from.isEmpty ? '가족' : from,
            fromGuardianId: data['from_id']?.trim().isNotEmpty == true
                ? data['from_id']!.trim()
                : null,
            message: data['message'],
          ),
        );
  }
}

final pushRingListenerProvider = Provider<PushRingListener>((ref) {
  final listener = PushRingListener(ref);
  ref.onDispose(listener.stop);
  return listener;
});
