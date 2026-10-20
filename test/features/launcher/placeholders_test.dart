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

  testWidgets('더 보기 opens the more-apps placeholder', (tester) async {
    await _gotoEasyHome(tester);
    await tester.tap(find.text('더 보기'));
    await tester.pumpAndSettle();
    expect(find.text('더 많은 앱을 곧 추가할 수 있어요'), findsOneWidget);
  });
}
