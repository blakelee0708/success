/// What the phone is connected through, for 인터넷's card.
///
/// Read only. **Nothing here switches anything**: `setWifiEnabled` has been a
/// no-op for ordinary apps since Android 10 and mobile data needs carrier
/// privileges, so the app can say what is happening and open the right
/// settings screen, and that is the whole of it.
enum InternetStatus {
  wifi,
  mobile,

  /// Ethernet, a dock, something else that is working. Rare on a phone, and
  /// it is not 'none' - telling a senior their internet is off while a page
  /// loads is worse than saying nothing specific.
  other,

  /// Nothing is connected.
  none,

  /// The phone would not say. A build with no `ACCESS_NETWORK_STATE`, or a
  /// channel that is not there - `flutter test` is such a phone.
  ///
  /// It is not treated as `none`. The card offers both doors and claims
  /// nothing, which is what it would do for an unknown answer anyway.
  unknown;

  static InternetStatus fromName(String? name) => switch (name) {
    'wifi' => InternetStatus.wifi,
    'mobile' => InternetStatus.mobile,
    'other' => InternetStatus.other,
    'none' => InternetStatus.none,
    _ => InternetStatus.unknown,
  };

  /// Whether the phone has internet at all. `unknown` is not a failure.
  bool get connected => this != none;
}
