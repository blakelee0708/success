import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/clock.dart';
import '../../../domain/device_status.dart';
import 'app_launcher.dart';

/// Reads the parent's own phone: how much battery is left, whether it is on
/// the charger, and whether it will make a sound if somebody rings it.
///
/// All three are free on Android — no runtime permission, no manifest
/// permission, nothing for Play to review — which is why this is the second
/// capability of 안심 케어 to exist rather than the fourth. 위치 needs a
/// 위치기반서비스사업 신고 before it can ship at all; this needs nothing.
///
/// 인터넷 is deliberately absent. `ConnectivityManager` would mean asking for
/// `ACCESS_NETWORK_STATE`, and the question it answers is already answered by
/// the check-in itself: a reading that arrived is a reading that got through.
/// Carrying the permission to say it twice is not worth it.
abstract interface class DeviceStatusReader {
  /// Null when the platform cannot say. Under `flutter test` there is no
  /// channel at all, and callers must not read that as a reading of zero.
  Future<DeviceStatus?> read();
}

class MethodChannelDeviceStatusReader implements DeviceStatusReader {
  const MethodChannelDeviceStatusReader(this._now);

  /// The reading is stamped on this phone, at the moment it is taken. The
  /// server's `now()` would be the moment it *arrived*, which is a different
  /// thing on a phone that was offline for an hour.
  final DateTime Function() _now;

  @override
  Future<DeviceStatus?> read() async {
    try {
      final raw = await MethodChannelAppLauncher.channel
          .invokeMapMethod<String, Object?>('deviceStatus');
      if (raw == null) return null;
      final status = DeviceStatus(
        readAt: _now(),
        batteryPercent: switch (raw['batteryPercent']) {
          final int v when v >= 0 && v <= 100 => v,
          _ => null,
        },
        isCharging: switch (raw['isCharging']) {
          final bool v => v,
          _ => null,
        },
        ringer: DeviceStatus.ringerFrom(raw['ringer']),
      );
      // A map that answered none of the three is not a reading. Sending it
      // would overwrite a real one from this morning with an empty one.
      return status.isEmpty ? null : status;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}

/// What the tests and the review screenshots use.
class FakeDeviceStatusReader implements DeviceStatusReader {
  FakeDeviceStatusReader(this.status);

  FakeDeviceStatusReader.throwing() : status = null, throws = true;

  /// A channel that accepts the call and never answers — a wedged launcher
  /// service, and what `flutter test` does with an unmocked channel.
  FakeDeviceStatusReader.silent() : status = null, silent = true;

  final DeviceStatus? status;
  bool throws = false;
  bool silent = false;
  int reads = 0;

  @override
  Future<DeviceStatus?> read() async {
    reads++;
    if (throws) throw MissingPluginException();
    if (silent) return Completer<DeviceStatus?>().future;
    return status;
  }
}

final deviceStatusReaderProvider = Provider<DeviceStatusReader>(
  (ref) => MethodChannelDeviceStatusReader(ref.watch(nowProvider)),
);
