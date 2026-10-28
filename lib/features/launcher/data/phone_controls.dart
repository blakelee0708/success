import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/device_status.dart';
import '../../../domain/internet_status.dart';
import 'app_launcher.dart';

/// The two things about their own phone a senior can change from the launcher.
///
/// Both are free on Android: no runtime permission, no manifest permission,
/// nothing for Play to review. The manifest still declares no `uses-permission`
/// at all, and `privacy_policy_test` holds it that way.
///
/// What each one leaves out is the load-bearing part.
///
///  * **무음 is not offered.** `RINGER_MODE_SILENT` needs
///    `ACCESS_NOTIFICATION_POLICY`, which is not a runtime dialog but a system
///    settings screen the senior has to find and switch on by themselves -
///    the same ask as the home-app chooser, and this app exists because they
///    cannot make it. And the guardian installs this because 엄마가 전화를 안
///    받아, whose first cause is a phone left on silent. A launcher for that
///    family has no business handing them the way back into it.
///  * **Wi-Fi is shown, never switched.** `setWifiEnabled` has been a no-op
///    for ordinary apps since Android 10, and mobile data needs carrier
///    privileges, so there is no toggle to write - not from here and not from
///    the guardian's phone either. The system panel is what Google gave
///    instead. It needs no permission and it slides over this app rather than
///    sending the senior off into Settings.
abstract interface class PhoneControls {
  /// False when the phone refused, rather than an exception nobody catches.
  ///
  /// Do Not Disturb can block the change, and the moment it blocks is the one
  /// where the senior is trying to get their ringer back - so the caller is
  /// told plainly instead of being left to assume it worked.
  Future<bool> setRinger(RingerMode mode);

  /// The phone's own internet sheet. False when the phone has none to open.
  Future<bool> openInternetPanel();

  /// Wi-Fi and mobile data are **two destinations, not one**, which was
  /// learnt from a photograph of a real Galaxy: the panel above arrived there
  /// as Settings > 연결, where Wi-Fi is a switch at the top and mobile data
  /// is not on the screen at all - two taps further in, behind 모바일
  /// 네트워크 or 데이터 사용. A senior sent there to turn their data on never
  /// finds it. Which door they need is decided on our own card instead.
  Future<bool> openWifiSettings();
  Future<bool> openMobileDataSettings();

  /// What the phone is on right now, so the card can say something true
  /// before it offers a door. [InternetStatus.unknown] is the honest answer
  /// on a phone that would not say, and the card treats it as *offer both*.
  Future<InternetStatus> internetStatus();
}

class MethodChannelPhoneControls implements PhoneControls {
  const MethodChannelPhoneControls();

  @override
  Future<bool> setRinger(RingerMode mode) async {
    // 무음 never reaches the platform. The interface says so and this is where
    // it is enforced, because a caller that gets it wrong would otherwise hit
    // a SecurityException on a real phone and nowhere else.
    if (mode == RingerMode.silent) return false;
    return _call('setRingerMode', {'mode': mode.name});
  }

  @override
  Future<bool> openInternetPanel() => _call('openInternetPanel', null);

  @override
  Future<bool> openWifiSettings() => _call('openWifiSettings', null);

  @override
  Future<bool> openMobileDataSettings() =>
      _call('openMobileDataSettings', null);

  @override
  Future<InternetStatus> internetStatus() async {
    try {
      final name = await MethodChannelAppLauncher.channel.invokeMethod<String>(
        'internetStatus',
      );
      return InternetStatus.fromName(name);
    } on PlatformException {
      return InternetStatus.unknown;
    } on MissingPluginException {
      return InternetStatus.unknown;
    }
  }

  Future<bool> _call(String method, Map<String, Object?>? args) async {
    try {
      final ok = await MethodChannelAppLauncher.channel.invokeMethod<bool>(
        method,
        args,
      );
      return ok ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      // `flutter test` is a phone with no channel at all. It did not refuse,
      // it was never asked - but to the caller the honest answer is the same:
      // nothing changed.
      return false;
    }
  }
}

/// What the tests and the review screenshots use.
class FakePhoneControls implements PhoneControls {
  FakePhoneControls({this.accepts = true, this.hangs = false});

  /// A phone that takes the call and does nothing, which is what Do Not
  /// Disturb looks like from here.
  FakePhoneControls.refusing() : accepts = false, hangs = false;

  /// A channel that never answers. It throws nothing, so catching is not
  /// enough and the caller must not be waiting on it - the trap this codebase
  /// has now hit four times.
  FakePhoneControls.silent() : accepts = false, hangs = true;

  final bool accepts;
  final bool hangs;

  final ringerCalls = <RingerMode>[];
  int panelCalls = 0;
  int wifiCalls = 0;
  int dataCalls = 0;

  /// What the fake phone is on. Tests set it to drive the card's three
  /// sentences.
  InternetStatus status = InternetStatus.wifi;

  @override
  Future<bool> setRinger(RingerMode mode) {
    ringerCalls.add(mode);
    if (hangs) return Completer<bool>().future;
    return Future.value(accepts && mode != RingerMode.silent);
  }

  @override
  Future<bool> openInternetPanel() {
    panelCalls++;
    if (hangs) return Completer<bool>().future;
    return Future.value(accepts);
  }

  @override
  Future<bool> openWifiSettings() {
    wifiCalls++;
    if (hangs) return Completer<bool>().future;
    return Future.value(accepts);
  }

  @override
  Future<bool> openMobileDataSettings() {
    dataCalls++;
    if (hangs) return Completer<bool>().future;
    return Future.value(accepts);
  }

  @override
  Future<InternetStatus> internetStatus() {
    if (hangs) return Completer<InternetStatus>().future;
    return Future.value(status);
  }
}

final phoneControlsProvider = Provider<PhoneControls>(
  (ref) => const MethodChannelPhoneControls(),
);
