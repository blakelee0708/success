import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/router/launch_gate.dart';
import 'package:app/domain/senior_settings.dart';

void main() {
  test('a device with nothing saved is sent to the splash', () {
    expect(
      launchDestinationFor(savedScreenMode: null, guardianSignedIn: false),
      LaunchDestination.splash,
    );
  });

  test('a senior who already chose a mode skips the splash', () {
    // The app becomes the phone's launcher, so pressing Home must not land
    // on a splash screen.
    expect(
      launchDestinationFor(
        savedScreenMode: ScreenMode.easy,
        guardianSignedIn: false,
      ),
      LaunchDestination.seniorHome,
    );
  });

  test('a signed-in guardian goes to the dashboard', () {
    expect(
      launchDestinationFor(savedScreenMode: null, guardianSignedIn: true),
      LaunchDestination.guardianDashboard,
    );
  });

  test(
    'a saved senior mode wins over a guardian session on the same device',
    () {
      // The senior's phone is the one that must never show a splash.
      expect(
        launchDestinationFor(
          savedScreenMode: ScreenMode.detailed,
          guardianSignedIn: true,
        ),
        LaunchDestination.seniorHome,
      );
    },
  );
}
