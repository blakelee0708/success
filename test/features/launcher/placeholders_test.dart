import 'package:flutter_test/flutter_test.dart';
import '../../support/pump_app.dart';

Future<void> _gotoEasyHome(WidgetTester tester) async {
  await enterSeniorFlow(tester);
  await tester.tap(find.text('정말 쉬운 화면'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('가족 연결 opens the real connect screen', (tester) async {
    // Phase 4 replaced the placeholder: the parent's phone can now join a
    // profile by the number their child reads out.
    await _gotoEasyHome(tester);
    await tester.tap(find.text('가족 연결'));
    await tester.pumpAndSettle();
    expect(find.text('자녀분에게\n이 번호를 불러 주세요'), findsOneWidget);
  });

  testWidgets('더 보기 opens 설정', (tester) async {
    // It used to open a screen holding one button and a line saying apps
    // cannot be added yet — a screen that existed to be passed through. And
    // until it led here, 정말 쉬운 화면 had no route to 설정 at all, so a
    // senior on the easy screen could not change their text size.
    await _gotoEasyHome(tester);
    await tester.tap(find.text('더 보기'));
    await tester.pumpAndSettle();

    expect(find.text('앱 설정하기'), findsOneWidget);
    expect(find.text('글씨 크기 조절하기'), findsOneWidget);
  });
}
