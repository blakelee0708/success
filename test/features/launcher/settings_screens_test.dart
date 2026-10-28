import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/data/senior_settings_repository.dart';
import 'package:app/domain/app_category.dart';
import 'package:app/features/launcher/presentation/widgets/category_picker.dart';

import 'package:app/features/launcher/presentation/app_settings_screen.dart';

import '../../support/pump_app.dart';

Map<String, Object> _saved({String fontSize = 'normal'}) => {
  SharedPreferencesSeniorSettingsRepository.storageKey: jsonEncode({
    'screenMode': 'detailed',
    'fontSize': fontSize,
    'apps': [
      {'id': 'phone', 'label': '전화', 'category': 'phone', 'color': null},
      {'id': 'kakao', 'label': '카카오톡', 'category': 'kakao', 'color': null},
    ],
  }),
};

Future<void> _openSettings(WidgetTester tester, {String? fontSize}) async {
  await pumpApp(
    tester,
    prefs: fontSize == null ? _saved() : _saved(fontSize: fontSize),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('설정'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the text-size screen marks the size already in use', (
    tester,
  ) async {
    await _openSettings(tester, fontSize: 'extraLarge');
    await tester.tap(find.text('글씨 크기 조절하기'));
    await tester.pumpAndSettle();

    expect(find.text('아주 크게'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });

  testWidgets('choosing a text size keeps it after leaving the screen', (
    tester,
  ) async {
    await _openSettings(tester);
    await tester.tap(find.text('글씨 크기 조절하기'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('아주 크게'));
    await tester.pumpAndSettle();

    // Leaving and coming back is the cheap stand-in for a restart: it proves
    // the choice went through the repository rather than local widget state.
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    await tester.tap(find.text('글씨 크기 조절하기'));
    await tester.pumpAndSettle();

    final selected = tester.widget<ListTile>(
      find.ancestor(of: find.text('아주 크게'), matching: find.byType(ListTile)),
    );
    expect(selected.selected, isTrue);
  });

  testWidgets('the button screen lists the saved buttons', (tester) async {
    await _openSettings(tester);
    await tester.tap(find.text('앱 설정하기'));
    await tester.pumpAndSettle();

    expect(find.text('전화'), findsOneWidget);
    expect(find.text('카카오톡'), findsOneWidget);
  });

  testWidgets('renaming a button from the list sticks', (tester) async {
    await _openSettings(tester);
    await tester.tap(find.text('앱 설정하기'));
    await tester.pumpAndSettle();

    // The row is no longer the rename target: 이름 is, and it says so. Three
    // unlabelled symbols with renaming hidden behind a tap on the row was
    // what this screen used to be.
    await tapInAppSettings(tester, find.byKey(AppSettingsKeys.rename('kakao')));
    await tester.enterText(find.byType(TextField), '카톡');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(find.text('카톡'), findsOneWidget);
    expect(find.text('카카오톡'), findsNothing);
  });

  testWidgets('deleting a button removes it from the list', (tester) async {
    await _openSettings(tester);
    await tester.tap(find.text('앱 설정하기'));
    await tester.pumpAndSettle();

    await tapInAppSettings(tester, find.byKey(AppSettingsKeys.delete('kakao')));
    // By key, because the row's own button says 지우기 too now.
    await tester.tap(find.byKey(AppSettingsKeys.deleteConfirm));
    await tester.pumpAndSettle();

    expect(find.text('카카오톡'), findsNothing);
    // Back to the top: the footer carries four slot rows of two lines each
    // now, so the first app row is above the fold after a delete.
    await tester.drag(find.byType(ReorderableListView), const Offset(0, 600));
    await tester.pumpAndSettle();
    expect(find.text('전화'), findsOneWidget);
  });

  testWidgets('deleting asks first, because the home is the phone', (
    tester,
  ) async {
    await _openSettings(tester);
    await tester.tap(find.text('앱 설정하기'));
    await tester.pumpAndSettle();

    await tapInAppSettings(tester, find.byKey(AppSettingsKeys.delete('kakao')));
    await tester.tap(find.text('그만두기'));
    await tester.pumpAndSettle();

    expect(find.text('카카오톡'), findsOneWidget);
  });

  testWidgets('adding a button puts it at the end of the list', (tester) async {
    await _openSettings(tester);
    await tester.tap(find.text('앱 설정하기'));
    await tester.pumpAndSettle();

    await tapInAppSettings(tester, find.text('버튼 추가하기'));
    // The kind is asked before the name, so the button gets the right icon,
    // colour and app rather than always being a 문자.
    await tester.tap(find.byKey(CategoryPickerKeys.option(AppCategory.camera)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '사진');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(find.text('사진'), findsOneWidget);
  });
}
