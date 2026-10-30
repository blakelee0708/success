import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/data/senior_settings_repository.dart';

import '../support/pump_app.dart';

/// Settings shaped the way a previous run would have left them, so pumping
/// the app is a restart rather than a fresh install.
Map<String, Object> _saved(String mode) => {
  SharedPreferencesSeniorSettingsRepository.storageKey: jsonEncode({
    'screenMode': mode,
    'fontSize': 'normal',
    'apps': <Object?>[],
  }),
};

void main() {
  testWidgets('a senior who already chose easy mode skips the splash', (
    tester,
  ) async {
    await pumpApp(tester, prefs: _saved('easy'));
    await tester.pumpAndSettle();

    // The app becomes the phone's launcher: pressing Home must land here.
    expect(find.text('사진 보기'), findsOneWidget);
    expect(find.text('눌러보세요'), findsNothing);
  });

  testWidgets('a senior who chose detailed mode lands on that home', (
    tester,
  ) async {
    await pumpApp(tester, prefs: _saved('detailed'));
    await tester.pumpAndSettle();

    expect(find.text('카카오톡'), findsOneWidget);
    expect(find.text('눌러보세요'), findsNothing);
  });

  testWidgets('a fresh install still sees the splash', (tester) async {
    await pumpApp(tester);
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('눌러보세요'), findsOneWidget);
  });
}
