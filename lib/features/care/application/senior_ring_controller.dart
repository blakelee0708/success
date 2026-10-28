import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/emergency_sound.dart';

/// A request from the guardian to make this phone loud.
///
/// [message] is what the senior reads while it rings — who is asking and why.
/// It is not an optional extra sold on top of the sound: a phone that starts
/// screaming with no explanation is frightening, and an elderly person who
/// cannot tell a message from a fault is the person this app exists for.
class RingRequest {
  const RingRequest({required this.from, this.fromGuardianId, this.message});

  /// The guardian's name, as the family roster gives it.
  final String from;

  /// Which guardian, so the phone can offer to call **them** back rather
  /// than matching on a display name two siblings may share. Null on a push
  /// that arrived without one, and then no call button is offered: ringing
  /// the wrong child is worse than offering nothing.
  final String? fromGuardianId;

  /// Their own words, when they wrote any.
  final String? message;

  /// What the screen says when they wrote nothing. Never left blank.
  String get line =>
      message?.trim().isNotEmpty == true ? message!.trim() : '전화 한 번만 주세요.';
}

/// Whether this phone is ringing, and the only two things that can change it.
///
/// Null means silent. Nothing here is persisted: a ring is a moment, and a
/// phone that restarts mid-ring should come back quiet rather than resume
/// screaming at a senior who has no idea why.
class SeniorRingController extends Notifier<RingRequest?> {
  Timer? _stopAfter;

  /// How long it rings with nobody touching it.
  ///
  /// It has to end by itself. The phone may be in a bag in another room —
  /// which is exactly the case this feature is for — and a sound with no end
  /// is a flat battery and a frightened senior rather than a found phone. The
  /// guardian can send it again.
  static const maxDuration = Duration(seconds: 60);

  @override
  RingRequest? build() {
    ref.onDispose(() => _stopAfter?.cancel());
    return null;
  }

  void ring(RingRequest request) {
    _stopAfter?.cancel();
    state = request;
    _stopAfter = Timer(maxDuration, dismiss);
    _sound((s) => s.play());
  }

  /// Called however the ring ends — a tap anywhere, or the timer.
  ///
  /// Safe to call when nothing is ringing, because the screen calls it on
  /// dismissal without checking first.
  void dismiss() {
    _stopAfter?.cancel();
    _stopAfter = null;
    if (state == null) return;
    state = null;
    _sound((s) => s.stop());
  }

  /// The speaker is told, never waited for.
  ///
  /// A platform channel is not obliged to reply, and this one is reached
  /// through the launcher channel that `flutter test` leaves unanswered. The
  /// screen is the half that says who is asking and why, and it may not be
  /// held up by a speaker — on a phone whose launcher service has wedged,
  /// awaiting here would leave the senior with a silent phone and no message
  /// either. `MethodChannelEmergencySound` already swallows both channel
  /// exceptions, but a channel that simply never answers throws nothing at
  /// all, so catching is not enough; it has to not be awaited.
  void _sound(Future<void> Function(EmergencySound) call) {
    try {
      unawaited(call(ref.read(emergencySoundProvider)));
    } on Object {
      // Nothing on screen changes because of a speaker.
    }
  }
}

final seniorRingControllerProvider =
    NotifierProvider<SeniorRingController, RingRequest?>(
      SeniorRingController.new,
    );
